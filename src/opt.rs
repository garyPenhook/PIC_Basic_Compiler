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
        StrSrc::Cat { tmp, parts } => {
            w_place(v, tmp, Acc::Write);
            for p in parts {
                w_src(v, p);
            }
            w_place(v, tmp, Acc::Read);
        }
    }
}

fn w_ex<V: Visit>(v: &mut V, e: &Ex) {
    v.ex(e);
    match &e.k {
        ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => {}
        ExK::Load(p) | ExK::Addr(p) => w_idx(v, p),
        ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => w_ex(v, x),
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
            St::Break | St::Continue | St::Return | St::Goto(_) | St::GoSub(_) | St::SubRet | St::Label(_) | St::Asm(_) | St::Halt | St::Int { .. } => {}
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
        StrSrc::Cat { tmp, parts } => {
            m_idx(tmp, f);
            for p in parts {
                m_src(p, f);
            }
        }
    }
}

fn m_ex(e: &mut Ex, f: &mut dyn FnMut(&mut Ex)) {
    match &mut e.k {
        ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => {}
        ExK::Load(p) | ExK::Addr(p) => m_idx(p, f),
        ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => m_ex(x, f),
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
        St::Break | St::Continue | St::Return | St::Goto(_) | St::GoSub(_) | St::SubRet | St::Label(_) | St::Asm(_) | St::Halt | St::Int { .. } => {}
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
        ExK::Abs(x) if x.w == w => x.as_const().map(|v| (as_i64(v, x.w, true).unsigned_abs() as u32) & mask(w)),
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
                        BinKind::Min | BinKind::Max if signed => {
                            let (sx, sy) = (as_i64(x, w, true), as_i64(y, w, true));
                            Some((if *k == BinKind::Min { sx.min(sy) } else { sx.max(sy) }) as u32 & mask(w))
                        }
                        BinKind::Min => Some(x.min(y)),
                        BinKind::Max => Some(x.max(y)),
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

/// One byte of a multi-byte variable (`Byte(w >> 8)` reads byte 1 of `w` in place): the variable and the bit
/// position of the byte, so a known value of the whole variable gives the byte's value.
fn byte_part(p: &Place, vars: &[Var]) -> Option<(VarId, u32)> {
    match p.base {
        Base::Var(v) if p.bit.is_none() && p.idx.is_none() && p.dbit.is_none() && !vars[v].by_ref && p.width() == 8 && p.bytes() == 1 && p.off < vars[v].bytes && vars[v].bytes > 1 => Some((v, p.off * 8)),
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
    // Entered from outside the call graph the pass sees: handlers, and routines C calls.
    let isr: HashSet<FuncId> = p.isrs.iter().map(|(f, _)| *f).chain(p.exports.iter().map(|e| e.func)).collect();
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
                } else if let ExK::Load(pl) = &e.k
                    && let Some((v, sh)) = byte_part(pl, vars)
                    && v == pv
                    && e.w == 8
                {
                    *e = Ex::konst((k >> sh) & 0xFF, 8, e.signed);
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
    // Entered from outside the call graph the pass sees: handlers, and routines C calls.
    let isr: HashSet<FuncId> = p.isrs.iter().map(|(f, _)| *f).chain(p.exports.iter().map(|e| e.func)).collect();
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

// ---- range checks --------------------------------------------------------------------------------

/// Whether evaluating `e` twice gives the same value and has no effect: loads of ordinary variables
/// (also with an index), no call, no device register, nothing `Volatile`.
fn repeatable(e: &Ex, vars: &[Var]) -> bool {
    match &e.k {
        ExK::Const(_) => true,
        ExK::Load(p) => {
            let base_ok = match p.base {
                Base::Var(v) | Base::Ptr(v) => !vars[v].volatile,
                Base::Flash(_) => true,
                Base::Abs { .. } | Base::FlashNext(_) => false,
            };
            base_ok && p.dbit.is_none() && p.idx.as_ref().is_none_or(|i| repeatable(i, vars))
        }
        ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) => repeatable(x, vars),
        ExK::Bin(_, a, b) => repeatable(a, vars) && repeatable(b, vars),
        _ => false,
    }
}

/// `x <relation> constant` as (x, relation with x on the left, constant as a number, signed, width).
fn cmp_const(e: &Ex) -> Option<(&Ex, CmpKind, i64, bool, u8)> {
    let ExK::Cmp(k, a, b) = &e.k else { return None };
    if a.w != b.w {
        return None;
    }
    if a.signed != b.signed {
        return None;
    }
    let s = a.signed;
    match (a.as_const(), b.as_const()) {
        (None, Some(c)) => Some((a, *k, as_i64(c, b.w, s), s, a.w)),
        (Some(c), None) => Some((b, k.swap(), as_i64(c, a.w, s), s, a.w)),
        _ => None,
    }
}

/// `lo <= x` and `x <= hi` from two comparisons of the same `x`, in either order, as the range (lo, hi).
fn range_of(l: &Ex, r: &Ex, vars: &[Var]) -> Option<(Ex, i64, i64, bool)> {
    let (x1, k1, c1, s1, w1) = cmp_const(l)?;
    let (x2, k2, c2, s2, w2) = cmp_const(r)?;
    if x1 != x2 || s1 != s2 || w1 != w2 || w1 > 32 || !repeatable(x1, vars) {
        return None;
    }
    let low = |k: CmpKind, c: i64| match k {
        CmpKind::Ge => Some(c),
        CmpKind::Gt => Some(c + 1),
        _ => None,
    };
    let high = |k: CmpKind, c: i64| match k {
        CmpKind::Le => Some(c),
        CmpKind::Lt => Some(c - 1),
        _ => None,
    };
    let (lo, hi) = match (low(k1, c1), high(k2, c2)) {
        (Some(lo), Some(hi)) => (lo, hi),
        _ => (low(k2, c2)?, high(k1, c1)?),
    };
    let (min, max) = if s1 { (-(1i64 << (w1 - 1)), (1i64 << (w1 - 1)) - 1) } else { (0, (1i64 << w1) - 1) };
    if lo > hi || lo < min || hi > max {
        return None;
    }
    Some((x1.clone(), lo, hi, s1))
}

/// `x >= lo And x <= hi` is `x - lo <= hi - lo` compared unsigned, and `x < lo Or x > hi` its opposite: one
/// load of `x` and one comparison instead of two of each (`cmd(i) < 48 Or cmd(i) > 57`).
fn range_check(e: &mut Ex, vars: &[Var]) -> bool {
    let (inside, l, r) = match &e.k {
        ExK::AndAlso(l, r) => (true, l, r),
        ExK::OrElse(l, r) => (false, l, r),
        _ => return false,
    };
    let (negate_l, negate_r);
    let (l2, r2);
    if inside {
        (l2, r2) = ((**l).clone(), (**r).clone());
    } else {
        // Not(Not a And Not b): turn each outside test into its opposite.
        let neg = |x: &Ex| -> Option<Ex> {
            let ExK::Cmp(k, a, b) = &x.k else { return None };
            Some(Ex::new(ExK::Cmp(k.negate(), a.clone(), b.clone()), x.w, x.signed))
        };
        negate_l = neg(l);
        negate_r = neg(r);
        let (Some(a), Some(b)) = (negate_l, negate_r) else { return false };
        (l2, r2) = (a, b);
    }
    let Some((x, lo, hi, s)) = range_of(&l2, &r2, vars) else { return false };
    let w = x.w;
    let rel = |k: CmpKind, a: Ex, b: Ex| Ex::boolean(ExK::Cmp(k, Box::new(a), Box::new(b)));
    *e = if lo == hi {
        rel(if inside { CmpKind::Eq } else { CmpKind::Ne }, x, Ex::konst(lo as u32, w, s))
    } else {
        let shifted = if lo == 0 && !s { x } else { Ex::new(ExK::Bin(BinKind::Sub, Box::new(x), Box::new(Ex::konst(lo as u32, w, false))), w, false) };
        rel(if inside { CmpKind::Le } else { CmpKind::Gt }, shifted, Ex::konst((hi - lo) as u32, w, false))
    };
    true
}

fn range_checks(p: &mut Program) -> bool {
    let vars = p.vars.clone();
    let mut changed = false;
    for (_, body) in all_bodies(p) {
        m_block(body, &mut |e: &mut Ex| changed |= range_check(e, &vars));
    }
    changed
}

/// Replaces the loads of the variables in `env` by their values and folds.
fn subst_known(e: &mut Ex, env: &HashMap<VarId, u32>, vars: &[Var]) -> bool {
    let mut hit = false;
    m_ex(e, &mut |x: &mut Ex| {
        if let ExK::Load(pl) = &x.k
            && let Some(v) = whole_var(pl, vars)
            && let Some(&k) = env.get(&v)
            && x.w == pl.width()
        {
            *x = Ex::konst(k, x.w, x.signed);
            hit = true;
        } else if let ExK::Load(pl) = &x.k
            && let Some((v, sh)) = byte_part(pl, vars)
            && let Some(&k) = env.get(&v)
            && x.w == 8
        {
            *x = Ex::konst((k >> sh) & 0xFF, 8, x.signed);
            hit = true;
        }
        fold(x);
    });
    hit
}

/// The value of `e` when every variable it loads is in `env`.
fn eval_known(e: &Ex, env: &HashMap<VarId, u32>, vars: &[Var]) -> Option<u32> {
    if e.has_call() {
        return None;
    }
    let mut c = e.clone();
    subst_known(&mut c, env, vars);
    c.as_const()
}

/// How a statement list ended when run at compile time.
#[derive(PartialEq)]
enum Flow {
    Next,
    Break,
    Continue,
}

/// Compile-time run of a statement list over constant locals (see [`fold_loop`]).
struct Sim<'a> {
    env: HashMap<VarId, u32>,
    written: Vec<VarId>,
    vars: &'a [Var],
    tracked: &'a dyn Fn(VarId) -> bool,
    fuel: u32,
}

impl Sim<'_> {
    fn set(&mut self, pl: &Place, val: u32) -> Option<()> {
        let v = whole_var(pl, self.vars)?;
        if !(self.tracked)(v) {
            return None;
        }
        self.env.insert(v, val & mask(pl.width()));
        if !self.written.contains(&v) {
            self.written.push(v);
        }
        Some(())
    }

    fn block(&mut self, b: &[S]) -> Option<Flow> {
        for s in b {
            self.fuel = self.fuel.checked_sub(1)?;
            match &s.st {
                St::Assign(pl, e) if e.w == pl.width() => {
                    let k = eval_known(e, &self.env, self.vars)?;
                    self.set(pl, k)?;
                }
                St::Add(pl, k) => {
                    let v = whole_var(pl, self.vars)?;
                    let old = *self.env.get(&v)?;
                    self.set(pl, old.wrapping_add(*k))?;
                }
                St::Clear(pl) => self.set(pl, 0)?,
                St::If(arms, other) => {
                    let mut chosen: &[S] = other;
                    for (c, blk) in arms {
                        if eval_known(c, &self.env, self.vars)? != 0 {
                            chosen = blk;
                            break;
                        }
                    }
                    let f = self.block(chosen)?;
                    if f != Flow::Next {
                        return Some(f);
                    }
                }
                St::While(c, body) => self.looping(c, body)?,
                St::Break => return Some(Flow::Break),
                St::Continue => return Some(Flow::Continue),
                _ => return None,
            }
        }
        Some(Flow::Next)
    }

    fn looping(&mut self, c: &Ex, body: &[S]) -> Option<()> {
        loop {
            self.fuel = self.fuel.checked_sub(1)?;
            if eval_known(c, &self.env, self.vars)? == 0 {
                return Some(());
            }
            if self.block(body)? == Flow::Break {
                return Some(());
            }
        }
    }
}

/// A `While` whose condition and body only read and write constant locals is run by the compiler: it
/// becomes an assignment of the final value of every variable it wrote (and nothing at all when it
/// runs no pass), so `I2cInit` finds its baud divider at compile time instead of adding in a loop.
/// Gives up (None) for anything it cannot follow, or for a loop that needs more than a few thousand steps.
fn fold_loop(c: &Ex, body: &[S], known: &HashMap<VarId, u32>, vars: &[Var], tracked: &dyn Fn(VarId) -> bool, span: crate::diag::Span) -> Option<Vec<S>> {
    let mut sim = Sim { env: known.clone(), written: Vec::new(), vars, tracked, fuel: 20_000 };
    sim.looping(c, body)?;
    let out = sim
        .written
        .iter()
        .map(|&v| {
            let pl = Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: vars[v].ty.clone() };
            let e = Ex::konst(sim.env[&v], pl.width(), pl.signed());
            S { st: St::Assign(pl, e), span }
        })
        .collect();
    Some(out)
}

/// Constants held in a routine's own locals flow forward through the routine's top-level statements:
/// into the straight-line ones, into the conditions of an `If` (one whose condition is known is
/// replaced by the arm it takes) and through a loop run at compile time. Any other compound statement
/// only forgets the variables it mentions.
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
        // Hidden variables too: a loop limit that is a constant by now (`For i = 0 To n - 1` with `n` known).
        let tracked = |v: VarId| matches!(vars[v].kind, VarKind::Local | VarKind::Hidden) && vars[v].owner == Some(owner) && !vars[v].by_ref && !vars[v].volatile && !addr.contains(&v);
        let mut known: HashMap<VarId, u32> = HashMap::new();
        let mut todo: std::collections::VecDeque<S> = std::mem::take(body).into();
        let mut out: Vec<S> = Vec::with_capacity(todo.len());
        while let Some(mut s) = todo.pop_front() {
            let straight = matches!(s.st, St::Assign(..) | St::Add(..) | St::SetBit(..) | St::ToggleBit(..) | St::Clear(..) | St::ClearMem(..) | St::Copy { .. } | St::StrSet { .. } | St::Call(..) | St::DelayUs(_) | St::DelayMs(_) | St::Direction { .. });
            // A `For` works out its start and limit once, before the loop: what is known then applies to them.
            if let St::For { from, limit, .. } = &mut s.st
                && !known.is_empty()
            {
                changed |= subst_known(from, &known, &vars);
                changed |= subst_known(limit, &known, &vars);
            }
            if !straight {
                let compound = matches!(s.st, St::If(..) | St::While(..)) && !known.is_empty() && !has_jump_target(std::slice::from_ref(&s));
                if !compound {
                    known.clear();
                    out.push(s);
                    continue;
                }
                match &mut s.st {
                    St::If(arms, other) => {
                        for (c, _) in arms.iter_mut() {
                            changed |= subst_known(c, &known, &vars);
                        }
                        // Arms whose condition is false go; the first one that is true ends the chain.
                        let before = arms.len();
                        let mut taken = None;
                        let mut kept = Vec::new();
                        for (c, blk) in std::mem::take(arms) {
                            match c.as_const() {
                                Some(0) => {}
                                Some(_) if kept.is_empty() => {
                                    taken = Some(blk);
                                    break;
                                }
                                Some(_) => {
                                    // Always true after earlier arms that may be: it is the `Else`.
                                    *other = blk;
                                    break;
                                }
                                None => kept.push((c, blk)),
                            }
                        }
                        *arms = kept;
                        if let Some(blk) = taken {
                            changed = true;
                            for st in blk.into_iter().rev() {
                                todo.push_front(st);
                            }
                            continue;
                        }
                        if arms.is_empty() {
                            changed = true;
                            for st in std::mem::take(other).into_iter().rev() {
                                todo.push_front(st);
                            }
                            continue;
                        }
                        changed |= arms.len() != before;
                    }
                    St::While(c, body) => {
                        if let Some(rep) = fold_loop(c, body, &known, &vars, &tracked, s.span) {
                            changed = true;
                            for st in rep.into_iter().rev() {
                                todo.push_front(st);
                            }
                            continue;
                        }
                    }
                    _ => {}
                }
                let one = std::slice::from_ref(&s);
                known.retain(|&v, _| !mentions(one, v));
                out.push(s);
                continue;
            }
            if !known.is_empty() {
                let mut hit = false;
                m_stmt(&mut s, &mut |e: &mut Ex| {
                    if let ExK::Load(pl) = &e.k
                        && let Some(v) = whole_var(pl, &vars)
                        && let Some(&k) = known.get(&v)
                        && e.w == pl.width()
                    {
                        *e = Ex::konst(k, e.w, e.signed);
                        hit = true;
                    } else if let ExK::Load(pl) = &e.k
                        && let Some((v, sh)) = byte_part(pl, &vars)
                        && let Some(&k) = known.get(&v)
                        && e.w == 8
                    {
                        *e = Ex::konst((k >> sh) & 0xFF, 8, e.signed);
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
                St::Add(pl, k) => match whole_var(pl, &vars).and_then(|v| known.get(&v).map(|&old| (v, old))) {
                    Some((v, old)) => {
                        known.insert(v, old.wrapping_add(*k) & mask(pl.width()));
                    }
                    None => {
                        if let Some(v) = base_var(pl) {
                            known.remove(&v);
                        }
                    }
                },
                St::SetBit(pl, _) | St::ToggleBit(pl) | St::ClearMem(pl, _) => {
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
            out.push(s);
        }
        *body = out;
    }
    changed
}

/// An expression with no side effects whose value is not needed once its store is dropped.
fn pure(e: &Ex) -> bool {
    match &e.k {
        ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => true,
        ExK::Load(p) => matches!(p.base, Base::Var(_)) && p.idx.is_none() && p.dbit.is_none(),
        ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => pure(x),
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
        !var.volatile && matches!(var.kind, VarKind::Local | VarKind::Param | VarKind::Hidden) && var.owner.map_or(!main_asm, |o| !pinned.contains(&o)) && !all.read.contains(&v)
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
        if !matches!(var.kind, VarKind::Local | VarKind::Hidden) || var.owner != Some(owner) || var.by_ref || var.volatile || !matches!(var.ty, Ty::Int(_, false)) || body.len() < 2 {
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

/// The variables an interrupt handler, a routine C calls, or anything they call reads or writes: another flow of control
/// can see these between two instructions of the main program, so a pass must not park a half-computed value in one.
/// `None` when that is unknown for any of them (raw assembly, access through a pointer or `ByRef`, C or register-call
/// routines, see `ir::routine_effects`): then every variable counts.
pub fn interrupt_vars(p: &Program) -> Option<HashSet<VarId>> {
    let fx = crate::ir::routine_effects(p);
    let mut vars = HashSet::new();
    for f in p.isrs.iter().map(|(f, _)| *f).chain(p.exports.iter().map(|e| e.func)) {
        let e = fx.get(f)?.as_ref()?;
        vars.extend(e.writes.iter().chain(e.reads.iter()).copied());
    }
    Some(vars)
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
    out.extend(p.exports.iter().map(|e| e.func));
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

/// A copy of `p` without the stores to the globals in `names` (assembly symbols), for globals nothing in the
/// program reads, takes the address of or names in an `Asm` block. `None` when no store could be removed.
pub fn without_write_only(p: &Program, names: &HashSet<String>) -> Option<Program> {
    let mut q = p.clone();
    let mut all = Facts::default();
    let mut in_asm: HashSet<String> = HashSet::new();
    for (_, body) in all_bodies(&mut q) {
        let f = scan(body);
        all.read.extend(f.read);
        all.addr.extend(f.addr);
        all.save_func |= f.save_func;
        let mut lines: Vec<&String> = Vec::new();
        collect_asm(body, &mut lines);
        for l in lines {
            in_asm.extend(l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).map(str::to_string));
        }
    }
    if all.save_func {
        return None;
    }
    let vars = q.vars.clone();
    let dead = |v: VarId| {
        let var = &vars[v];
        var.kind == VarKind::Global && !var.volatile && !var.by_ref && names.contains(&var.asm) && !in_asm.contains(&var.asm) && !all.read.contains(&v) && !all.addr.contains(&v)
    };
    let mut changed = false;
    for (_, body) in all_bodies(&mut q) {
        retain_stmts(body, &mut |s: &mut S| {
            let drop = match &s.st {
                St::Assign(pl, e) => matches!(pl.base, Base::Var(v) if dead(v)) && pl.idx.is_none() && pl.dbit.is_none() && pure(e),
                St::Add(pl, _) | St::SetBit(pl, _) | St::ToggleBit(pl) | St::Clear(pl) | St::ClearMem(pl, _) => matches!(pl.base, Base::Var(v) if dead(v)) && pl.idx.is_none() && pl.dbit.is_none(),
                _ => false,
            };
            changed |= drop;
            !drop
        });
    }
    if !changed {
        return None;
    }
    for (i, v) in q.vars.iter_mut().enumerate() {
        if dead(i) {
            v.init = None;
        }
    }
    Some(q)
}

/// A routine whose last statement is `Result = G(..)` and that uses its `Result` nowhere else (no early `Return`, no other
/// write) needs no copy of its own: it shares `G`'s `Result` object, and its callers read that. This removes a
/// `movff` pair per byte at every such hop (`ADin` -> `AdcRead` -> `Convert`), the entry clear of the `Result`, and its RAM.
/// Skipped for byte results (they travel in W), routines in a call cycle, routines a handler can reach (an interrupt
/// calling `G` would overwrite a result its caller has not read yet), and routines reachable other than by a plain call.
fn share_results(p: &mut Program) -> bool {
    struct Calls(HashSet<FuncId>);
    impl Visit for Calls {
        fn call(&mut self, f: FuncId, _: &[(Place, Ex)]) {
            self.0.insert(f);
        }
    }
    let n = p.funcs.len();
    let calls: Vec<HashSet<FuncId>> = p
        .funcs
        .iter()
        .map(|f| {
            let mut c = Calls(HashSet::new());
            w_block(&mut c, &f.body);
            c.0
        })
        .collect();
    let reach = |from: FuncId| -> HashSet<FuncId> {
        let mut seen = HashSet::new();
        let mut todo = vec![from];
        while let Some(f) = todo.pop() {
            for &g in &calls[f] {
                if seen.insert(g) {
                    todo.push(g);
                }
            }
        }
        seen
    };
    let mut hot: HashSet<FuncId> = reachable_otherwise(p);
    for &(h, _) in &p.isrs {
        hot.insert(h);
        hot.extend(reach(h));
    }
    hot.extend(p.ext_funcs.iter().copied());
    for (f, _) in p.funcs.iter().enumerate() {
        if p.funcs[f].ext || p.funcs[f].reg {
            hot.insert(f);
        }
    }
    let mut asm_lines: Vec<String> = Vec::new();
    {
        let mut refs: Vec<&String> = Vec::new();
        for b in p.funcs.iter().map(|f| &f.body).chain(std::iter::once(&p.main.body)) {
            collect_asm(b, &mut refs);
        }
        asm_lines.extend(refs.into_iter().cloned());
    }
    let mut changed = false;
    'next: for fi in 0..n {
        let Some(rv) = p.funcs[fi].result else { continue };
        if hot.contains(&fi) {
            continue;
        }
        let var = &p.vars[rv];
        if var.kind != VarKind::Result || var.owner != Some(fi) || var.by_ref || var.volatile || !matches!(var.ty, Ty::Int(w, _) if w >= 16) {
            continue;
        }
        // The body ends with the statement, then the routine's own closing `Return`.
        let blen = p.funcs[fi].body.len();
        let k = if matches!(p.funcs[fi].body.last().map(|s| &s.st), Some(St::Return)) { blen.wrapping_sub(2) } else { continue };
        let Some(last) = p.funcs[fi].body.get(k) else { continue };
        let St::Assign(pl, ex) = &last.st else { continue };
        let ExK::Call(g, _) = &ex.k else { continue };
        let g = *g;
        if !(matches!(pl.base, Base::Var(v) if v == rv) && pl.off == 0 && pl.bit.is_none() && pl.idx.is_none() && pl.dbit.is_none() && pl.ty == var.ty) {
            continue;
        }
        let Some(gv) = p.funcs[g].result else { continue };
        let gvar = &p.vars[gv];
        if g == fi || hot.contains(&g) || gvar.kind != VarKind::Result || gvar.owner != Some(g) || gvar.by_ref || gvar.volatile || gvar.ty != var.ty {
            continue;
        }
        if reach(g).contains(&g) || reach(g).contains(&fi) {
            continue;
        }
        if asm_lines.iter().any(|l| l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).any(|t| t == var.asm)) {
            continue;
        }
        // Every other mention of `rv`: only whole-object clears at the top level of the routine's own body, and loads.
        struct Uses {
            rv: VarId,
            bad: bool,
            places: usize,
            ret: bool,
        }
        impl Visit for Uses {
            fn place(&mut self, p: &Place, _: Acc) {
                if matches!(p.base, Base::Var(v) | Base::Ptr(v) if v == self.rv) {
                    self.places += 1;
                }
            }
            fn ex(&mut self, e: &Ex) {
                if let ExK::Addr(p) = &e.k {
                    if matches!(p.base, Base::Var(v) | Base::Ptr(v) if v == self.rv) {
                        self.bad = true;
                    }
                }
            }
            fn stmt(&mut self, s: &S) {
                match &s.st {
                    St::Return | St::Goto(_) | St::GoSub(_) | St::SubRet | St::Label(_) => self.ret = true,
                    St::Save { items, .. } if items.contains(&SaveIt::Var(self.rv)) => self.bad = true,
                    _ => {}
                }
            }
        }
        let mut u = Uses { rv, bad: false, places: 0, ret: false };
        for b in p.funcs.iter().map(|f| &f.body).chain(std::iter::once(&p.main.body)) {
            w_block(&mut u, b);
        }
        // An early `Return`, a jump or a label in this routine could leave `Result` unset (it would read 0 before).
        let mut own = Uses { rv, bad: false, places: 0, ret: false };
        w_block(&mut own, &p.funcs[fi].body[..=k]);
        u.ret = own.ret;
        let body = &p.funcs[fi].body;
        let mut clears = 0;
        for s in &body[..k] {
            if let St::Clear(c) = &s.st {
                if matches!(c.base, Base::Var(v) if v == rv) && c.off == 0 && c.idx.is_none() && c.bit.is_none() && c.dbit.is_none() {
                    clears += 1;
                }
            }
        }
        // `places` counts the clears, the final target, and nothing else.
        if u.bad || u.ret || u.places != clears + 1 {
            continue 'next;
        }
        // Apply: the final assignment becomes a plain call, the clears go, and every read of `rv` reads `gv`.
        let body = &mut p.funcs[fi].body;
        let ret = body.pop().unwrap();
        let last = body.pop().unwrap();
        let St::Assign(_, Ex { k: ExK::Call(g, args), .. }) = last.st else { unreachable!() };
        body.retain(|s| !matches!(&s.st, St::Clear(c) if matches!(c.base, Base::Var(v) if v == rv)));
        body.push(S { st: St::Call(g, args), span: last.span });
        body.push(ret);
        for f in p.funcs.iter_mut() {
            if f.result == Some(rv) {
                f.result = Some(gv);
            }
        }
        let mut rename = |e: &mut Ex| {
            if let ExK::Load(pl) = &mut e.k {
                if matches!(pl.base, Base::Var(v) if v == rv) {
                    pl.base = Base::Var(gv);
                }
            }
        };
        for f in p.funcs.iter_mut() {
            m_block(&mut f.body, &mut rename);
        }
        m_block(&mut p.main.body, &mut rename);
        changed = true;
        // The call graph and the hot set are unchanged by this rewrite; the next candidate may chain onto `gv`.
    }
    changed
}

/// A routine that ends with `Result = v`, `v` a scalar local of the same type, keeps its value in `v` itself:
/// `v` becomes the routine's result and the final copy goes (with it, a callee-side `movff` per byte). Only when
/// nothing else in the routine touches `Result` but whole-object clears at its top level (which go too: `v` holds the
/// value), and no `Return`, jump or label could leave the routine before the copy (it would have returned the old
/// `Result`, not `v`).
fn coalesce_results(p: &mut Program) -> bool {
    let mut asm_lines: Vec<String> = Vec::new();
    {
        let mut refs: Vec<&String> = Vec::new();
        for b in p.funcs.iter().map(|f| &f.body).chain(std::iter::once(&p.main.body)) {
            collect_asm(b, &mut refs);
        }
        asm_lines.extend(refs.into_iter().cloned());
    }
    let named = |asm: &str| asm_lines.iter().any(|l| l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).any(|t| t == asm));
    let whole = |pl: &Place, v: VarId, ty: &Ty| matches!(pl.base, Base::Var(x) if x == v) && pl.off == 0 && pl.bit.is_none() && pl.idx.is_none() && pl.dbit.is_none() && pl.ty == *ty;
    struct Uses {
        v: VarId,
        loads: usize,
        writes: usize,
        bad: bool,
        jump: bool,
    }
    impl Visit for Uses {
        fn place(&mut self, p: &Place, _: Acc) {
            if matches!(p.base, Base::Var(x) | Base::Ptr(x) if x == self.v) {
                self.writes += 1;
            }
        }
        fn ex(&mut self, e: &Ex) {
            match &e.k {
                ExK::Load(p) if matches!(p.base, Base::Var(x) | Base::Ptr(x) if x == self.v) => self.loads += 1,
                ExK::Addr(p) if matches!(p.base, Base::Var(x) | Base::Ptr(x) if x == self.v) => self.bad = true,
                _ => {}
            }
        }
        fn stmt(&mut self, s: &S) {
            match &s.st {
                St::Return | St::Goto(_) | St::GoSub(_) | St::SubRet | St::Label(_) => self.jump = true,
                St::Save { items, .. } if items.contains(&SaveIt::Var(self.v)) => self.bad = true,
                St::StrSet { parts, .. } if parts.iter().any(|q| matches!(q, StrSrc::Ram(pl) if matches!(pl.base, Base::Var(x) if x == self.v))) => self.bad = true,
                St::Copy { src, .. } if matches!(src.base, Base::Var(x) if x == self.v) => self.bad = true,
                _ => {}
            }
        }
    }
    // A routine called through its address, from `Asm` or from C expects its `Result` where it always was.
    let other_callers = reachable_otherwise(p);
    let mut changed = false;
    for fi in 0..p.funcs.len() {
        if p.funcs[fi].ext || p.funcs[fi].reg || other_callers.contains(&fi) || p.exports.iter().any(|e| e.thunk == fi) {
            continue;
        }
        let Some(rv) = p.funcs[fi].result else { continue };
        let rvar = &p.vars[rv];
        if rvar.kind != VarKind::Result || rvar.owner != Some(fi) || rvar.by_ref || rvar.volatile || rvar.init.is_some() || !matches!(rvar.ty, Ty::Int(..)) {
            continue;
        }
        let rty = rvar.ty.clone();
        let body = &p.funcs[fi].body;
        if !matches!(body.last().map(|s| &s.st), Some(St::Return)) || body.len() < 2 {
            continue;
        }
        let k = body.len() - 2;
        let St::Assign(pl, ex) = &body[k].st else { continue };
        let ExK::Load(q) = &ex.k else { continue };
        let Base::Var(v) = q.base else { continue };
        if !whole(pl, rv, &rty) || !whole(q, v, &rty) || v == rv || ex.w != q.width() {
            continue;
        }
        let vvar = &p.vars[v];
        if vvar.kind != VarKind::Local || vvar.owner != Some(fi) || vvar.by_ref || vvar.volatile || vvar.init.is_some() || vvar.bytes != rvar.bytes {
            continue;
        }
        if named(&rvar.asm) || named(&vvar.asm) {
            continue;
        }
        // In the routine, before the copy: no load of `Result`, only top-level whole clears of it, no way out.
        let mut own = Uses { v: rv, loads: 0, writes: 0, bad: false, jump: false };
        w_block(&mut own, &body[..k]);
        let clears = body[..k].iter().filter(|s| matches!(&s.st, St::Clear(c) if whole(c, rv, &rty))).count();
        if own.bad || own.jump || own.loads > 0 || own.writes != clears {
            continue;
        }
        let mut vu = Uses { v, loads: 0, writes: 0, bad: false, jump: false };
        w_block(&mut vu, &body[..k]);
        if vu.bad {
            continue;
        }
        // Elsewhere `Result` may only be read (those loads are renamed).
        let mut other = Uses { v: rv, loads: 0, writes: 0, bad: false, jump: false };
        for (g, f) in p.funcs.iter().enumerate() {
            if g != fi {
                w_block(&mut other, &f.body);
            }
        }
        w_block(&mut other, &p.main.body);
        if other.bad || other.writes > 0 {
            continue;
        }
        let body = &mut p.funcs[fi].body;
        body.remove(k);
        body.retain(|s| !matches!(&s.st, St::Clear(c) if whole(c, rv, &rty)));
        p.funcs[fi].result = Some(v);
        p.vars[v].kind = VarKind::Result;
        let mut rename = |e: &mut Ex| {
            if let ExK::Load(pl) = &mut e.k
                && matches!(pl.base, Base::Var(x) if x == rv)
            {
                pl.base = Base::Var(v);
            }
        };
        for f in p.funcs.iter_mut() {
            m_block(&mut f.body, &mut rename);
        }
        m_block(&mut p.main.body, &mut rename);
        changed = true;
    }
    changed
}

/// A counted loop whose body never mentions its variable counts with that variable instead of a hidden byte
/// (`Count` followed by the store of the last value). The variable then holds the count while the loop runs,
/// so a global is used only when nothing outside the main program mentions it (an interrupt handler or a routine
/// it calls could otherwise see the count).
fn share_counters(p: &mut Program) -> bool {
    let vars = p.vars.clone();
    let mut outside: HashSet<VarId> = HashSet::new();
    let mut read: HashSet<VarId> = HashSet::new();
    for (owner, body) in all_bodies(p) {
        read.extend(scan(body).read);
        if owner.is_some() {
            let f = scan(body);
            outside.extend(f.read);
            outside.extend(f.written);
        }
    }
    fn walk(blk: &mut Vec<S>, vars: &[Var], outside: &HashSet<VarId>, read: &HashSet<VarId>) -> bool {
        let mut changed = false;
        for i in 0..blk.len() {
            for sub in blocks_mut(&mut blk[i].st) {
                changed |= walk(sub, vars, outside, read);
            }
            if i + 1 >= blk.len() {
                continue;
            }
            let target = match (&blk[i].st, &blk[i + 1].st) {
                (St::Count { counter, step: None, body, .. }, St::Assign(vp, e)) => match (&counter.base, whole_var(vp, vars)) {
                    (Base::Var(h), Some(v))
                        if vars[*h].kind == VarKind::Hidden
                            && *h != v
                            && vars[v].bytes == 1
                            && !vars[v].volatile
                            // A variable nothing reads is dropped with its stores, so a hidden counter is the cheaper one.
                            && read.contains(&v)
                            && e.as_const().is_some()
                            && (vars[v].kind != VarKind::Global || !outside.contains(&v))
                            && !blocks_count_loop(body, v, true, true) =>
                    {
                        Some(vp.clone())
                    }
                    _ => None,
                },
                _ => None,
            };
            if let Some(vp) = target {
                if let St::Count { counter, .. } = &mut blk[i].st {
                    *counter = vp;
                    changed = true;
                }
            }
        }
        changed
    }
    let mut changed = false;
    for (_, body) in all_bodies(p) {
        changed |= walk(body, &vars, &outside, &read);
    }
    changed
}

pub fn optimize(p: &mut Program) {
    for _ in 0..8 {
        fold_all(p);
        let mut changed = range_checks(p);
        changed |= propagate_params(p);
        changed |= specialize_literals(p);
        fold_all(p);
        changed |= propagate_locals(p);
        changed |= drop_dead(p);
        if !changed {
            break;
        }
    }
    share_counters(p);
    coalesce_results(p);
    if share_results(p) {
        drop_dead(p);
    }
    // Last: later passes would not know about a table walk.
    if flash_walk(p) {
        drop_dead(p);
    }
}
