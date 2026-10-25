//! IR optimisation, run between lowering and code generation.
//!
//! * Constant folding of integer expressions.
//! * A `ByVal` parameter that every caller passes the same constant, and the routine never
//!   writes, becomes that constant inside the routine.
//! * Straight-line propagation of constants held in a routine's own locals.
//! * Removal of stores to locals and parameters nothing reads, and of the matching arguments.
//!
//! Together these turn `SerialInit(115200)` into a handful of register writes instead of a
//! run-time 32-bit divide.

use crate::ir::*;
use crate::types::{Ty, WORD};
use std::collections::{HashMap, HashSet};

#[derive(Clone, Copy, PartialEq)]
enum Acc {
    Read,
    Write,
    Both,
}

/// Read-only walk over statements and expressions.
trait Visit {
    fn ex(&mut self, _: &Ex) {}
    fn place(&mut self, _: &Place, _: Acc) {}
    fn call(&mut self, _: FuncId, _: &[(Place, Ex)]) {}
    fn stmt(&mut self, _: &S) {}
}

fn w_idx<V: Visit>(v: &mut V, p: &Place) {
    if let Some(i) = &p.idx {
        w_ex(v, i);
    }
    if let Some(i) = &p.dbit {
        w_ex(v, i);
    }
}

fn w_place<V: Visit>(v: &mut V, p: &Place, a: Acc) {
    v.place(p, a);
    w_idx(v, p);
}

fn w_src<V: Visit>(v: &mut V, s: &StrSrc) {
    match s {
        StrSrc::Ram(p) => w_place(v, p, Acc::Read),
        StrSrc::Lit(_) => {}
        StrSrc::Char(e) => w_ex(v, e),
    }
}

fn w_ex<V: Visit>(v: &mut V, e: &Ex) {
    v.ex(e);
    match &e.k {
        ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => {}
        ExK::Load(p) | ExK::Addr(p) => w_idx(v, p),
        ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) => w_ex(v, x),
        ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => {
            w_ex(v, a);
            w_ex(v, b);
        }
        ExK::Call(f, args) => {
            v.call(*f, args);
            for (p, a) in args {
                w_idx(v, p);
                w_ex(v, a);
            }
        }
        ExK::StrEq(a, b) => {
            w_src(v, a);
            w_src(v, b);
        }
    }
}

fn w_block<V: Visit>(v: &mut V, b: &[S]) {
    for s in b {
        v.stmt(s);
        match &s.st {
            St::Assign(p, e) => {
                w_place(v, p, Acc::Write);
                w_ex(v, e);
            }
            St::Add(p, _) | St::SetBit(p, _) | St::ToggleBit(p) | St::Clear(p) | St::ClearMem(p, _) | St::Direction { place: p, .. } => w_place(v, p, Acc::Write),
            St::Copy { dst, src, .. } => {
                w_place(v, dst, Acc::Write);
                w_place(v, src, Acc::Read);
            }
            St::StrSet { dst, parts, .. } => {
                w_place(v, dst, Acc::Write);
                for p in parts {
                    w_src(v, p);
                }
            }
            St::Call(f, args) => {
                v.call(*f, args);
                for (p, a) in args {
                    w_idx(v, p);
                    w_ex(v, a);
                }
            }
            St::If(arms, other) => {
                for (c, b) in arms {
                    w_ex(v, c);
                    w_block(v, b);
                }
                w_block(v, other);
            }
            St::While(c, b) | St::Repeat(b, c) => {
                w_ex(v, c);
                w_block(v, b);
            }
            St::For { var, from, limit, body, .. } => {
                w_place(v, var, Acc::Both);
                w_ex(v, from);
                w_ex(v, limit);
                w_block(v, body);
            }
            St::Count { counter, body, step, .. } => {
                w_place(v, counter, Acc::Both);
                if let Some((p, _)) = step {
                    w_place(v, p, Acc::Both);
                }
                w_block(v, body);
            }
            St::Save { body, .. } => w_block(v, body),
            St::DelayUs(e) | St::DelayMs(e) => w_ex(v, e),
            St::Break | St::Continue | St::Return | St::Goto(_) | St::Label(_) | St::Asm(_) | St::Halt | St::Int { .. } => {}
            St::FlashSeek(_, _, e) => {
                if let Some(e) = e {
                    w_ex(v, e);
                }
            }
        }
    }
}

/// Post-order walk handing every expression (also those inside places) to `f` for rewriting.
fn m_idx(p: &mut Place, f: &mut dyn FnMut(&mut Ex)) {
    if let Some(i) = &mut p.idx {
        m_ex(i, f);
    }
    if let Some(i) = &mut p.dbit {
        m_ex(i, f);
    }
}

fn m_src(s: &mut StrSrc, f: &mut dyn FnMut(&mut Ex)) {
    match s {
        StrSrc::Ram(p) => m_idx(p, f),
        StrSrc::Lit(_) => {}
        StrSrc::Char(e) => m_ex(e, f),
    }
}

fn m_ex(e: &mut Ex, f: &mut dyn FnMut(&mut Ex)) {
    match &mut e.k {
        ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => {}
        ExK::Load(p) | ExK::Addr(p) => m_idx(p, f),
        ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) => m_ex(x, f),
        ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => {
            m_ex(a, f);
            m_ex(b, f);
        }
        ExK::Call(_, args) => {
            for (p, a) in args {
                m_idx(p, f);
                m_ex(a, f);
            }
        }
        ExK::StrEq(a, b) => {
            m_src(a, f);
            m_src(b, f);
        }
    }
    f(e);
}

fn m_block(b: &mut [S], f: &mut dyn FnMut(&mut Ex)) {
    for s in b {
        m_stmt(s, f);
    }
}

fn m_stmt(s: &mut S, f: &mut dyn FnMut(&mut Ex)) {
    match &mut s.st {
        St::Assign(p, e) => {
            m_idx(p, f);
            m_ex(e, f);
        }
        St::Add(p, _) | St::SetBit(p, _) | St::ToggleBit(p) | St::Clear(p) | St::ClearMem(p, _) | St::Direction { place: p, .. } => m_idx(p, f),
        St::Copy { dst, src, .. } => {
            m_idx(dst, f);
            m_idx(src, f);
        }
        St::StrSet { dst, parts, .. } => {
            m_idx(dst, f);
            for p in parts {
                m_src(p, f);
            }
        }
        St::Call(_, args) => {
            for (p, a) in args {
                m_idx(p, f);
                m_ex(a, f);
            }
        }
        St::If(arms, other) => {
            for (c, b) in arms {
                m_ex(c, f);
                m_block(b, f);
            }
            m_block(other, f);
        }
        St::While(c, b) | St::Repeat(b, c) => {
            m_ex(c, f);
            m_block(b, f);
        }
        St::For { var, from, limit, body, .. } => {
            m_idx(var, f);
            m_ex(from, f);
            m_ex(limit, f);
            m_block(body, f);
        }
        St::Count { counter, body, step, .. } => {
            m_idx(counter, f);
            if let Some((p, _)) = step {
                m_idx(p, f);
            }
            m_block(body, f);
        }
        St::Save { body, .. } => m_block(body, f),
        St::DelayUs(e) | St::DelayMs(e) => m_ex(e, f),
        St::Break | St::Continue | St::Return | St::Goto(_) | St::Label(_) | St::Asm(_) | St::Halt | St::Int { .. } => {}
        St::FlashSeek(_, _, e) => {
            if let Some(e) = e {
                m_ex(e, f);
            }
        }
    }
}

/// Removes every statement `keep` rejects, at any depth.
fn retain_stmts(b: &mut Vec<S>, keep: &mut dyn FnMut(&mut S) -> bool) {
    b.retain_mut(|s| keep(s));
    for s in b.iter_mut() {
        match &mut s.st {
            St::If(arms, other) => {
                for (_, blk) in arms {
                    retain_stmts(blk, keep);
                }
                retain_stmts(other, keep);
            }
            St::While(_, blk) | St::Repeat(blk, _) | St::For { body: blk, .. } | St::Count { body: blk, .. } | St::Save { body: blk, .. } => retain_stmts(blk, keep),
            _ => {}
        }
    }
}

// ---- constant folding -------------------------------------------------------------------------

fn as_i64(v: u32, w: u8, signed: bool) -> i64 {
    if signed && w < 32 && v & (1 << (w - 1)) != 0 { (v | !mask(w)) as i32 as i64 } else if signed && w == 32 { v as i32 as i64 } else { v as i64 }
}

/// Folds one node whose operands are already folded.
fn fold(e: &mut Ex) {
    let (w, signed) = (e.w, e.signed);
    let new = match &e.k {
        ExK::Conv(x) => x.as_const().map(|v| as_i64(v, x.w, x.signed) as u32),
        ExK::Neg(x) if x.w == w => x.as_const().map(|v| 0u32.wrapping_sub(v)),
        ExK::Com(x) if x.w == w => x.as_const().map(|v| !v),
        ExK::NotB(x) => x.as_const().map(|v| (v == 0) as u32),
        ExK::Cmp(k, a, b) if a.w == b.w => match (a.as_const(), b.as_const()) {
            (Some(x), Some(y)) => {
                let s = a.signed || b.signed;
                let (x, y) = (as_i64(x, a.w, s), as_i64(y, b.w, s));
                Some(match k {
                    CmpKind::Eq => x == y,
                    CmpKind::Ne => x != y,
                    CmpKind::Lt => x < y,
                    CmpKind::Gt => x > y,
                    CmpKind::Le => x <= y,
                    CmpKind::Ge => x >= y,
                } as u32)
            }
            _ => None,
        },
        ExK::Bin(BinKind::Add, a, b) if a.w == w && b.w == w && (a.as_const() == Some(0) || b.as_const() == Some(0)) && !(a.as_const().is_some() && b.as_const().is_some()) => {
            let keep = if a.as_const() == Some(0) { (**b).clone() } else { (**a).clone() };
            *e = keep;
            return;
        }
        ExK::Bin(k, a, b) => match (a.as_const(), b.as_const()) {
            (Some(x), Some(y)) if a.w == w => {
                let shift = matches!(k, BinKind::Shl | BinKind::Shr);
                if !shift && b.w != w {
                    None
                } else {
                    let (x, y) = (x & mask(w), y & mask(b.w));
                    match k {
                        BinKind::Add => Some(x.wrapping_add(y)),
                        BinKind::Sub => Some(x.wrapping_sub(y)),
                        BinKind::Mul => Some(x.wrapping_mul(y)),
                        BinKind::And => Some(x & y),
                        BinKind::Or => Some(x | y),
                        BinKind::Xor => Some(x ^ y),
                        BinKind::Div if !signed && y != 0 => Some(x / y),
                        BinKind::Mod if !signed && y != 0 => Some(x % y),
                        BinKind::Shl if y < w as u32 => Some(x << y),
                        BinKind::Shr if !signed && y < w as u32 => Some(x >> y),
                        _ => None,
                    }
                }
            }
            _ => None,
        },
        // Short-circuit logic with a known left side.
        ExK::AndAlso(a, b) => match a.as_const() {
            Some(0) => Some(0),
            Some(_) => {
                let b = (**b).clone();
                *e = b;
                return;
            }
            None => None,
        },
        ExK::OrElse(a, b) => match a.as_const() {
            Some(0) => {
                let b = (**b).clone();
                *e = b;
                return;
            }
            Some(_) => Some(1),
            None => None,
        },
        _ => None,
    };
    if let Some(v) = new {
        *e = Ex::konst(v, w, signed);
    }
}

// ---- facts about the whole program ------------------------------------------------------------

#[derive(Default)]
struct Facts {
    read: HashSet<VarId>,
    written: HashSet<VarId>,
    addr: HashSet<VarId>,
    faddr: HashSet<FuncId>,
    sites: HashMap<FuncId, Vec<Vec<(Place, Ex)>>>,
    asm: bool,
    save_func: bool,
    /// Pointer parameters stored through at statement level (or read there).
    ptr_stmt: HashSet<VarId>,
    ptr_written: HashSet<VarId>,
    /// Variables named as a plain `Base::Var` place (a pointer parameter's own value).
    raw: HashSet<VarId>,
}

fn base_var(p: &Place) -> Option<VarId> {
    match p.base {
        Base::Var(v) | Base::Ptr(v) => Some(v),
        _ => None,
    }
}

impl Visit for Facts {
    fn ex(&mut self, e: &Ex) {
        match &e.k {
            ExK::Load(p) => {
                if let Some(v) = base_var(p) {
                    self.read.insert(v);
                    if matches!(p.base, Base::Var(_)) {
                        self.raw.insert(v);
                    }
                }
            }
            ExK::Addr(p) => {
                if let Some(v) = base_var(p) {
                    self.read.insert(v);
                    self.addr.insert(v);
                }
            }
            ExK::FuncAddr(f) => {
                self.faddr.insert(*f);
            }
            _ => {}
        }
    }
    fn place(&mut self, p: &Place, a: Acc) {
        if let Some(v) = base_var(p) {
            match p.base {
                Base::Ptr(_) => {
                    self.ptr_stmt.insert(v);
                    if a != Acc::Read {
                        self.ptr_written.insert(v);
                    }
                }
                _ => {
                    self.raw.insert(v);
                }
            }
            if a != Acc::Write || matches!(p.base, Base::Ptr(_)) {
                self.read.insert(v);
            }
            if a != Acc::Read {
                self.written.insert(v);
            }
        }
    }
    fn call(&mut self, f: FuncId, args: &[(Place, Ex)]) {
        self.sites.entry(f).or_default().push(args.to_vec());
    }
    fn stmt(&mut self, s: &S) {
        match &s.st {
            St::Asm(_) => self.asm = true,
            St::Save { items, .. } => {
                for i in items {
                    match i {
                        SaveIt::Var(v) => {
                            self.read.insert(*v);
                            self.written.insert(*v);
                        }
                        SaveIt::Func(_) => self.save_func = true,
                        SaveIt::Regs => {}
                    }
                }
            }
            _ => {}
        }
    }
}

fn scan(b: &[S]) -> Facts {
    let mut f = Facts::default();
    w_block(&mut f, b);
    f
}

fn whole_var(p: &Place, vars: &[Var]) -> Option<VarId> {
    match p.base {
        Base::Var(v) if p.off == 0 && p.bit.is_none() && p.idx.is_none() && p.dbit.is_none() && p.bytes() == vars[v].bytes && !vars[v].by_ref => Some(v),
        _ => None,
    }
}

fn all_bodies(p: &mut Program) -> impl Iterator<Item = (Option<FuncId>, &mut Vec<S>)> {
    p.funcs.iter_mut().enumerate().map(|(i, f)| (Some(i), &mut f.body)).chain(std::iter::once((None, &mut p.main.body)))
}

// ---- passes -----------------------------------------------------------------------------------

fn fold_all(p: &mut Program) {
    for (_, body) in all_bodies(p) {
        m_block(body, &mut fold);
    }
}

/// Parameters every caller sets to one constant, and the routine only reads, become constants.
fn propagate_params(p: &mut Program) -> bool {
    let mut all = Facts::default();
    let mut per: Vec<Facts> = Vec::new();
    for f in &p.funcs {
        per.push(scan(&f.body));
    }
    for (_, body) in all_bodies(p) {
        w_block(&mut all, body);
    }
    for f in &per {
        all.addr.extend(f.addr.iter());
    }
    let isr: HashSet<FuncId> = p.isrs.iter().map(|(f, _)| *f).collect();
    let mut changed = false;
    for fi in 0..p.funcs.len() {
        if isr.contains(&fi) || all.faddr.contains(&fi) || per[fi].asm || all.save_func {
            continue;
        }
        let Some(sites) = all.sites.get(&fi) else { continue };
        for &pv in &p.funcs[fi].params.clone() {
            let var = &p.vars[pv];
            if var.kind != VarKind::Param || var.by_ref || all.addr.contains(&pv) || per[fi].written.contains(&pv) {
                continue;
            }
            let mut value: Option<Ex> = None;
            let mut ok = true;
            for site in sites {
                let arg = site.iter().find(|(pl, _)| matches!(pl.base, Base::Var(v) if v == pv) && pl.off == 0 && pl.bit.is_none() && pl.idx.is_none());
                match arg {
                    Some((_, e)) if e.as_const().is_some() && e.w as u32 == var.bytes * 8 => match &value {
                        None => value = Some(e.clone()),
                        Some(v) if v.as_const() == e.as_const() => {}
                        _ => ok = false,
                    },
                    _ => ok = false,
                }
                if !ok {
                    break;
                }
            }
            let Some(value) = value.filter(|_| ok) else { continue };
            let k = value.as_const().unwrap();
            let vars = &p.vars;
            let mut hit = false;
            m_block(&mut p.funcs[fi].body, &mut |e: &mut Ex| {
                if let ExK::Load(pl) = &e.k
                    && whole_var(pl, vars) == Some(pv)
                    && e.w == value.w
                {
                    *e = Ex::konst(k, e.w, e.signed);
                    hit = true;
                }
            });
            changed |= hit;
        }
    }
    changed
}

/// A `ByRef` string parameter that every caller sets to a string literal (and the routine only
/// reads) becomes a Word offset into one table of those literals in program memory: no RAM
/// copies, and the routine reads the text with `TBLRD`.
fn specialize_literals(p: &mut Program) -> bool {
    let mut all = Facts::default();
    let mut per: Vec<Facts> = Vec::new();
    for f in &p.funcs {
        per.push(scan(&f.body));
    }
    for (_, body) in all_bodies(p) {
        w_block(&mut all, body);
    }
    // The text of each literal is the argument of its start-up copy; one with no copy is empty.
    let mut text: HashMap<VarId, Vec<u8>> = HashMap::new();
    for s in &p.main.body {
        if let St::StrSet { dst, parts, .. } = &s.st
            && let Base::Var(v) = dst.base
            && let [StrSrc::Lit(b)] = parts.as_slice()
            && p.vars[v].name == "(string literal)"
        {
            text.insert(v, b.clone());
        }
    }
    let isr: HashSet<FuncId> = p.isrs.iter().map(|(f, _)| *f).collect();
    let mut changed = false;
    for fi in 0..p.funcs.len() {
        if isr.contains(&fi) || all.faddr.contains(&fi) || per[fi].asm || all.save_func {
            continue;
        }
        let Some(sites) = all.sites.get(&fi) else { continue };
        for &pv in &p.funcs[fi].params.clone() {
            let var = &p.vars[pv];
            if !var.by_ref || !matches!(var.ty, Ty::Str(_)) || !per[fi].read.contains(&pv) || per[fi].ptr_stmt.contains(&pv) || per[fi].raw.contains(&pv) || per[fi].addr.contains(&pv) {
                continue;
            }
            let mut lits: Vec<VarId> = Vec::new();
            let mut ok = true;
            for site in sites {
                let arg = site.iter().find(|(pl, _)| matches!(pl.base, Base::Var(v) if v == pv));
                match arg {
                    Some((_, Ex { k: ExK::Addr(a), .. })) if a.off == 0 && a.idx.is_none() => match a.base {
                        Base::Var(l) if p.vars[l].name == "(string literal)" => {
                            if !lits.contains(&l) {
                                lits.push(l);
                            }
                        }
                        _ => ok = false,
                    },
                    _ => ok = false,
                }
            }
            // The offsets must fit the Word the parameter becomes.
            let mut table: Vec<u8> = Vec::new();
            let mut offset: HashMap<VarId, u32> = HashMap::new();
            for &l in &lits {
                offset.insert(l, table.len() as u32);
                table.extend(text.get(&l).cloned().unwrap_or_default());
                table.push(0);
            }
            if !ok || lits.is_empty() || table.len() > 0xFFFF {
                continue;
            }
            let f = p.flash.len();
            p.flash.push(FlashObj { asm: format!("__SLIT{f}"), bytes: table });
            m_block(&mut p.funcs[fi].body, &mut |e: &mut Ex| {
                if let ExK::Load(pl) = &mut e.k
                    && matches!(pl.base, Base::Ptr(v) if v == pv)
                {
                    pl.base = Base::Flash(f);
                    let at = Place { base: Base::Var(pv), off: 0, bit: None, idx: None, dbit: None, ty: WORD };
                    let at = Ex::new(ExK::Load(at), 16, false);
                    let sum = match pl.idx.take() {
                        Some(i) => Ex::new(ExK::Bin(BinKind::Add, Box::new(at), Box::new(conv16(*i))), 16, false),
                        None => at,
                    };
                    pl.idx = Some(Box::new(sum));
                }
            });
            // Callers pass the literal's offset in the table.
            let vars = &p.vars;
            let _ = vars;
            for (_, body) in all_bodies(p) {
                m_block(body, &mut |e: &mut Ex| {
                    if let ExK::Call(g, args) = &mut e.k
                        && *g == fi
                    {
                        set_offsets(args, pv, &offset);
                    }
                });
                retain_stmts(body, &mut |s: &mut S| {
                    if let St::Call(g, args) = &mut s.st
                        && *g == fi
                    {
                        set_offsets(args, pv, &offset);
                    }
                    true
                });
            }
            let var = &mut p.vars[pv];
            var.by_ref = false;
            var.ty = WORD;
            var.bytes = 2;
            changed = true;
        }
    }
    changed
}

fn conv16(e: Ex) -> Ex {
    if e.w == 16 && !e.signed { e } else { Ex::new(ExK::Conv(Box::new(e)), 16, false) }
}

fn set_offsets(args: &mut [(Place, Ex)], pv: VarId, offset: &HashMap<VarId, u32>) {
    for (pl, e) in args {
        if matches!(pl.base, Base::Var(v) if v == pv)
            && let ExK::Addr(a) = &e.k
            && let Base::Var(l) = a.base
            && let Some(&o) = offset.get(&l)
        {
            pl.ty = WORD;
            *e = Ex::konst(o, 16, false);
        }
    }
}

/// Constants held in a routine's own locals flow forward through straight-line code.
fn propagate_locals(p: &mut Program) -> bool {
    let mut addr = HashSet::new();
    for (_, body) in all_bodies(p) {
        let f = scan(body);
        addr.extend(f.addr);
    }
    let mut changed = false;
    let vars = p.vars.clone();
    for (owner, body) in all_bodies(p) {
        let Some(owner) = owner else { continue };
        let tracked = |v: VarId| vars[v].kind == VarKind::Local && vars[v].owner == Some(owner) && !vars[v].by_ref && !addr.contains(&v);
        let mut known: HashMap<VarId, u32> = HashMap::new();
        for s in body.iter_mut() {
            let straight = matches!(s.st, St::Assign(..) | St::Add(..) | St::SetBit(..) | St::ToggleBit(..) | St::Clear(..) | St::ClearMem(..) | St::Copy { .. } | St::StrSet { .. } | St::Call(..) | St::DelayUs(_) | St::DelayMs(_) | St::Direction { .. });
            if !straight {
                known.clear();
                continue;
            }
            if !known.is_empty() {
                let mut hit = false;
                m_stmt(s, &mut |e: &mut Ex| {
                    if let ExK::Load(pl) = &e.k
                        && let Some(v) = whole_var(pl, &vars)
                        && let Some(&k) = known.get(&v)
                        && e.w == pl.width()
                    {
                        *e = Ex::konst(k, e.w, e.signed);
                        hit = true;
                    }
                    fold(e);
                });
                changed |= hit;
            }
            match &s.st {
                St::Assign(pl, e) => match (whole_var(pl, &vars), e.as_const()) {
                    (Some(v), Some(k)) if tracked(v) && e.w == pl.width() => {
                        known.insert(v, k);
                    }
                    _ => {
                        if let Some(v) = base_var(pl) {
                            known.remove(&v);
                        }
                    }
                },
                St::Clear(pl) => match whole_var(pl, &vars) {
                    Some(v) if tracked(v) => {
                        known.insert(v, 0);
                    }
                    _ => {
                        if let Some(v) = base_var(pl) {
                            known.remove(&v);
                        }
                    }
                },
                St::Add(pl, _) | St::SetBit(pl, _) | St::ToggleBit(pl) | St::ClearMem(pl, _) => {
                    if let Some(v) = base_var(pl) {
                        known.remove(&v);
                    }
                }
                St::Copy { dst, .. } | St::StrSet { dst, .. } => {
                    if let Some(v) = base_var(dst) {
                        known.remove(&v);
                    }
                }
                _ => {}
            }
        }
    }
    changed
}

/// An expression with no side effects whose value is not needed once its store is dropped.
fn pure(e: &Ex) -> bool {
    match &e.k {
        ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => true,
        ExK::Load(p) => matches!(p.base, Base::Var(_)) && p.idx.is_none() && p.dbit.is_none(),
        ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) => pure(x),
        ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => pure(a) && pure(b),
        ExK::Addr(p) => p.idx.is_none() && p.dbit.is_none(),
        ExK::Call(..) | ExK::StrEq(..) => false,
    }
}

/// Drops stores to locals and parameters that nothing reads, and arguments for parameters
/// nothing reads.
fn drop_dead(p: &mut Program) -> bool {
    let mut all = Facts::default();
    let mut pinned: HashSet<FuncId> = HashSet::new();
    let mut main_asm = false;
    for (owner, body) in all_bodies(p) {
        let f = scan(body);
        if f.asm {
            pinned.extend(owner);
            main_asm |= owner.is_none();
        }
        all.read.extend(f.read);
        all.save_func |= f.save_func;
    }
    if all.save_func {
        return false;
    }
    let dead = |vars: &[Var], v: VarId| {
        let var = &vars[v];
        matches!(var.kind, VarKind::Local | VarKind::Param | VarKind::Hidden) && var.owner.map_or(!main_asm, |o| !pinned.contains(&o)) && !all.read.contains(&v)
    };
    let vars = p.vars.clone();
    let mut changed = false;
    for (_, body) in all_bodies(p) {
        retain_stmts(body, &mut |s: &mut S| {
            let drop = match &mut s.st {
                St::Assign(pl, e) => matches!(pl.base, Base::Var(v) if dead(&vars, v)) && pl.idx.is_none() && pl.dbit.is_none() && pure(e),
                St::Add(pl, _) | St::SetBit(pl, _) | St::ToggleBit(pl) | St::Clear(pl) | St::ClearMem(pl, _) => matches!(pl.base, Base::Var(v) if dead(&vars, v)) && pl.idx.is_none() && pl.dbit.is_none(),
                St::StrSet { dst, parts, .. } => {
                    matches!(dst.base, Base::Var(v) if dead(&vars, v)) && dst.idx.is_none() && parts.iter().all(|p| matches!(p, StrSrc::Lit(_)))
                }
                St::Call(_, args) => {
                    let n = args.len();
                    args.retain(|(pl, e)| !(matches!(pl.base, Base::Var(v) if dead(&vars, v)) && pl.idx.is_none() && pure(e)));
                    changed |= args.len() != n;
                    false
                }
                _ => false,
            };
            changed |= drop;
            !drop
        });
        m_block(body, &mut |e: &mut Ex| {
            if let ExK::Call(_, args) = &mut e.k {
                let n = args.len();
                args.retain(|(pl, a)| !(matches!(pl.base, Base::Var(v) if dead(&vars, v)) && pl.idx.is_none() && pure(a)));
                changed |= args.len() != n;
            }
        });
    }
    changed
}

// ---- walking a constant table ------------------------------------------------------------------

/// Whether code reads or moves TBLPTR, which a table walk keeps between statements.
struct TblUse<'a> {
    users: &'a HashSet<FuncId>,
    hit: bool,
}

impl Visit for TblUse<'_> {
    fn ex(&mut self, e: &Ex) {
        match &e.k {
            ExK::Load(p) | ExK::Addr(p) if matches!(p.base, Base::Flash(_) | Base::FlashNext(_)) => self.hit = true,
            ExK::StrEq(..) => self.hit = true,
            _ => {}
        }
    }
    fn place(&mut self, p: &Place, _: Acc) {
        self.hit |= matches!(p.base, Base::Flash(_) | Base::FlashNext(_));
    }
    fn call(&mut self, f: FuncId, _: &[(Place, Ex)]) {
        self.hit |= self.users.contains(&f);
    }
    fn stmt(&mut self, s: &S) {
        self.hit |= matches!(s.st, St::StrSet { .. } | St::Copy { .. } | St::Asm(_) | St::FlashSeek(..));
    }
}

/// Routines whose code, or whose callees' code, may change TBLPTR.
fn tbl_users(p: &Program) -> HashSet<FuncId> {
    let mut users: HashSet<FuncId> = HashSet::new();
    loop {
        let mut grew = false;
        for (i, f) in p.funcs.iter().enumerate() {
            if users.contains(&i) {
                continue;
            }
            let mut v = TblUse { users: &users, hit: false };
            w_block(&mut v, &f.body);
            if v.hit {
                users.insert(i);
                grew = true;
            }
        }
        if !grew {
            return users;
        }
    }
}

/// `e` is `i + k` (plus, optionally, one unsigned Word parameter `x`) for the variable `i`:
/// returns `k` and `x`.
fn index_plus(e: &Ex, i: VarId, vars: &[Var], owner: FuncId) -> Option<(u32, Option<Ex>)> {
    fn go(e: &Ex, i: VarId, vars: &[Var], owner: FuncId, seen_i: &mut u32) -> Option<(u32, Option<Ex>)> {
        match &e.k {
            ExK::Const(c) => Some((*c, None)),
            ExK::Load(p) if matches!(p.base, Base::Var(v) if v == i) && p.off == 0 && p.bit.is_none() && p.idx.is_none() && p.dbit.is_none() && !e.signed => {
                *seen_i += 1;
                Some((0, None))
            }
            ExK::Load(p) => match p.base {
                Base::Var(v) if v != i && vars[v].kind == VarKind::Param && vars[v].owner == Some(owner) && !vars[v].by_ref && p.off == 0 && p.bit.is_none() && p.idx.is_none() && p.dbit.is_none() && e.w == 16 && !e.signed && p.width() == 16 && !p.signed() => Some((0, Some(e.clone()))),
                _ => None,
            },
            ExK::Conv(x) if !x.signed => go(x, i, vars, owner, seen_i),
            ExK::Bin(BinKind::Add, a, b) => {
                let (ka, xa) = go(a, i, vars, owner, seen_i)?;
                let (kb, xb) = go(b, i, vars, owner, seen_i)?;
                let x = match (xa, xb) {
                    (Some(_), Some(_)) => return None,
                    (x, None) | (None, x) => x,
                };
                Some((ka.wrapping_add(kb), x))
            }
            _ => None,
        }
    }
    let mut seen = 0;
    let (k, x) = go(e, i, vars, owner, &mut seen)?;
    (seen == 1).then_some((k, x))
}

fn blocks_mut(st: &mut St) -> Vec<&mut Vec<S>> {
    match st {
        St::If(arms, other) => arms.iter_mut().map(|(_, b)| b).chain(std::iter::once(other)).collect(),
        St::While(_, b) | St::Repeat(b, _) | St::For { body: b, .. } | St::Count { body: b, .. } | St::Save { body: b, .. } => vec![b],
        _ => Vec::new(),
    }
}

fn has_continue(s: &S) -> bool {
    matches!(s.st, St::Continue) || sub_blocks_of(&s.st).into_iter().any(|b| b.iter().any(has_continue))
}

fn sub_blocks_of(st: &St) -> Vec<&[S]> {
    match st {
        St::If(arms, other) => arms.iter().map(|(_, b)| b.as_slice()).chain(std::iter::once(other.as_slice())).collect(),
        St::While(_, b) | St::Repeat(b, _) | St::For { body: b, .. } | St::Count { body: b, .. } | St::Save { body: b, .. } => vec![b.as_slice()],
        _ => Vec::new(),
    }
}

/// Rewrites, in `blk` and the blocks inside it, loops of the form
///
/// ```text
/// i = k
/// While True            ' or any constant-true loop
///     c = table(i)      ' the only mention of i besides the step
///     ...
///     Inc(i)
/// Wend
/// ```
///
/// to read the table through TBLPTR, which `TBLRD*+` advances: the pointer is set once before the
/// loop and the index disappears. Returns the index variables that were replaced. (The index of a
/// Byte would wrap after 256 characters; a table walk does not, which only differs for a loop that
/// never meets the table's end.)
fn walk_tables(blk: &mut Vec<S>, vars: &[Var], users: &HashSet<FuncId>, owner: FuncId, facts: &Facts, done: &mut Vec<VarId>) {
    for s in blk.iter_mut() {
        for b in blocks_mut(&mut s.st) {
            walk_tables(b, vars, users, owner, facts, done);
        }
    }
    for k in 1..blk.len() {
        let St::While(cond, body) = &blk[k].st else { continue };
        if !cond.as_const().is_some_and(|v| v != 0) || has_jump_target(body) || body.iter().any(has_continue) {
            continue;
        }
        // The last statement steps a variable by one: the index.
        let i = match body.last() {
            Some(S { st: St::Add(p, 1), .. }) if p.off == 0 && p.bit.is_none() && p.idx.is_none() && p.dbit.is_none() => match p.base {
                Base::Var(i) => i,
                _ => continue,
            },
            _ => continue,
        };
        let var = &vars[i];
        if !matches!(var.kind, VarKind::Local | VarKind::Hidden) || var.owner != Some(owner) || var.by_ref || !matches!(var.ty, Ty::Int(_, false)) || body.len() < 2 {
            continue;
        }
        // It starts at a constant: the last statement before the loop that mentions it.
        let Some(j) = (0..k).rev().find(|&j| mentions(std::slice::from_ref(&blk[j]), i)) else { continue };
        let start = match &blk[j].st {
            St::Assign(p, e) if matches!(p.base, Base::Var(v) if v == i) && p.off == 0 && p.bit.is_none() && p.idx.is_none() && p.dbit.is_none() => match e.as_const() {
                Some(c) => c,
                None => continue,
            },
            St::Clear(p) if matches!(p.base, Base::Var(v) if v == i) && p.off == 0 && p.bit.is_none() && p.idx.is_none() && p.dbit.is_none() => 0,
            _ => continue,
        };
        // Statements in between run after the pointer is set only if they are moved; the pointer
        // is set right before the loop instead, so only jumps into that stretch matter.
        if blk[j + 1..k].iter().any(|s| has_jump_target(std::slice::from_ref(s))) {
            continue;
        }
        // One statement reads the table at `i + k`.
        let n = body.len() - 1;
        let Some((t, f, at, x)) = body[..n].iter().enumerate().find_map(|(t, s)| match &s.st {
            St::Assign(dst, Ex { k: ExK::Load(src), w: 8, .. }) if dst.idx.is_none() && dst.dbit.is_none() && !matches!(dst.base, Base::Flash(_)) => match (&src.base, &src.idx) {
                (Base::Flash(f), Some(ix)) if src.bit.is_none() && src.dbit.is_none() => index_plus(ix, i, vars, owner).map(|(o, x)| (t, *f, src.off.wrapping_add(o), x)),
                _ => None,
            },
            _ => None,
        }) else {
            continue;
        };
        // A run-time start offset must not change while the loop runs.
        if let Some(Ex { k: ExK::Load(Place { base: Base::Var(xv), .. }), .. }) = &x
            && (facts.written.contains(xv) || facts.addr.contains(xv))
        {
            continue;
        }
        // Nothing else in the loop mentions the index or touches TBLPTR.
        let rest: Vec<S> = body[..n].iter().enumerate().filter(|(j, _)| *j != t).map(|(_, s)| s.clone()).collect();
        let mut v = TblUse { users, hit: false };
        w_block(&mut v, &rest);
        if v.hit || mentions(&rest, i) {
            continue;
        }
        let St::While(_, body) = &mut blk[k].st else { continue };
        body.pop();
        if let St::Assign(_, Ex { k: ExK::Load(src), .. }) = &mut body[t].st {
            src.base = Base::FlashNext(f);
            src.off = 0;
            src.idx = None;
        }
        let span = blk[j].span;
        blk.remove(j);
        blk.insert(k - 1, S { st: St::FlashSeek(f, at.wrapping_add(start), x), span });
        done.push(i);
    }
}

/// Applies [`walk_tables`] to every routine, keeping a change only when the index variable has no
/// other use left in the routine.
fn flash_walk(p: &mut Program) -> bool {
    let users = tbl_users(p);
    let vars = p.vars.clone();
    let mut changed = false;
    for (fi, f) in p.funcs.iter_mut().enumerate() {
        let before = f.body.clone();
        let mut done = Vec::new();
        let facts = scan(&f.body);
        walk_tables(&mut f.body, &vars, &users, fi, &facts, &mut done);
        if done.is_empty() {
            continue;
        }
        // The index may still be cleared on entry; that store dies with it.
        let mut probe = f.body.clone();
        probe.retain(|s| !matches!(&s.st, St::Clear(pl) if matches!(pl.base, Base::Var(v) if done.contains(&v))));
        if done.iter().any(|&i| mentions(&probe, i)) {
            f.body = before;
        } else {
            f.body = probe;
            changed = true;
        }
    }
    changed
}

/// Routines something other than a plain call can reach: their address is taken, or an `Asm`
/// block names them. They keep the standard argument passing.
pub fn reachable_otherwise(p: &Program) -> HashSet<FuncId> {
    let mut out: HashSet<FuncId> = HashSet::new();
    let mut all = Facts::default();
    let mut lines: Vec<&String> = Vec::new();
    for f in p.funcs.iter().map(|f| &f.body).chain(std::iter::once(&p.main.body)) {
        w_block(&mut all, f);
        collect_asm(f, &mut lines);
    }
    out.extend(all.faddr.iter().copied());
    for (i, f) in p.funcs.iter().enumerate() {
        if lines.iter().any(|l| l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).any(|t| t == f.asm)) {
            out.insert(i);
        }
    }
    out
}

fn collect_asm<'a>(b: &'a [S], out: &mut Vec<&'a String>) {
    for s in b {
        if let St::Asm(ls) = &s.st {
            out.extend(ls.iter());
        }
        for sub in sub_blocks_of(&s.st) {
            collect_asm(sub, out);
        }
    }
}

pub fn optimize(p: &mut Program) {
    for _ in 0..8 {
        fold_all(p);
        let mut changed = propagate_params(p);
        changed |= specialize_literals(p);
        fold_all(p);
        changed |= propagate_locals(p);
        changed |= drop_dead(p);
        if !changed {
            break;
        }
    }
    // Last: later passes would not know about a table walk.
    if flash_walk(p) {
        drop_dead(p);
    }
}
