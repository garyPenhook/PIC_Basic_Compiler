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

/// A `ByRef` string parameter that every caller sets to the same literal (and the routine only
/// reads) reads the literal straight from program memory, so no RAM copy is needed.
fn specialize_literals(p: &mut Program) -> bool {
    let mut all = Facts::default();
    let mut per: Vec<Facts> = Vec::new();
    for f in &p.funcs {
        per.push(scan(&f.body));
    }
    for (_, body) in all_bodies(p) {
        w_block(&mut all, body);
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
            if !var.by_ref || !matches!(var.ty, crate::types::Ty::Str(_)) || !per[fi].read.contains(&pv) || per[fi].ptr_stmt.contains(&pv) || per[fi].raw.contains(&pv) || per[fi].addr.contains(&pv) {
                continue;
            }
            let mut lit: Option<VarId> = None;
            let mut ok = true;
            for site in sites {
                let arg = site.iter().find(|(pl, _)| matches!(pl.base, Base::Var(v) if v == pv));
                match arg {
                    Some((_, Ex { k: ExK::Addr(a), .. })) if a.off == 0 && a.idx.is_none() => match a.base {
                        Base::Var(l) if p.vars[l].name == "(string literal)" && lit.is_none_or(|x| x == l) => lit = Some(l),
                        _ => ok = false,
                    },
                    _ => ok = false,
                }
            }
            let Some(l) = lit.filter(|_| ok) else { continue };
            // The literal's text is the argument of its start-up copy.
            let mut text: Option<Vec<u8>> = None;
            for s in &p.main.body {
                if let St::StrSet { dst, parts, .. } = &s.st
                    && matches!(dst.base, Base::Var(v) if v == l)
                    && let [StrSrc::Lit(b)] = parts.as_slice()
                {
                    text = Some(b.clone());
                }
            }
            let Some(mut bytes) = text else { continue };
            bytes.push(0);
            let f = p.flash.len();
            p.flash.push(FlashObj { asm: format!("__SLIT{f}"), bytes });
            m_block(&mut p.funcs[fi].body, &mut |e: &mut Ex| {
                if let ExK::Load(pl) = &mut e.k
                    && matches!(pl.base, Base::Ptr(v) if v == pv)
                {
                    pl.base = Base::Flash(f);
                }
            });
            changed = true;
        }
    }
    changed
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
}
