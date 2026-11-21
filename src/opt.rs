//! IR optimisation, run between lowering and code generation.
//!
//! * Constant folding of integer expressions.
//! * A `ByVal` parameter that every caller passes the same constant, and the routine never
//!   writes, becomes that constant inside the routine.
//! * Straight-line propagation of constants held in a routine's own locals.
//! * Removal of stores to locals and parameters nothing reads, and of the matching arguments.
//! * A call of a routine that only returns a constant is replaced by the constant.
//! * `specialize_best`: calls that pass constants get a private copy of the routine (so `PinOk(18)` and
//!   `PinOk(17)` each fold to a constant); a copy is kept only when the generated program is smaller.
//! * `global_value_sets`: a global every reachable store sets to a constant holds one of a few known values, so a
//!   comparison that is the same for all of them is a constant (a bus mode that only an uncalled `Init` sets costs
//!   nothing).
//! * `pool_literals`: the RAM copies of string literals share one block, filled by one table copy at start-up.
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
        // `(x - c) - v` is `x - (v + c)` in wrap-around arithmetic at one width, and `v + 1` is one instruction where the
        // difference of two variables minus one takes a negate (`tmp(n - 1 - i)`: 2 words instead of 3).
        ExK::Bin(BinKind::Sub, a, b)
            if b.w == w
                && b.as_const().is_none()
                && matches!(&b.k, ExK::Load(p) if !p.indirect() && p.idx.is_none() && p.dbit.is_none())
                && matches!(&a.k, ExK::Bin(BinKind::Sub, x, c) if a.w == w && x.w == w && c.w == w && x.as_const().is_none() && c.as_const().is_some()) =>
        {
            let ExK::Bin(_, x, c) = &a.k else { return };
            let (x, c) = ((**x).clone(), c.as_const().unwrap_or(0));
            let plus = Ex::new(ExK::Bin(BinKind::Add, b.clone(), Box::new(Ex::konst(c, w, signed))), w, b.signed);
            *e = Ex::new(ExK::Bin(BinKind::Sub, Box::new(x), Box::new(plus)), w, signed);
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

/// Routines whose frames a `Save` copies: the routines it names and those called inside its block, with everything
/// they call. The passes that propagate into parameters leave these alone (a saved frame is copied as it stands).
fn saved_funcs(p: &Program) -> HashSet<FuncId> {
    struct Saves(HashSet<FuncId>);
    impl Visit for Saves {
        fn stmt(&mut self, s: &S) {
            if let St::Save { items, body, .. } = &s.st {
                for i in items {
                    if let SaveIt::Func(f) = i {
                        self.0.insert(*f);
                    }
                }
                self.0.extend(scan(body).sites.into_keys());
            }
        }
    }
    let mut sv = Saves(HashSet::new());
    for b in p.funcs.iter().map(|f| &f.body).chain(std::iter::once(&p.main.body)) {
        w_block(&mut sv, b);
    }
    let mut seen = sv.0;
    let mut todo: Vec<FuncId> = seen.iter().copied().collect();
    while let Some(f) = todo.pop() {
        for g in scan(&p.funcs[f].body).sites.into_keys() {
            if seen.insert(g) {
                todo.push(g);
            }
        }
    }
    seen
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
    let saved = saved_funcs(p);
    let mut changed = false;
    for fi in 0..p.funcs.len() {
        if isr.contains(&fi) || all.faddr.contains(&fi) || per[fi].asm || saved.contains(&fi) {
            continue;
        }
        let Some(sites) = all.sites.get(&fi) else { continue };
        for &pv in &p.funcs[fi].params.clone() {
            let var = &p.vars[pv];
            if var.kind != VarKind::Param || var.by_ref || all.addr.contains(&pv) || per[fi].written.contains(&pv) || p.funcs[fi].result == Some(pv) {
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

/// A `ByRef` parameter that every call sets to the address of the same global (`Aht30Measure(t, rh)`, or a routine
/// that passes its own `ByRef` parameter on once that one is settled) names the global directly: the pointer and its
/// copies go, and accesses through FSR0 become direct ones. Only a global: other passes take a routine's own locals
/// to change only in that routine or through an address they can see. The rewrite is kept only when nothing in the
/// routine mentions the parameter afterwards (`drop_dead` then removes the arguments).
fn propagate_ref_params(p: &mut Program) -> bool {
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
    // Handlers, C and raw assembly (`reachable_otherwise`) call routines with arguments this pass does not see.
    let isr: HashSet<FuncId> = p.isrs.iter().map(|(f, _)| *f).chain(p.exports.iter().map(|e| e.func)).chain(reachable_otherwise(p)).collect();
    let saved = saved_funcs(p);
    let mut changed = false;
    for fi in 0..p.funcs.len() {
        let func = &p.funcs[fi];
        if isr.contains(&fi) || all.faddr.contains(&fi) || per[fi].asm || saved.contains(&fi) || func.reg || func.ext {
            continue;
        }
        let Some(sites) = all.sites.get(&fi) else { continue };
        if sites.is_empty() {
            continue;
        }
        for &pv in &p.funcs[fi].params.clone() {
            let var = &p.vars[pv];
            // (Stores through the pointer, and its address passed on as `Addr(Ptr(pv))`, are what the rewrite turns
            // into the global; a store to the pointer itself or its own address is still there afterwards.)
            if var.kind != VarKind::Param || !var.by_ref || var.volatile || matches!(var.ty, Ty::Str(_)) {
                continue;
            }
            // The one address every call passes.
            let mut target: Option<Ex> = None;
            let mut ok = true;
            for site in sites {
                let arg = site.iter().find(|(pl, _)| matches!(pl.base, Base::Var(v) if v == pv) && pl.off == 0 && pl.bit.is_none() && pl.idx.is_none());
                match arg {
                    Some((_, e @ Ex { k: ExK::Addr(a), .. }))
                        if a.idx.is_none() && a.bit.is_none() && a.dbit.is_none()
                            && matches!(a.base, Base::Var(g) if p.vars[g].kind == VarKind::Global && !p.vars[g].by_ref) =>
                    {
                        match &target {
                            None => target = Some(e.clone()),
                            Some(t) if t == e => {}
                            _ => ok = false,
                        }
                    }
                    _ => ok = false,
                }
                if !ok {
                    break;
                }
            }
            let Some(target) = target.filter(|_| ok) else { continue };
            let ExK::Addr(tp) = &target.k else { continue };
            let (Base::Var(g), base_off) = (tp.base.clone(), tp.off) else { continue };
            let mut body = p.funcs[fi].body.clone();
            let retarget = |pl: &mut Place| {
                if pl.base == Base::Ptr(pv) {
                    pl.base = Base::Var(g);
                    pl.off += base_off;
                }
            };
            m_block(&mut body, &mut |e: &mut Ex| match &mut e.k {
                ExK::Load(pl) if pl.base == Base::Var(pv) && pl.off == 0 && pl.bit.is_none() && pl.idx.is_none() && pl.dbit.is_none() && e.w == target.w => {
                    *e = target.clone();
                }
                ExK::Load(pl) | ExK::Addr(pl) => retarget(pl),
                _ => {}
            });
            stmt_places(&mut body, &mut |pl: &mut Place| retarget(pl), &mut |_| {});
            let after = scan(&body);
            if after.read.contains(&pv) || after.written.contains(&pv) || after.addr.contains(&pv) || after.raw.contains(&pv) || after.ptr_stmt.contains(&pv) || after.ptr_written.contains(&pv) {
                continue;
            }
            p.funcs[fi].body = body;
            changed = true;
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
    let saved = saved_funcs(p);
    let mut changed = false;
    for fi in 0..p.funcs.len() {
        if isr.contains(&fi) || all.faddr.contains(&fi) || per[fi].asm || saved.contains(&fi) {
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

/// The routines the program can run: those the main program, an interrupt handler or C (`Export`, `Extern`)
/// calls, those whose address is taken or that an `Asm` block names, and everything they call in turn.
fn reachable_funcs(p: &Program) -> HashSet<FuncId> {
    let mut seen: HashSet<FuncId> = reachable_otherwise(p);
    seen.extend(p.isrs.iter().map(|(f, _)| *f));
    seen.extend(p.ext_funcs.iter().copied());
    for g in scan(&p.main.body).sites.into_keys() {
        seen.insert(g);
    }
    let mut todo: Vec<FuncId> = seen.iter().copied().collect();
    while let Some(f) = todo.pop() {
        for g in scan(&p.funcs[f].body).sites.into_keys() {
            if seen.insert(g) {
                todo.push(g);
            }
        }
    }
    seen
}

/// Records, for each variable in `vals`, the constant stored by every write in `b`; a write that is not a
/// constant store of the whole variable removes the variable (its values are then unknown).
fn value_writes(b: &[S], vars: &[Var], vals: &mut HashMap<VarId, HashSet<u32>>) {
    let lose = |pl: &Place, vals: &mut HashMap<VarId, HashSet<u32>>| {
        if let Base::Var(v) | Base::Ptr(v) = pl.base {
            vals.remove(&v);
        }
    };
    for s in b {
        match &s.st {
            St::Assign(pl, e) => match (whole_var(pl, vars), e.as_const()) {
                (Some(v), Some(k)) if e.w == pl.width() => {
                    if let Some(set) = vals.get_mut(&v) {
                        set.insert(k & mask(pl.width()));
                    }
                }
                _ => lose(pl, vals),
            },
            St::Clear(pl) => match whole_var(pl, vars) {
                Some(v) => {
                    if let Some(set) = vals.get_mut(&v) {
                        set.insert(0);
                    }
                }
                None => lose(pl, vals),
            },
            St::Add(pl, _) | St::SetBit(pl, _) | St::ToggleBit(pl) | St::ClearMem(pl, _) | St::Direction { place: pl, .. } => lose(pl, vals),
            St::Copy { dst, .. } | St::StrSet { dst, .. } => lose(dst, vals),
            St::For { var, .. } => lose(var, vals),
            St::Count { counter, step, .. } => {
                lose(counter, vals);
                if let Some((pl, _)) = step {
                    lose(pl, vals);
                }
            }
            St::Save { items, .. } => {
                for i in items {
                    if let SaveIt::Var(v) = i {
                        vals.remove(v);
                    }
                }
            }
            // Argument places are the callee's parameters, but a global there must not be missed either.
            St::Call(_, args) => {
                for (pl, _) in args {
                    lose(pl, vals);
                }
            }
            // Every other kind writes no variable. Listed one by one, so a new kind of statement has to be decided here.
            St::FlashSeek(..)
            | St::If(..)
            | St::While(..)
            | St::Repeat(..)
            | St::Break
            | St::Continue
            | St::Return
            | St::Goto(_)
            | St::GoSub(_)
            | St::SubRet
            | St::Label(_)
            | St::Asm(_)
            | St::DelayUs(_)
            | St::DelayMs(_)
            | St::Halt
            | St::Int { .. } => {}
        }
        for sub in sub_blocks_of(&s.st) {
            value_writes(sub, vars, vals);
        }
    }
}

/// Drops, at any depth, the arms of an `If` whose condition is a constant false, and makes a constant true one the
/// `Else` (later arms go). An arm that holds a label, `Goto` or `GoSub` is kept with everything around it. An `If`
/// left with no arm is replaced by its `Else` block.
fn prune_const_ifs(b: &mut Vec<S>) -> bool {
    let mut changed = false;
    let mut out: Vec<S> = Vec::with_capacity(b.len());
    for mut s in std::mem::take(b) {
        for sub in blocks_mut(&mut s.st) {
            changed |= prune_const_ifs(sub);
        }
        let decided = matches!(&s.st, St::If(arms, _) if arms.iter().any(|(c, _)| c.as_const().is_some()));
        if decided
            && !has_jump_target(std::slice::from_ref(&s))
            && let St::If(arms, other) = &mut s.st
        {
            let mut kept = Vec::new();
            for (c, blk) in std::mem::take(arms) {
                match c.as_const() {
                    Some(0) => {}
                    Some(_) => {
                        *other = blk;
                        break;
                    }
                    None => kept.push((c, blk)),
                }
            }
            changed = true;
            if kept.is_empty() {
                out.append(other);
                continue;
            }
            *arms = kept;
        }
        out.push(s);
    }
    *b = out;
    changed
}

/// A global that every reachable store sets to a constant holds one of a few known values: those constants and its
/// start-up value (its `init`, or 0, since start-up clears the globals). A comparison of the variable with a constant
/// that comes out the same for every one of them is that constant, and the `If` arms it decides go. So a module that
/// picks its bus at run time (`If mode = 1 … ElseIf mode = 2`) loses the code for the bus the program never starts:
/// `oled` over I2C drops its SPI path when `OledInitSpi`, the only store of 2, is never called.
/// Only scalar globals (not `Volatile`, address never taken, not named in an `Asm` block), and nothing for a program
/// that links with C (calls it or is called by it), which could write any global.
fn global_value_sets(p: &mut Program) -> bool {
    if p.c_link() || !p.cfiles.is_empty() {
        return false;
    }
    let reach = reachable_funcs(p);
    let mut vals: HashMap<VarId, HashSet<u32>> = HashMap::new();
    for (i, v) in p.vars.iter().enumerate() {
        let scalar = matches!(v.ty, Ty::Int(8 | 16 | 32, _) | Ty::Bool) && v.bytes * 8 == match v.ty {
            Ty::Int(w, _) => w as u32,
            _ => 8,
        };
        if v.kind == VarKind::Global && v.owner.is_none() && scalar && !v.volatile && !v.by_ref {
            vals.insert(i, HashSet::from([v.init.unwrap_or(0) & mask((v.bytes * 8) as u8)]));
        }
    }
    let mut all = Facts::default();
    let mut lines: Vec<&String> = Vec::new();
    let bodies: Vec<&Vec<S>> = p.funcs.iter().enumerate().filter(|(i, _)| reach.contains(i)).map(|(_, f)| &f.body).chain(std::iter::once(&p.main.body)).collect();
    for b in &bodies {
        w_block(&mut all, b);
        collect_asm(b, &mut lines);
        value_writes(b, &p.vars, &mut vals);
    }
    // An address taken anywhere, also in code not reached, keeps the variable out.
    for f in &p.funcs {
        let fx = scan(&f.body);
        all.addr.extend(fx.addr);
    }
    let in_asm: HashSet<&str> = lines.iter().flat_map(|l| l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))).collect();
    vals.retain(|v, set| !all.addr.contains(v) && set.len() <= 16 && !in_asm.contains(p.vars[*v].asm.as_str()));
    if vals.is_empty() {
        return false;
    }
    let vars = &p.vars;
    let mut changed = false;
    let mut decide = |e: &mut Ex| {
        let ExK::Cmp(k, a, b) = &e.k else { return };
        let (x, c, k) = match (&a.k, b.as_const()) {
            (ExK::Load(_), Some(c)) => (a, c, *k),
            _ => match (&b.k, a.as_const()) {
                (ExK::Load(_), Some(c)) => (b, c, k.swap()),
                _ => return,
            },
        };
        let ExK::Load(pl) = &x.k else { return };
        let Some(v) = whole_var(pl, vars) else { return };
        let Some(set) = vals.get(&v) else { return };
        if x.w != pl.width() || a.w != b.w {
            return;
        }
        // Each value in place of the variable, compared by `fold` itself.
        let signed = a.signed || b.signed;
        let mut res = set.iter().map(|&val| {
            let mut t = Ex::new(ExK::Cmp(k, Box::new(Ex::konst(val, x.w, signed)), Box::new(Ex::konst(c, x.w, signed))), e.w, e.signed);
            fold(&mut t);
            t.as_const()
        });
        let first = res.next().unwrap();
        if first.is_some() && res.all(|r| r == first) {
            *e = Ex::konst(first.unwrap(), e.w, e.signed);
            changed = true;
        }
    };
    for (fi, body) in p.funcs.iter_mut().enumerate().map(|(i, f)| (Some(i), &mut f.body)).chain(std::iter::once((None, &mut p.main.body))) {
        if fi.is_some_and(|i| !reach.contains(&i)) {
            continue;
        }
        m_block(body, &mut decide);
    }
    if changed {
        for (_, body) in all_bodies(p) {
            m_block(body, &mut fold);
            prune_const_ifs(body);
        }
    }
    changed
}

/// A statement that may leave its routine (`Return`, also inside a block).
fn may_return(s: &S) -> bool {
    matches!(s.st, St::Return) || sub_blocks_of(&s.st).into_iter().any(|b| b.iter().any(may_return))
}

/// [`global_value_sets`] after the variable is first set. Start-up gives a global its `init` (or 0), and a module's
/// own state often keeps it there only until its set-up routine runs: `mode = 1` in `OledInitI2c`, `ready = True` in
/// `I2cInit`. Code that runs only after that store cannot see the start-up value, so its `If mode = 0 Then Exit`
/// checks (in every `oled` routine) are decided by the values stores write.
///
/// The settling point is the first top-level statement of the main program that stores a constant into the variable,
/// itself or in a routine it calls (a top-level store of that routine with nothing before it that can return). Code
/// after it runs later: the main program's later statements, the routine's statements after the store, and every
/// routine all of whose calls are in such code (not a handler, not one C, raw assembly or an address can reach). In
/// that code a variable only ever set to one constant reads as that constant, and a comparison that comes out the same
/// for every stored value is decided. Same limits as `global_value_sets`, and nothing when the main program or the
/// routine has labels a `Goto` could jump to (statement order would not be the order they run in).
fn global_values_after_init(p: &mut Program) -> bool {
    if p.c_link() || !p.cfiles.is_empty() || crate::ir::has_jump_target(&p.main.body) {
        return false;
    }
    let reach = reachable_funcs(p);
    let other = reachable_otherwise(p);
    let isr: HashSet<FuncId> = p.isrs.iter().map(|(f, _)| *f).collect();
    // The values each store writes (the start-up value is not one of them).
    let mut written: HashMap<VarId, HashSet<u32>> = HashMap::new();
    for (i, v) in p.vars.iter().enumerate() {
        let scalar = matches!(v.ty, Ty::Int(8 | 16 | 32, _) | Ty::Bool) && v.bytes * 8 == match v.ty {
            Ty::Int(w, _) => w as u32,
            _ => 8,
        };
        if v.kind == VarKind::Global && v.owner.is_none() && scalar && !v.volatile && !v.by_ref {
            written.insert(i, HashSet::new());
        }
    }
    let mut all = Facts::default();
    let mut lines: Vec<&String> = Vec::new();
    for b in p.funcs.iter().enumerate().filter(|(i, _)| reach.contains(i)).map(|(_, f)| &f.body).chain(std::iter::once(&p.main.body)) {
        w_block(&mut all, b);
        collect_asm(b, &mut lines);
        value_writes(b, &p.vars, &mut written);
    }
    for f in &p.funcs {
        all.addr.extend(scan(&f.body).addr);
    }
    let in_asm: HashSet<&str> = lines.iter().flat_map(|l| l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))).collect();
    written.retain(|v, set| !set.is_empty() && set.len() <= 16 && !all.addr.contains(v) && !in_asm.contains(p.vars[*v].asm.as_str()));
    // (A `Save` of a routine's frame restores that routine's locals, never a global; a saved global is dropped by
    // `value_writes`.)
    if written.is_empty() {
        return false;
    }
    let store_of = |st: &S, v: VarId, vars: &[Var]| match &st.st {
        St::Assign(pl, e) => whole_var(pl, vars) == Some(v) && e.as_const().is_some() && e.w == pl.width(),
        St::Clear(pl) => whole_var(pl, vars) == Some(v),
        _ => false,
    };
    let mut changed = false;
    let mut vars_sorted: Vec<VarId> = written.keys().copied().collect();
    vars_sorted.sort_unstable();
    for v in vars_sorted {
        let set = written[&v].clone();
        // The settling point: (main statement, and the routine with its store when the store is in one).
        let mut settle: Option<(usize, Option<(FuncId, usize)>)> = None;
        for (s, st) in p.main.body.iter().enumerate() {
            if store_of(st, v, &p.vars) {
                settle = Some((s, None));
                break;
            }
            // The routines the statement always calls: itself a call, or a call in the value it stores or in the
            // first condition it tests (not on the right of `AndAlso` / `OrElse`, which may be skipped).
            fn always(e: &Ex, out: &mut Vec<FuncId>) {
                match &e.k {
                    ExK::Call(f, args) => {
                        for (_, a) in args {
                            always(a, out);
                        }
                        out.push(*f);
                    }
                    ExK::AndAlso(a, _) | ExK::OrElse(a, _) => always(a, out),
                    ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) => {
                        always(a, out);
                        always(b, out);
                    }
                    ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => always(x, out),
                    _ => {}
                }
            }
            let mut callees: Vec<FuncId> = Vec::new();
            match &st.st {
                St::Call(f, args) => {
                    for (_, a) in args {
                        always(a, &mut callees);
                    }
                    callees.push(*f);
                }
                St::Assign(_, e) => always(e, &mut callees),
                St::If(arms, _) => {
                    if let Some((c, _)) = arms.first() {
                        always(c, &mut callees);
                    }
                }
                St::While(c, _) => always(c, &mut callees),
                _ => {}
            }
            let mut hit: Option<(FuncId, usize)> = None;
            for &f in &callees {
                let body = &p.funcs[f].body;
                if isr.contains(&f) || p.funcs[f].ext || p.funcs[f].reg || crate::ir::has_jump_target(body) {
                    continue;
                }
                if let Some(w) = body.iter().position(|x| store_of(x, v, &p.vars))
                    && !body[..w].iter().any(may_return)
                {
                    hit = Some((f, w));
                    break;
                }
            }
            if let Some(h) = hit {
                settle = Some((s, Some(h)));
                break;
            }
        }
        let Some((s, inner)) = settle else { continue };
        // Routines whose every call is in code that runs after the settling point: the largest such set.
        let init_f = inner.map(|x| x.0);
        let mut late: HashSet<FuncId> = (0..p.funcs.len())
            .filter(|f| reach.contains(f) && !isr.contains(f) && !other.contains(f) && Some(*f) != init_f && !p.funcs[*f].ext && !p.funcs[*f].reg)
            .collect();
        loop {
            let mut ok: HashSet<FuncId> = late.clone();
            // Each call site and whether it is in late code.
            let note = |b: &[S], is_late: bool, ok: &mut HashSet<FuncId>| {
                let calls = scan(b).sites;
                if !is_late {
                    for f in calls.keys() {
                        ok.remove(f);
                    }
                }
            };
            for (i, st) in p.main.body.iter().enumerate() {
                note(std::slice::from_ref(st), i > s, &mut ok);
            }
            for f in 0..p.funcs.len() {
                if !reach.contains(&f) {
                    continue;
                }
                if Some(f) == init_f {
                    let w = inner.unwrap().1;
                    for (j, st) in p.funcs[f].body.iter().enumerate() {
                        note(std::slice::from_ref(st), j > w, &mut ok);
                    }
                } else {
                    let l = late.contains(&f);
                    note(&p.funcs[f].body, l, &mut ok);
                }
            }
            if ok == late {
                break;
            }
            late = ok;
        }
        let vars = p.vars.clone();
        let single = (set.len() == 1).then(|| *set.iter().next().unwrap());
        let mut hit = false;
        let mut decide = |e: &mut Ex| {
            if let (Some(k), ExK::Load(pl)) = (single, &e.k)
                && whole_var(pl, &vars) == Some(v)
                && e.w == pl.width()
            {
                *e = Ex::konst(k, e.w, e.signed);
                hit = true;
                return;
            }
            let ExK::Cmp(op, a, b) = &e.k else { return };
            let (x, c, op) = match (&a.k, b.as_const()) {
                (ExK::Load(_), Some(c)) => (a, c, *op),
                _ => match (&b.k, a.as_const()) {
                    (ExK::Load(_), Some(c)) => (b, c, op.swap()),
                    _ => return,
                },
            };
            let ExK::Load(pl) = &x.k else { return };
            if whole_var(pl, &vars) != Some(v) || x.w != pl.width() || a.w != b.w {
                return;
            }
            let signed = a.signed || b.signed;
            let mut res = set.iter().map(|&val| {
                let mut t = Ex::new(ExK::Cmp(op, Box::new(Ex::konst(val, x.w, signed)), Box::new(Ex::konst(c, x.w, signed))), e.w, e.signed);
                fold(&mut t);
                t.as_const()
            });
            let first = res.next().unwrap();
            if first.is_some() && res.all(|r| r == first) {
                *e = Ex::konst(first.unwrap(), e.w, e.signed);
                hit = true;
            }
        };
        if p.main.body.len() > s + 1 {
            m_block(&mut p.main.body[s + 1..], &mut decide);
        }
        if let Some((f, w)) = inner && p.funcs[f].body.len() > w + 1 {
            m_block(&mut p.funcs[f].body[w + 1..], &mut decide);
        }
        for f in &late {
            m_block(&mut p.funcs[*f].body, &mut decide);
        }
        changed |= hit;
    }
    if changed {
        for (_, body) in all_bodies(p) {
            m_block(body, &mut fold);
            prune_const_ifs(body);
        }
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
    }
    // A `Save` copies the frames of the routines it reaches as they stand: their variables stay.
    let saved = saved_funcs(p);
    let dead = |vars: &[Var], v: VarId| {
        let var = &vars[v];
        !var.volatile && matches!(var.kind, VarKind::Local | VarKind::Param | VarKind::Hidden) && var.owner.map_or(!main_asm, |o| !pinned.contains(&o) && !saved.contains(&o)) && !all.read.contains(&v)
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
        let mut lines: Vec<&String> = Vec::new();
        collect_asm(body, &mut lines);
        for l in lines {
            in_asm.extend(l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).map(str::to_string));
        }
    }
    // (Globals only: a `Save` of a routine copies that routine's frame, and a global it lists counts as read.)
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

/// PIC16 typed-source guard: no operation can alter or observe the page latch, including
/// its interrupt shadow, indirect registers, pointer parameters and register aliases. The
/// emitted raw assembly must be checked separately by the code generator.
pub(crate) fn preserves_page_zero(p: &Program, tgt: &crate::codegen::Target) -> bool {
    struct Uses { bad: bool, special: Vec<u32> }
    impl Uses {
        fn access(&mut self, pl: &Place, bytes: u32) {
            match &pl.base {
                Base::Ptr(_) => self.bad = true,
                Base::Abs { addr, name } => {
                    self.bad |= pl.idx.is_some() || crate::ir::indirect_sfr(name)
                        || (0..bytes).any(|off| {
                            let a = addr.saturating_add(pl.off).saturating_add(off);
                            matches!(a & 0x7f, 0 | 1 | 2 | 10)
                                || self.special.contains(&a)
                        });
                }
                _ => {}
            }
        }
    }
    impl Visit for Uses {
        fn place(&mut self, pl: &Place, _: Acc) { self.access(pl, pl.bytes()); }
        fn ex(&mut self, e: &Ex) {
            if let ExK::Load(pl) | ExK::Addr(pl) = &e.k { self.access(pl, pl.bytes()); }
        }
        fn stmt(&mut self, s: &S) {
            match &s.st {
                St::ClearMem(pl, bytes) => self.access(pl, *bytes),
                St::Copy { dst, src, bytes } => { self.access(dst, *bytes); self.access(src, *bytes); }
                _ => {}
            }
        }
    }
    let mut uses = Uses { bad: false, special: tgt.sfr.iter().filter(|(n, _)| n.to_ascii_uppercase().starts_with("PCL")).map(|(_, &a)| a).collect() };
    w_block(&mut uses, &p.main.body);
    for f in &p.funcs { w_block(&mut uses, &f.body); }
    !uses.bad
}

mod array_init;

/// A routine called once, as a statement of its caller, that is handed one of the caller's own variables
/// (`Digits(n)` inside `FmtDec`, `OledGoto(line)` inside `OledTextGoto`) uses that variable as its parameter when the
/// caller does not read it again: the copy into the parameter goes, and so does the parameter's RAM. Run as a storage
/// trial after every pass that takes a routine's locals to be named only by that routine (the callee now reads and
/// writes one of its caller's). Not when the call is inside a loop, which would reach the read again.
pub fn coalesce_params(p: &Program, _tgt: &crate::codegen::Target) -> Option<Program> {
    let mut q = p.clone();
    let mut all = Facts::default();
    let mut per: Vec<Facts> = Vec::new();
    for f in &q.funcs {
        per.push(scan(&f.body));
    }
    for (_, body) in all_bodies(&mut q) {
        w_block(&mut all, body);
    }
    for f in &per {
        all.addr.extend(f.addr.iter());
    }
    let saved = saved_funcs(&q);
    // Entered from outside the calls this pass sees: handlers, C, raw assembly (`reachable_otherwise`), and the
    // routines a `Save` copies.
    let outside: HashSet<FuncId> = q.isrs.iter().map(|(f, _)| *f).chain(q.exports.iter().map(|e| e.func)).chain(saved.iter().copied()).chain(reachable_otherwise(&q)).collect();
    // A variable another routine's parameter has become: renaming it in its own turn would leave that routine
    // naming a variable nothing sets any more (`Digits` reading `FmtDec`'s `n` after `n` became the caller's `w`).
    let mut targets: HashSet<VarId> = HashSet::new();
    let mut changed = false;
    for g in 0..q.funcs.len() {
        let gf = &q.funcs[g];
        if outside.contains(&g) || all.faddr.contains(&g) || per[g].asm || gf.reg || gf.ext {
            continue;
        }
        let Some(sites) = all.sites.get(&g) else { continue };
        if sites.len() != 1 {
            continue;
        }
        // The one caller and its top-level statement (one without blocks of its own) that makes the call, perhaps
        // as an argument of another call (`Close(Pad(Digits(n), width, fill))`).
        struct Find {
            g: FuncId,
            args: Option<Vec<(Place, Ex)>>,
        }
        impl Visit for Find {
            fn call(&mut self, f: FuncId, a: &[(Place, Ex)]) {
                if f == self.g {
                    self.args = Some(a.to_vec());
                }
            }
        }
        let mut found: Option<(FuncId, usize, Vec<(Place, Ex)>)> = None;
        for fi in 0..q.funcs.len() {
            if fi == g {
                continue;
            }
            for (k, st) in q.funcs[fi].body.iter().enumerate() {
                if !sub_blocks_of(&st.st).is_empty() {
                    continue;
                }
                let mut fd = Find { g, args: None };
                w_block(&mut fd, std::slice::from_ref(st));
                if let Some(a) = fd.args {
                    found = Some((fi, k, a));
                }
            }
        }
        let Some((fi, k, args)) = found else { continue };
        let ff = &q.funcs[fi];
        if outside.contains(&fi) || per[fi].asm || ff.reg || ff.ext || crate::ir::has_jump_target(&ff.body) {
            continue;
        }
        // Reads of a variable in the calling statement: the argument must be the only one, so nothing in the
        // statement sees the variable after the callee has changed it.
        struct Reads(VarId, u32);
        impl Visit for Reads {
            fn ex(&mut self, e: &Ex) {
                if let ExK::Load(pl) | ExK::Addr(pl) = &e.k && matches!(pl.base, Base::Var(v) | Base::Ptr(v) if v == self.0) {
                    self.1 += 1;
                }
            }
            fn place(&mut self, pl: &Place, a: Acc) {
                if a != Acc::Write && matches!(pl.base, Base::Var(v) | Base::Ptr(v) if v == self.0) {
                    self.1 += 1;
                }
            }
        }
        let after = scan(&ff.body[k + 1..]);
        let mut renames: Vec<(VarId, VarId)> = Vec::new();
        for (ai, (pl, e)) in args.iter().enumerate() {
            let Base::Var(pv) = pl.base else { continue };
            let ExK::Load(src) = &e.k else { continue };
            let Base::Var(qv) = src.base else { continue };
            let (pvar, qvar) = (&q.vars[pv], &q.vars[qv]);
            let whole = |x: &Place, n: u32| x.off == 0 && x.bit.is_none() && x.idx.is_none() && x.dbit.is_none() && x.bytes() == n;
            let _ = ai;
            let mut rd = Reads(qv, 0);
            w_block(&mut rd, std::slice::from_ref(&ff.body[k]));
            let other_args_read = rd.1 != 1;
            if pvar.kind != VarKind::Param || pvar.owner != Some(g) || pvar.by_ref || pvar.volatile || all.addr.contains(&pv) || q.funcs[g].result == Some(pv)
                || !matches!(qvar.kind, VarKind::Param | VarKind::Local) || qvar.owner != Some(fi) || qvar.by_ref || qvar.volatile || all.addr.contains(&qv) || ff.result == Some(qv)
                || pvar.ty != qvar.ty || pvar.bytes != qvar.bytes || !whole(pl, pvar.bytes) || !whole(src, qvar.bytes) || e.w as u32 != qvar.bytes * 8
                || after.read.contains(&qv) || after.written.contains(&qv) || other_args_read || renames.iter().any(|r| r.1 == qv)
                || targets.contains(&pv)
            {
                continue;
            }
            renames.push((pv, qv));
        }
        if renames.is_empty() {
            continue;
        }
        targets.extend(renames.iter().map(|r| r.1));
        for &(pv, qv) in &renames {
            let ren = |pl: &mut Place| {
                if pl.base == Base::Var(pv) {
                    pl.base = Base::Var(qv);
                }
            };
            m_block(&mut q.funcs[g].body, &mut |e: &mut Ex| {
                if let ExK::Load(pl) | ExK::Addr(pl) = &mut e.k {
                    ren(pl);
                }
            });
            stmt_places(&mut q.funcs[g].body, &mut |pl: &mut Place| ren(pl), &mut |_| {});
            q.funcs[g].params.retain(|&x| x != pv);
        }
        each_call(&mut q.funcs[fi].body[k..k + 1], &mut |f: &mut FuncId, a: &mut Vec<(Place, Ex)>| {
            if *f == g {
                a.retain(|(pl, _)| !renames.iter().any(|r| pl.base == Base::Var(r.0)));
            }
        });
        // Statements of the callee were rescanned per routine above; recompute before the next routine.
        per[g] = scan(&q.funcs[g].body);
        changed = true;
    }
    changed.then_some(q)
}

/// A size-checked candidate without redundant entry clears of private local arrays.
pub fn without_array_clears(p: &Program, tgt: &crate::codegen::Target) -> Option<Program> {
    array_init::candidate(p, tgt)
}

/// Try phase-local storage reuse. Code generation accepts this candidate only when RAM and flash do not grow.
pub fn compact_storage(p: &Program, tgt: &crate::codegen::Target) -> Option<Program> {
    if opaque_ram(p, tgt) { return None; }
    let mut q = p.clone();
    reuse_locals(&mut q).then_some(q)
}

fn opaque_ram(p: &Program, tgt: &crate::codegen::Target) -> bool { opaque_ram_with(p, tgt, true) }

/// `through_ptr` false ignores pointer-parameter accesses: a caller whose variable never has its address taken
/// (`scan(..).addr`) cannot be reached through one. A named special-function register is never frame RAM.
fn opaque_ram_with(p: &Program, tgt: &crate::codegen::Target, through_ptr: bool) -> bool {
    // Absolute RAM and indirect-register accesses may observe a local without naming it,
    // including from an interrupt handler while the leaf routine is running.
    struct Opaque<'a> { found: bool, tgt: &'a crate::codegen::Target, through_ptr: bool }
    impl Visit for Opaque<'_> {
        fn place(&mut self, p: &Place, _: Acc) {
            match &p.base {
                Base::Ptr(_) => self.found |= self.through_ptr,
                Base::Abs { addr, name } => {
                    let sfr = !crate::ir::indirect_sfr(name) && p.idx.is_none() && self.tgt.sfr.get(name.as_str()).is_some_and(|a| a == addr);
                    if !self.through_ptr && sfr { return; }
                    self.found |= p.idx.is_some() || crate::ir::indirect_sfr(name) || (0..p.bytes()).any(|off| {
                        let a = addr.saturating_add(p.off).saturating_add(off);
                        if let Some(mem) = &self.tgt.pic16 {
                            mem.gpr.iter().any(|&(s, e)| (s..e).contains(&a))
                                || (mem.common.0..mem.common.1).contains(&(a & 0x7f)) || a >= 0x2000
                        } else {
                            (self.tgt.access.0..self.tgt.access.1).contains(&a)
                                || self.tgt.ram.iter().any(|&(s, e)| (s..e).contains(&a))
                        }
                    });
                }
                _ => {}
            }
        }
        fn ex(&mut self, e: &Ex) {
            if let ExK::Load(pl) | ExK::Addr(pl) = &e.k { self.place(pl, Acc::Read); }
        }
    }
    let mut opaque = Opaque { found: false, tgt, through_ptr };
    w_block(&mut opaque, &p.main.body);
    for f in &p.funcs { w_block(&mut opaque, &f.body); }
    opaque.found
}

/// Share equal-sized scalar locals with disjoint top-level statement intervals. Structured
/// statements are indivisible intervals, so loop backedges cannot invalidate the analysis.
/// Each local must start with a whole assignment that does not read its previous value.
fn reuse_locals(p: &mut Program) -> bool {
    if p.c_link() || !p.cfiles.is_empty() { return false; }
    if p.funcs.iter().any(|f| scan(&f.body).asm) || scan(&p.main.body).asm { return false; }
    struct Unsafe(bool);
    impl Visit for Unsafe {
        fn stmt(&mut self, s: &S) {
            self.0 |= matches!(s.st, St::Goto(_) | St::Label(_) | St::GoSub(_) | St::SubRet | St::Save { .. });
        }
        fn place(&mut self, p: &Place, _: Acc) {
            self.0 |= matches!(p.base, Base::Abs { .. } | Base::Ptr(_));
        }
        fn ex(&mut self, e: &Ex) {
            if let ExK::Load(pl) | ExK::Addr(pl) = &e.k {
                self.place(pl, Acc::Read);
            }
        }
    }
    // Known callees may use their own frames while this frame remains live. Unknown
    // effects and recursive entry retain the reference storage scheme.
    let effects = crate::ir::routine_effects(p);
    let mut changed = false;
    for fi in 0..p.funcs.len() {
        let f = &p.funcs[fi];
        if f.ext || f.reg || effects[fi].is_none() { continue; }
        struct Calls(HashSet<FuncId>);
        impl Visit for Calls {
            fn call(&mut self, f: FuncId, _: &[(Place, Ex)]) { self.0.insert(f); }
        }
        let mut calls = Calls(HashSet::new());
        w_block(&mut calls, &f.body);
        if calls.0.iter().any(|&callee| effects[callee].as_ref().is_none_or(|e|
            callee == fi || e.reads.iter().chain(e.writes.iter()).any(|&v| p.vars[v].owner == Some(fi)))) { continue; }
        let mut unsafe_uses = Unsafe(false);
        w_block(&mut unsafe_uses, &f.body);
        if unsafe_uses.0 { continue; }
        let mut outside = scan(&p.main.body);
        for (j, other) in p.funcs.iter().enumerate() {
            if j != fi {
                let facts = scan(&other.body);
                outside.read.extend(facts.read);
                outside.written.extend(facts.written);
                outside.addr.extend(facts.addr);
            }
        }
        let facts = scan(&f.body);
        let statements: Vec<Facts> = f.body.iter().map(|s| scan(std::slice::from_ref(s))).collect();
        let mut intervals = Vec::new();
        for (v, var) in p.vars.iter().enumerate() {
            if var.kind != VarKind::Local || var.owner != Some(fi) || var.volatile || var.by_ref
                || var.init.is_some() || !matches!(var.ty, Ty::Int(..) | Ty::Bool)
                || facts.addr.contains(&v) || outside.read.contains(&v) || outside.written.contains(&v)
                || outside.addr.contains(&v) { continue; }
            // Entry clears may be dropped only after proving the first real use overwrites all bytes.
            let uses: Vec<usize> = f.body.iter().enumerate().filter_map(|(i, s)| {
                if matches!(&s.st, St::Clear(pl) if whole_var(pl, &p.vars) == Some(v)) { return None; }
                let u = &statements[i];
                (u.read.contains(&v) || u.written.contains(&v)).then_some(i)
            }).collect();
            let (Some(&first), Some(&last)) = (uses.first(), uses.last()) else { continue };
            if !matches!(&f.body[first].st, St::Assign(pl, e)
                if whole_var(pl, &p.vars) == Some(v) && !e.touches(v, true)) { continue; }
            // A later clear is a real write, not an entry initialization.
            if f.body[first..].iter().any(|s| matches!(&s.st, St::Clear(pl) if whole_var(pl, &p.vars) == Some(v))) { continue; }
            intervals.push((first, last, v));
        }
        intervals.sort_unstable();
        let mut slots: Vec<(usize, VarId)> = Vec::new();
        let mut rename = HashMap::new();
        for (first, last, v) in intervals {
            if let Some(slot) = slots.iter_mut().find(|(end, old)| *end < first && p.vars[*old].ty == p.vars[v].ty && p.vars[*old].bytes == p.vars[v].bytes) {
                rename.insert(v, slot.1);
                slot.0 = last;
            } else {
                slots.push((last, v));
            }
        }
        if rename.is_empty() { continue; }
        let body = &mut p.funcs[fi].body;
        body.retain(|s| !matches!(&s.st, St::Clear(pl) if matches!(pl.base, Base::Var(v) if rename.contains_key(&v))));
        let mut remap = |pl: &mut Place| {
            if let Base::Var(v) = &mut pl.base {
                if let Some(&to) = rename.get(v) { *v = to; }
            }
        };
        stmt_places(body, &mut remap, &mut |_| {});
        m_block(body, &mut |e| {
            if let ExK::Load(pl) | ExK::Addr(pl) = &mut e.k { remap(pl); }
        });
        changed = true;
    }
    changed
}

/// Remove scalar globals whose only uses are side-effect-free updates of themselves.
/// Check the remaining program after removing each candidate's stores: this also excludes
/// conditions, aliases, interrupt uses, and writes in forms we do not understand.
pub fn without_dead_updates(p: &Program, tgt: &crate::codegen::Target) -> Option<Program> {
    if p.c_link() || !p.cfiles.is_empty() {
        return None;
    }
    fn safe(e: &Ex, vars: &[Var]) -> bool {
        match &e.k {
            ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => true,
            ExK::Load(pl) => matches!(pl.base, Base::Var(v) if !vars[v].volatile && !vars[v].by_ref) && pl.idx.is_none() && pl.dbit.is_none(),
            ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => safe(x, vars),
            ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => safe(a, vars) && safe(b, vars),
            _ => false,
        }
    }
    let mut q = p.clone();
    // Raw assembly can access RAM through an address or an alias, not just a symbol name.
    struct Indirect<'a> { found: bool, tgt: &'a crate::codegen::Target }
    impl Visit for Indirect<'_> {
        fn place(&mut self, p: &Place, _: Acc) {
            if let Base::Abs { addr, name } = &p.base {
                let ram = (0..p.bytes()).any(|off| {
                    let a = addr.saturating_add(p.off).saturating_add(off);
                    if let Some(mem) = &self.tgt.pic16 {
                        mem.gpr.iter().any(|&(s, e)| a >= s && a < e)
                            || (mem.common.0..mem.common.1).contains(&(a & 0x7f)) || a >= 0x2000
                    } else {
                        (self.tgt.access.0..self.tgt.access.1).contains(&a)
                            || self.tgt.ram.iter().any(|&(s, e)| a >= s && a < e)
                    }
                });
                self.found |= ram || p.idx.is_some() || crate::ir::indirect_sfr(name);
            }
        }
    }
    struct Candidates<'a> { vars: &'a [Var], ids: HashSet<VarId> }
    impl Visit for Candidates<'_> {
        fn stmt(&mut self, s: &S) {
            match &s.st {
                St::Assign(pl, e) => {
                    if let Some(v) = whole_var(pl, self.vars) && e.touches(v, true) { self.ids.insert(v); }
                }
                St::Add(pl, _) => {
                    if let Some(v) = whole_var(pl, self.vars) { self.ids.insert(v); }
                }
                _ => {}
            }
        }
    }
    let mut candidates = Candidates { vars: &p.vars, ids: HashSet::new() };
    for (_, body) in all_bodies(&mut q) {
        let f = scan(body);
        let mut indirect = Indirect { found: false, tgt };
        w_block(&mut indirect, body);
        w_block(&mut candidates, body);
        if f.asm || f.save_func || indirect.found { return None; }
    }
    // Each candidate requires a whole-program check; bound compile time on large modules.
    if candidates.ids.iter().filter(|&&v| p.vars[v].kind == VarKind::Global).count() > 16 { return None; }
    let mut changed = false;
    for v in 0..q.vars.len() {
        if !candidates.ids.contains(&v) { continue; }
        let var = &q.vars[v];
        if var.kind != VarKind::Global || var.volatile || var.by_ref || !matches!(var.ty, Ty::Int(..) | Ty::Bool) { continue; }
        let mut trial = q.clone();
        let vars = trial.vars.clone();
        let mut removed = false;
        for (_, body) in all_bodies(&mut trial) {
            retain_stmts(body, &mut |s| {
                let drop = match &s.st {
                    St::Assign(pl, e) => whole_var(pl, &vars) == Some(v) && safe(e, &vars),
                    St::Add(pl, _) | St::Clear(pl) => whole_var(pl, &vars) == Some(v),
                    _ => false,
                };
                removed |= drop;
                !drop
            });
        }
        if !removed { continue; }
        let mut used = false;
        for (_, body) in all_bodies(&mut trial) {
            let f = scan(body);
            used |= f.read.contains(&v) || f.written.contains(&v) || f.addr.contains(&v);
        }
        if !used {
            trial.vars[v].init = None;
            q = trial;
            changed = true;
        }
    }
    changed.then_some(q)
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

/// True when the routine calls nothing (no call, `GoSub` or `Asm` block), so it cannot run again while one of its
/// own activations is still using its variables.
fn leaf(body: &[S]) -> bool {
    struct Calls(bool);
    impl Visit for Calls {
        fn ex(&mut self, e: &Ex) {
            if matches!(e.k, ExK::Call(..)) {
                self.0 = true;
            }
        }
        fn stmt(&mut self, s: &S) {
            if matches!(s.st, St::Call(..) | St::GoSub(_) | St::Asm(_)) {
                self.0 = true;
            }
        }
    }
    let mut c = Calls(false);
    w_block(&mut c, body);
    !c.0
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
        // `Result = r` with `r` wider than `Result` (`Isqrt`: LongWord into Word) also qualifies: the low bytes of `r`
        // are the result, and the callers read them through places of the narrower type. Only in a routine that calls
        // nothing (below), so `r` is not live in a second activation.
        let (q, narrow) = match &ex.k {
            ExK::Load(q) => (q, false),
            ExK::Conv(inner) => match &inner.k {
                ExK::Load(q) if inner.w > ex.w => (q, true),
                _ => continue,
            },
            _ => continue,
        };
        let Base::Var(v) = q.base else { continue };
        if !whole(pl, rv, &rty) || v == rv || ex.w != pl.width() {
            continue;
        }
        if narrow {
            if !matches!(q.ty, Ty::Int(..)) || !whole(q, v, &q.ty.clone()) || q.bytes() <= rvar.bytes {
                continue;
            }
        } else if !whole(q, v, &rty) || ex.w != q.width() {
            continue;
        }
        let vvar = &p.vars[v];
        // A `ByVal` parameter serves as well as a local (the caller stores the argument in it and reads the result
        // from it), in a routine that calls nothing: it cannot then be entered again while the value is in use.
        let is_param = vvar.kind == VarKind::Param && p.funcs[fi].params.contains(&v) && leaf(body);
        if !(vvar.kind == VarKind::Local || is_param) || vvar.owner != Some(fi) || vvar.by_ref || vvar.volatile || vvar.init.is_some() {
            continue;
        }
        if narrow {
            if vvar.bytes != q.bytes() || !leaf(&p.funcs[fi].body) {
                continue;
            }
        } else if vvar.bytes != rvar.bytes {
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
        if !is_param {
            p.vars[v].kind = VarKind::Result;
        }
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

/// Marks the `For` loops whose variable nothing reads after the loop (`St::For::free`). The test is on mentions, not
/// on paths: every mention of the variable in its routine is the loop variable of a `For` or lies in the body of one,
/// so each use is preceded by that loop's own store of the start value. The variable is a whole scalar that is not
/// `Volatile` or `ByRef`; a global must be named in one routine only and be invisible to interrupt handlers.
fn free_loop_ends(p: &mut Program) {
    fn is_for_over(st: &St, v: VarId, vars: &[Var]) -> bool {
        matches!(st, St::For { var, .. } if whole_var(var, vars) == Some(v))
    }
    // A mention of `v` that is not covered by a `For` over it.
    fn outside(body: &[S], v: VarId, vars: &[Var]) -> bool {
        body.iter().any(|s| {
            if let St::For { from, limit, body: b, .. } = &s.st
                && is_for_over(&s.st, v, vars)
            {
                // A loop over the same variable inside would change what this one sees.
                fn nested(b: &[S], v: VarId, vars: &[Var]) -> bool {
                    b.iter().any(|s| is_for_over(&s.st, v, vars) || matches!(&s.st, St::Count { .. } if crate::ir::mentions(std::slice::from_ref(s), v) && !sub_blocks_of(&s.st).iter().any(|x| crate::ir::mentions(x, v))) || sub_blocks_of(&s.st).into_iter().any(|x| nested(x, v, vars)))
                }
                return from.touches(v, true) || limit.touches(v, true) || nested(b, v, vars);
            }
            let mut head = s.clone();
            for b in blocks_mut(&mut head.st) {
                b.clear();
            }
            crate::ir::mentions(std::slice::from_ref(&head), v) || sub_blocks_of(&s.st).into_iter().any(|b| outside(b, v, vars))
        })
    }
    fn mark(body: &mut [S], ok: &HashSet<VarId>, vars: &[Var]) {
        for s in body {
            if let St::For { var, free, .. } = &mut s.st
                && let Some(v) = whole_var(var, vars)
            {
                *free = ok.contains(&v);
            }
            for b in blocks_mut(&mut s.st) {
                mark(b, ok, vars);
            }
        }
    }
    let vars = p.vars.clone();
    let seen = interrupt_vars(p);
    let n_bodies = p.funcs.len() + 1;
    let results: HashSet<VarId> = p.funcs.iter().filter_map(|f| f.result).collect();
    let named: Vec<Vec<bool>> = {
        let bodies: Vec<&[S]> = p.funcs.iter().map(|f| f.body.as_slice()).chain(std::iter::once(p.main.body.as_slice())).collect();
        (0..vars.len()).map(|v| bodies.iter().map(|b| crate::ir::mentions(b, v)).collect()).collect()
    };
    for bi in 0..n_bodies {
        let body: &[S] = if bi < p.funcs.len() { &p.funcs[bi].body } else { &p.main.body };
        let mut ok = HashSet::new();
        for (v, var) in vars.iter().enumerate() {
            // A routine's result is read by its callers (a parameter can be one, `coalesce_results`).
            if var.volatile || var.by_ref || !named[v][bi] || !matches!(var.kind, VarKind::Global | VarKind::Local | VarKind::Param) || results.contains(&v) {
                continue;
            }
            if var.kind == VarKind::Global && (named[v].iter().filter(|x| **x).count() != 1 || seen.as_ref().is_none_or(|s| s.contains(&v))) {
                continue;
            }
            if !outside(body, v, &vars) {
                ok.insert(v);
            }
        }
        let body: &mut Vec<S> = if bi < p.funcs.len() { &mut p.funcs[bi].body } else { &mut p.main.body };
        mark(body, &ok, &vars);
    }
}

/// Whether any expression of the program (in any routine, at any depth) satisfies `f`.
pub fn any_ex(p: &Program, f: &dyn Fn(&Ex) -> bool) -> bool {
    struct Any<'a>(&'a dyn Fn(&Ex) -> bool, bool);
    impl Visit for Any<'_> {
        fn ex(&mut self, e: &Ex) {
            if (self.0)(e) {
                self.1 = true;
            }
        }
    }
    let mut a = Any(f, false);
    for b in p.funcs.iter().map(|f| &f.body).chain(std::iter::once(&p.main.body)) {
        w_block(&mut a, b);
    }
    a.1
}

// ---- constant-result routines and call-site specialisation -------------------------------------

/// A call of a routine whose whole body stores constants into its `Result` (the last one is the value), with
/// arguments that have no effect, is that constant. A call statement of a routine with an empty body and
/// effect-free arguments is dropped. After `specialize_best` has given `PinOk(18)` its own copy, that copy is
/// `Result = True` and the test in the caller disappears.
fn const_result_calls(p: &mut Program) -> bool {
    let mut known: HashMap<FuncId, Option<(u32, u8)>> = HashMap::new();
    for (i, f) in p.funcs.iter().enumerate() {
        if f.reg || f.ext || f.no_inline || p.isrs.iter().any(|(h, _)| *h == i) || p.exports.iter().any(|e| e.func == i || e.thunk == i) || p.ext_funcs.contains(&i) {
            continue;
        }
        if f.body.is_empty() && f.result.is_none() {
            known.insert(i, None);
            continue;
        }
        let Some(r) = f.result else { continue };
        let mut last: Option<(u32, u8)> = None;
        let mut ok = !f.body.is_empty();
        for s in &f.body {
            match &s.st {
                St::Assign(pl, e) if matches!(pl.base, Base::Var(v) if v == r) && pl.off == 0 && pl.bit.is_none() && pl.idx.is_none() && pl.dbit.is_none() && pl.width() == e.w && e.as_const().is_some() && !p.vars[r].volatile => {
                    last = Some((e.as_const().unwrap(), e.w));
                }
                _ => {
                    ok = false;
                    break;
                }
            }
        }
        if ok && last.is_some() {
            known.insert(i, last);
        }
    }
    if known.is_empty() {
        return false;
    }
    let mut hit = false;
    for (_, body) in all_bodies(p) {
        m_block(body, &mut |e: &mut Ex| {
            if let ExK::Call(g, args) = &e.k
                && let Some(Some((k, w))) = known.get(g)
                && *w == e.w
                && args.iter().all(|(pl, a)| pure(a) && pl.idx.is_none())
            {
                *e = Ex::konst(*k, e.w, e.signed);
                hit = true;
            }
        });
        retain_stmts(body, &mut |s: &mut S| {
            if let St::Call(g, args) = &s.st
                && known.contains_key(g)
                && args.iter().all(|(pl, a)| pure(a) && pl.idx.is_none())
            {
                hit = true;
                return false;
            }
            true
        });
    }
    hit
}

/// Labels, `Save` blocks and raw assembly of a routine body: what makes copying it harder.
#[derive(Default)]
struct Shape {
    save: bool,
    labels: Vec<LabelId>,
}

impl Visit for Shape {
    fn stmt(&mut self, s: &S) {
        match &s.st {
            St::Save { .. } => self.save = true,
            St::Label(l) | St::Goto(l) | St::GoSub(l) => {
                if !self.labels.contains(l) {
                    self.labels.push(*l);
                }
            }
            _ => {}
        }
    }
}

/// Whether `target` can run again while `from` runs (a call cycle through `from`).
fn calls_reach(p: &Program, from: FuncId, target: FuncId) -> bool {
    let mut seen: HashSet<FuncId> = HashSet::new();
    let mut work = vec![from];
    while let Some(x) = work.pop() {
        if !seen.insert(x) {
            continue;
        }
        for g in scan(&p.funcs[x].body).sites.keys() {
            if *g == target {
                return true;
            }
            work.push(*g);
        }
    }
    false
}

/// Applies `g` to every place written in the statements of `b` (not those inside expressions) and every label.
fn stmt_places(b: &mut [S], g: &mut dyn FnMut(&mut Place), lab: &mut dyn FnMut(&mut LabelId)) {
    fn src(s: &mut StrSrc, g: &mut dyn FnMut(&mut Place)) {
        match s {
            StrSrc::Ram(p) => g(p),
            StrSrc::Lit(_) | StrSrc::Char(_) => {}
            StrSrc::Cat { tmp, parts } => {
                g(tmp);
                for q in parts {
                    src(q, g);
                }
            }
        }
    }
    for s in b {
        match &mut s.st {
            St::Assign(p, _) | St::Add(p, _) | St::SetBit(p, _) | St::ToggleBit(p) | St::Clear(p) | St::ClearMem(p, _) | St::Direction { place: p, .. } => g(p),
            St::Copy { dst, src, .. } => {
                g(dst);
                g(src);
            }
            St::StrSet { dst, parts, .. } => {
                g(dst);
                for q in parts {
                    src(q, g);
                }
            }
            St::Call(_, args) => {
                for (p, _) in args {
                    g(p);
                }
            }
            St::If(arms, other) => {
                for (_, blk) in arms {
                    stmt_places(blk, g, lab);
                }
                stmt_places(other, g, lab);
            }
            St::While(_, blk) | St::Repeat(blk, _) | St::Save { body: blk, .. } => stmt_places(blk, g, lab),
            St::For { var, body, .. } => {
                g(var);
                stmt_places(body, g, lab);
            }
            St::Count { counter, body, step, .. } => {
                g(counter);
                if let Some((p, _)) = step {
                    g(p);
                }
                stmt_places(body, g, lab);
            }
            St::Goto(l) | St::GoSub(l) | St::Label(l) => lab(l),
            _ => {}
        }
    }
}

/// Applies `g` to every call, in statements and in expressions.
fn each_call(b: &mut [S], g: &mut dyn FnMut(&mut FuncId, &mut Vec<(Place, Ex)>)) {
    fn blocks(b: &mut [S], g: &mut dyn FnMut(&mut FuncId, &mut Vec<(Place, Ex)>)) {
        for s in b {
            match &mut s.st {
                St::Call(f, args) => g(f, args),
                St::If(arms, other) => {
                    for (_, blk) in arms {
                        blocks(blk, g);
                    }
                    blocks(other, g);
                }
                St::While(_, blk) | St::Repeat(blk, _) | St::For { body: blk, .. } | St::Count { body: blk, .. } | St::Save { body: blk, .. } => blocks(blk, g),
                _ => {}
            }
        }
    }
    blocks(b, g);
    m_block(b, &mut |e: &mut Ex| {
        if let ExK::Call(f, args) = &mut e.k {
            g(f, args);
        }
    });
}

/// The constant arguments of one call: (index into `spec`, value) for each parameter of `spec` given a constant.
fn site_key(args: &[(Place, Ex)], spec: &[(VarId, u32)], mask: u32) -> Vec<(usize, u32)> {
    let mut key = Vec::new();
    for (i, (pv, bytes)) in spec.iter().enumerate() {
        if mask >> i & 1 == 0 {
            continue;
        }
        let arg = args.iter().find(|(pl, _)| matches!(pl.base, Base::Var(v) if v == *pv) && pl.off == 0 && pl.bit.is_none() && pl.idx.is_none());
        if let Some((_, e)) = arg
            && let Some(k) = e.as_const()
            && e.w as u32 == bytes * 8
        {
            key.push((i, k));
        }
    }
    key
}

/// What `specialize_func` needs to know about the whole program, worked out once per version of it.
struct SpecCtx {
    all: Facts,
    other: HashSet<FuncId>,
    /// Routines a `Save` copies the frame of (`saved_funcs`): not copied.
    saved: HashSet<FuncId>,
}

fn spec_ctx(p: &Program) -> SpecCtx {
    let mut all = Facts::default();
    for body in p.funcs.iter().map(|f| &f.body).chain(std::iter::once(&p.main.body)) {
        w_block(&mut all, body);
    }
    SpecCtx { all, other: reachable_otherwise(p), saved: saved_funcs(p) }
}

/// Gives every group of calls of `f` that pass the same constants their own copy of `f`, so that
/// `propagate_params` and the folding passes can use the constants. Only the parameters whose bit is set in `mask`
/// (by position among the read-only ByVal ones) are fixed. Returns whether any copy was made.
fn specialize_func(p: &mut Program, f: FuncId, mask: u32, tried: Option<&mut HashSet<Vec<Vec<usize>>>>, ctx: &SpecCtx, dry: bool) -> bool {
    const MAX_COPIES: usize = 6;
    let all = &ctx.all;
    let fa = scan(&p.funcs[f].body);
    let mut shape = Shape::default();
    w_block(&mut shape, &p.funcs[f].body);
    let func = &p.funcs[f];
    if func.reg || func.ext || func.no_inline || fa.asm || fa.save_func || ctx.saved.contains(&f) || shape.save || p.isrs.iter().any(|(i, _)| *i == f) || ctx.other.contains(&f) {
        return false;
    }
    // Parameters whose value a copy can fix: read-only ByVal scalars.
    let mut spec: Vec<(VarId, u32)> = Vec::new();
    for &pv in &func.params {
        let var = &p.vars[pv];
        if var.kind == VarKind::Param && !var.by_ref && var.bytes <= 4 && !all.addr.contains(&pv) && !fa.written.contains(&pv) && func.result != Some(pv) {
            spec.push((pv, var.bytes));
        }
    }
    spec.truncate(16);
    if spec.is_empty() {
        return false;
    }
    // A copy can only fold what reads the parameters it fixes.
    {
        let mut reads = Facts::default();
        w_block(&mut reads, &p.funcs[f].body);
        if !spec.iter().any(|(pv, _)| reads.read.contains(pv)) {
            return false;
        }
    }
    let Some(sites) = all.sites.get(&f) else { return false };
    let mut groups: Vec<(Vec<(usize, u32)>, Vec<usize>)> = Vec::new();
    for (si, site) in sites.iter().enumerate() {
        let key = site_key(site, &spec, mask);
        if key.is_empty() {
            continue;
        }
        match groups.iter_mut().find(|(k, _)| *k == key) {
            Some((_, v)) => v.push(si),
            None => groups.push((key, vec![si])),
        }
    }
    // One group that holds every call is `propagate_params`' business.
    if groups.is_empty() || (groups.len() == 1 && groups[0].1.len() == sites.len()) {
        return false;
    }
    groups.sort_by(|a, b| b.1.len().cmp(&a.1.len()).then(a.1[0].cmp(&b.1[0])));
    groups.truncate(MAX_COPIES);
    // The same split of the calls from another mask gives the same program.
    if let Some(t) = tried {
        let split: Vec<Vec<usize>> = groups.iter().map(|(_, v)| v.clone()).collect();
        if dry {
            if t.contains(&split) {
                return false;
            }
        } else if !t.insert(split) {
            return false;
        }
    }
    let count: Vec<(Vec<(usize, u32)>, usize)> = groups.into_iter().map(|(k, v)| (k, v.len())).collect();

    if dry {
        return !calls_reach(p, f, f);
    }
    if calls_reach(p, f, f) {
        return false;
    }
    // One copy per group.
    let first_copy = p.funcs.len();
    let mut copies: Vec<(Vec<(usize, u32)>, FuncId, HashMap<VarId, VarId>)> = Vec::new();
    for (key, _) in &count {
        let nf = p.funcs.len();
        let old = p.funcs[f].clone();
        let mut vmap: HashMap<VarId, VarId> = HashMap::new();
        for i in 0..p.vars.len() {
            if p.vars[i].owner == Some(f) {
                let mut v = p.vars[i].clone();
                v.asm = format!("{}_S{nf}", v.asm);
                v.owner = Some(nf);
                p.vars.push(v);
                vmap.insert(i, p.vars.len() - 1);
            }
        }
        let mut lmap: HashMap<LabelId, LabelId> = HashMap::new();
        for &l in &shape.labels {
            let name = format!("{}_S{nf}", p.label_names[l]);
            p.label_names.push(name);
            lmap.insert(l, p.label_names.len() - 1);
        }
        let mut body = old.body.clone();
        let fix = |pl: &mut Place| {
            if let Base::Var(v) | Base::Ptr(v) = &mut pl.base
                && let Some(n) = vmap.get(v)
            {
                *v = *n;
            }
        };
        stmt_places(&mut body, &mut |pl| fix(pl), &mut |l| {
            if let Some(n) = lmap.get(l) {
                *l = *n;
            }
        });
        fn src_fix(s: &mut StrSrc, fix: &dyn Fn(&mut Place)) {
            match s {
                StrSrc::Ram(p) => fix(p),
                StrSrc::Lit(_) => {}
                StrSrc::Char(_) => {}
                StrSrc::Cat { tmp, parts } => {
                    fix(tmp);
                    for q in parts {
                        src_fix(q, fix);
                    }
                }
            }
        }
        m_block(&mut body, &mut |e: &mut Ex| match &mut e.k {
            ExK::Load(pl) | ExK::Addr(pl) => fix(pl),
            ExK::Call(_, args) => {
                for (pl, _) in args {
                    fix(pl);
                }
            }
            ExK::StrEq(a, b) => {
                src_fix(a, &fix);
                src_fix(b, &fix);
            }
            _ => {}
        });
        // Places inside the index expressions of statement places were visited by m_block (as expressions);
        // the index of a place that is itself rewritten above needs nothing more.
        let mapped = |v: VarId| *vmap.get(&v).unwrap_or(&v);
        p.funcs.push(Func { asm: format!("{}_S{nf}", old.asm), name: format!("{}_S{nf}", old.name), params: old.params.iter().map(|&v| mapped(v)).collect(), result: old.result.map(mapped), body, span: old.span, reg: false, ext: false, no_inline: old.no_inline });
        // The copy must not name any object of the original's frame: a place the walkers above did not know about
        // would leave both routines sharing storage. Give the copy up (and every copy made so far) when one does.
        let mut seen = Facts::default();
        w_block(&mut seen, &p.funcs[nf].body);
        let stale = |v: &VarId| vmap.contains_key(v);
        if seen.read.iter().chain(&seen.written).chain(&seen.raw).chain(&seen.addr).chain(&seen.ptr_stmt).chain(&seen.ptr_written).any(stale) {
            p.funcs.truncate(first_copy);
            return false;
        }
        copies.push((key.clone(), nf, vmap));
    }

    // Send each group's calls to its copy; the arguments are re-pointed at the copy's parameters.
    let mut redirect = |g: &mut FuncId, args: &mut Vec<(Place, Ex)>| {
        if *g != f {
            return;
        }
        let key = site_key(args, &spec, mask);
        if key.is_empty() {
            return;
        }
        if let Some((_, nf, vmap)) = copies.iter().find(|(k, _, _)| *k == key) {
            *g = *nf;
            for (pl, _) in args.iter_mut() {
                if let Base::Var(v) = &mut pl.base
                    && let Some(n) = vmap.get(v)
                {
                    *v = *n;
                }
            }
        }
    };
    let nfuncs = p.funcs.len() - copies.len();
    for (i, fun) in p.funcs.iter_mut().enumerate() {
        if i < nfuncs {
            each_call(&mut fun.body, &mut redirect);
        }
    }
    each_call(&mut p.main.body, &mut redirect);
    true
}

/// Routines called at least twice, most calls first.
fn spec_candidates(p: &Program) -> Vec<FuncId> {
    let mut all = Facts::default();
    for body in p.funcs.iter().map(|f| &f.body).chain(std::iter::once(&p.main.body)) {
        w_block(&mut all, body);
    }
    // The most calls times the largest body first: that is where a copy that folds saves the most.
    let mut cands: Vec<(FuncId, usize)> = all
        .sites
        .iter()
        .filter(|(f, s)| s.len() >= 2 && **f < p.funcs.len())
        .map(|(f, s)| {
            let mut w = Facts::default();
            w_block(&mut w, &p.funcs[*f].body);
            (*f, s.len() * (p.funcs[*f].body.len() + w.read.len()))
        })
        .collect();
    cands.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    cands.into_iter().map(|(f, _)| f).collect()
}

/// Statements and expression nodes in every routine and the main program: a stand-in for how long a trial build takes.
fn ir_weight(p: &Program) -> usize {
    #[derive(Default)]
    struct W(usize);
    impl Visit for W {
        fn ex(&mut self, _: &Ex) {
            self.0 += 1;
        }
        fn stmt(&mut self, _: &S) {
            self.0 += 1;
        }
    }
    let mut w = W::default();
    for b in p.funcs.iter().map(|f| &f.body).chain(std::iter::once(&p.main.body)) {
        w_block(&mut w, b);
    }
    w.0
}

/// Programs heavier than this keep the shared routines (see `specialize_best`).
const SPEC_MAX_WEIGHT: usize = 4_000;

/// Trial builds `specialize_best` may make for a program of this IR weight: more for the small programs, whose builds
/// are quick, and always between 4 and 12, so the work is the same on every run.
fn spec_builds(weight: usize) -> u32 {
    (9_000 / weight.max(1)).clamp(4, 12) as u32
}

/// The size of every program in `qs`, in order, each built on a thread of its own: the trial builds are independent
/// and the slowest part of a compile.
fn sizes(qs: &[&Program], size: &Size) -> Vec<Option<u32>> {
    // No more threads than the machine has processors: in batches of that many.
    let cpus = std::thread::available_parallelism().map_or(1, |n| n.get());
    if qs.len() <= 1 || cpus == 1 {
        return qs.iter().map(|q| size(q)).collect();
    }
    if qs.len() > cpus {
        return qs.chunks(cpus).flat_map(|c| sizes(c, size)).collect();
    }
    std::thread::scope(|sc| {
        let handles: Vec<_> = qs
            .iter()
            .map(|&q| {
                // Code generation recurses on the expression trees: a stack as roomy as the main thread's, not the
                // small default of a spawned thread.
                std::thread::Builder::new().stack_size(64 << 20).spawn_scoped(sc, move || size(q))
            })
            .collect();
        handles
            .into_iter()
            .zip(qs)
            .map(|(h, q)| match h {
                Ok(h) => h.join().unwrap_or_else(|e| std::panic::resume_unwind(e)),
                // No thread to be had: built here.
                Err(_) => size(q),
            })
            .collect()
    })
}

/// The words of a built program, `None` when it does not build; called from several threads at once.
type Size<'a> = dyn Fn(&Program) -> Option<u32> + Sync + 'a;

/// One routine at a time: a copy is kept when the built program shrinks. Returns the smallest program reached.
/// `builds` counts the trial builds made, at most `max_builds`.
fn specialize_greedy(start: Program, start_w: u32, size: &Size, builds: &mut u32, max_builds: u32, debug: bool) -> (u32, Program) {
    let mut cur = start;
    let mut cur_w = start_w;
    for _round in 0..3 {
        let mut improved = false;
        let mut ctx = spec_ctx(&cur);
        for f in spec_candidates(&cur) {
            // All constant parameters fixed, then each of the first four alone: the smallest result wins.
            let mut masks: Vec<u32> = vec![u32::MAX];
            masks.extend((0..4).map(|i| 1u32 << i));
            let mut tried: HashSet<Vec<Vec<usize>>> = HashSet::new();
            // The candidates are made one after the other (each split of the calls is tried once), then built together.
            let mut qs: Vec<(u32, Program)> = Vec::new();
            for mask in masks {
                if *builds + qs.len() as u32 >= max_builds {
                    break;
                }
                // Worked out without touching the program; only a split of the calls not seen yet is built.
                if !specialize_func(&mut cur, f, mask, Some(&mut tried), &ctx, true) {
                    continue;
                }
                let mut q = cur.clone();
                if !specialize_func(&mut q, f, mask, Some(&mut tried), &ctx, false) {
                    continue;
                }
                optimize_core(&mut q);
                qs.push((mask, q));
            }
            *builds += qs.len() as u32;
            let szs = sizes(&qs.iter().map(|(_, q)| q).collect::<Vec<_>>(), size);
            let mut pick: Option<(u32, Program)> = None;
            for ((mask, q), sz) in qs.into_iter().zip(szs) {
                if debug {
                    eprintln!("spec {} mask {mask}: {sz:?} words (now {cur_w})", cur.funcs[f].asm);
                }
                if let Some(w) = sz
                    && w < pick.as_ref().map_or(cur_w, |(b, _)| *b)
                {
                    pick = Some((w, q));
                }
            }
            if let Some((w, q)) = pick {
                cur_w = w;
                cur = q;
                ctx = spec_ctx(&cur);
                improved = true;
            }
        }
        if !improved || *builds >= max_builds {
            break;
        }
    }
    (cur_w, cur)
}

/// Two ways to use `specialize_func`, the smaller built program wins (`size` is the words of the generated program,
/// `None` when it does not build). One goes routine by routine and keeps a copy when the program shrinks. The other
/// gives copies to every routine called with differing constants, callers first, until nothing is left to copy: a
/// copy of a caller often only pays once its callees have copies too, which the first way never sees.
fn specialize_best(p: &mut Program, size: &Size) {
    // Nothing to try, or a program too big to try on: no trial build is made at all.
    let weight = ir_weight(p);
    let debug = std::env::var("BASIL_SPEC_DEBUG").is_ok();
    if debug {
        eprintln!("spec: IR weight {weight}");
    }
    if weight > SPEC_MAX_WEIGHT
        || !{
            let ctx = spec_ctx(p);
            spec_candidates(p).into_iter().any(|f| specialize_func(p, f, u32::MAX, None, &ctx, true))
        }
    {
        return;
    }
    // Sizes are of the finished program: the settling passes run on a copy.
    let measure = |q: &Program| {
        let mut r = q.clone();
        optimize_post(&mut r);
        size(&r)
    };
    let size: &Size = &measure;

    // Everything at once (made here so that it is built together with the program as it is).
    let mut all = p.clone();
    let limit = all.funcs.len() * 3 + 50;
    for _ in 0..4 {
        let mut any = false;
        let mut ctx = spec_ctx(&all);
        for f in spec_candidates(&all) {
            if all.funcs.len() > limit {
                break;
            }
            if specialize_func(&mut all, f, u32::MAX, None, &ctx, false) {
                any = true;
                ctx = spec_ctx(&all);
            }
        }
        if !any {
            break;
        }
        optimize_core(&mut all);
    }
    // (When the program as it is does not build, the build of everything at once is thrown away.)
    let [base, all_w] = sizes(&[p, &all], size)[..] else { unreachable!() };
    let Some(base) = base else { return };
    let mut builds = 1u32;
    let max_builds = spec_builds(weight);
    let mut best = base;
    let mut winner: Option<Program> = None;

    // One at a time, from the program as it is.
    let (w, q) = specialize_greedy(p.clone(), base, size, &mut builds, max_builds, debug);
    if w < best {
        best = w;
        winner = Some(q);
    }

    // The build of everything at once counts after the first way's builds, as if made then.
    builds += 1;
    if let Some(aw) = all_w {
        if debug {
            eprintln!("spec all at once: {aw} words (best {best})");
        }
        // Whatever budget is left goes to one-at-a-time copies on top of it.
        let (w2, q2) = specialize_greedy(all, aw, size, &mut builds, max_builds, debug);
        if w2 < best {
            best = w2;
            winner = Some(q2);
        }
    }
    if debug {
        eprintln!("spec result: {best} words (was {base}), {builds} trial builds");
    }
    if let Some(w) = winner {
        *p = w;
    }
}

pub fn optimize(p: &mut Program) {
    optimize_core(p);
    optimize_post(p);
}

/// `optimize`, with calls that pass constants given copies of their routine where `size` (words of the generated
/// program, `None` when it does not build) says that is smaller (see `specialize_best`).
pub fn optimize_sized(p: &mut Program, size: &(dyn Fn(&Program) -> Option<u32> + Sync)) {
    optimize_core(p);
    specialize_best(p, size);
    optimize_post(p);
}

fn optimize_core(p: &mut Program) {
    for _ in 0..8 {
        fold_all(p);
        let mut changed = range_checks(p);
        changed |= propagate_params(p);
        changed |= specialize_literals(p);
        changed |= propagate_ref_params(p);
        fold_all(p);
        changed |= const_result_calls(p);
        changed |= propagate_locals(p);
        changed |= global_value_sets(p);
        changed |= global_values_after_init(p);
        changed |= drop_dead(p);
        if !changed {
            break;
        }
    }
}

/// The passes that settle storage and loops; nothing is propagated after them.
fn optimize_post(p: &mut Program) {
    share_counters(p);
    coalesce_results(p);
    if share_results(p) {
        drop_dead(p);
    }
    // Last: later passes would not know about a table walk.
    if flash_walk(p) {
        drop_dead(p);
    }
    free_loop_ends(p);
    pool_literals(p);
}

/// The RAM copies of string literals (`__STRLITn`, made for `ByRefConst` arguments, see `lower::lit_place`) each cost a
/// start-up copy of their own: TBLPTR and FSR0 set and a helper called, about 11 words a literal. When there are two
/// or more, they become one block (`__STRLITS`, each literal at its offset with its Null) filled by one table copy at
/// start-up. A literal nothing reads any more loses its copy. Each one's only write must be its start-up `StrSet` at the
/// top level of the main program.
fn pool_literals(p: &mut Program) {
    let lits: HashSet<VarId> = p.vars.iter().enumerate().filter(|(_, v)| v.kind == VarKind::Hidden && v.name == "(string literal)" && v.owner.is_none()).map(|(i, _)| i).collect();
    if lits.is_empty() {
        return;
    }
    // The start-up copy of each literal: (statement index in the main body, variable, text).
    let mut inits: Vec<(usize, VarId, Vec<u8>)> = Vec::new();
    for (i, s) in p.main.body.iter().enumerate() {
        if let St::StrSet { dst, parts, keep: false, .. } = &s.st
            && let Base::Var(v) = dst.base
            && lits.contains(&v)
            && dst.off == 0
            && dst.idx.is_none()
            && let [StrSrc::Lit(b)] = parts.as_slice()
            && b.len() as u32 + 1 == p.vars[v].bytes
        {
            inits.push((i, v, b.clone()));
        }
    }
    // Everything else the program does with the literals, without their start-up copies.
    let mut rest = Facts::default();
    for f in &p.funcs {
        w_block(&mut rest, &f.body);
    }
    for (i, s) in p.main.body.iter().enumerate() {
        if !inits.iter().any(|(k, _, _)| *k == i) {
            w_block(&mut rest, std::slice::from_ref(s));
        }
    }
    let mut seen: HashSet<VarId> = HashSet::new();
    inits.retain(|(_, v, _)| seen.insert(*v) && !rest.written.contains(v) && !rest.ptr_written.contains(v));
    // Copies of literals nothing reads go; the others are pooled when there are two or more.
    let (used, unused): (Vec<_>, Vec<_>) = inits.into_iter().partition(|(_, v, _)| rest.read.contains(v) || rest.addr.contains(v));
    let mut drop: HashSet<usize> = unused.iter().map(|(i, _, _)| *i).collect();
    if used.len() >= 2 {
        let mut data: Vec<u8> = Vec::new();
        let mut at: HashMap<VarId, u32> = HashMap::new();
        for (_, v, b) in &used {
            at.insert(*v, data.len() as u32);
            data.extend_from_slice(b);
            data.push(0);
        }
        let total = data.len() as u32;
        let ty = Ty::Array(Box::new(Ty::Int(8, false)), total);
        let pool = p.vars.len();
        p.vars.push(Var { asm: "__STRLITS".into(), name: "(string literals)".into(), ty: ty.clone(), bytes: total, kind: VarKind::Hidden, owner: None, init: None, by_ref: false, volatile: false });
        let f = p.flash.len();
        p.flash.push(FlashObj { asm: "__STRLITS_F".into(), bytes: data });
        let first = used[0].0;
        drop.extend(used.iter().map(|(i, _, _)| *i));
        drop.remove(&first);
        let span = p.main.body[first].span;
        // `Copy` moves 1 to 255 bytes: a longer block is copied in pieces of at most that.
        let mut copies: Vec<S> = Vec::new();
        let mut off = 0;
        while off < total {
            let n = (total - off).min(255);
            let piece = Ty::Array(Box::new(Ty::Int(8, false)), n);
            let place = |base: Base| Place { base, off, bit: None, idx: None, dbit: None, ty: piece.clone() };
            copies.push(S { st: St::Copy { dst: place(Base::Var(pool)), src: place(Base::Flash(f)), bytes: n }, span });
            off += n;
        }
        p.main.body.splice(first..=first, copies.iter().cloned());
        // The statements after `first` moved by the extra pieces.
        let extra = copies.len() - 1;
        drop = drop.into_iter().map(|i| if i > first { i + extra } else { i }).collect();
        let fix = |pl: &mut Place| {
            if let Base::Var(v) = pl.base
                && let Some(&o) = at.get(&v)
            {
                pl.base = Base::Var(pool);
                pl.off += o;
            }
        };
        fn src_fix(s: &mut StrSrc, fix: &dyn Fn(&mut Place)) {
            match s {
                StrSrc::Ram(p) => fix(p),
                StrSrc::Lit(_) | StrSrc::Char(_) => {}
                StrSrc::Cat { tmp, parts } => {
                    fix(tmp);
                    for q in parts {
                        src_fix(q, fix);
                    }
                }
            }
        }
        for (_, body) in all_bodies(p) {
            stmt_places(body, &mut |pl| fix(pl), &mut |_| {});
            m_block(body, &mut |e: &mut Ex| match &mut e.k {
                ExK::Load(pl) | ExK::Addr(pl) => fix(pl),
                ExK::Call(_, args) => {
                    for (pl, _) in args {
                        fix(pl);
                    }
                }
                ExK::StrEq(a, b) => {
                    src_fix(a, &fix);
                    src_fix(b, &fix);
                }
                _ => {}
            });
        }
    }
    if !drop.is_empty() {
        let mut i = 0;
        p.main.body.retain(|_| {
            i += 1;
            !drop.contains(&(i - 1))
        });
    }
}

#[cfg(test)]
mod local_storage_tests {
    use super::*;
    fn place(v: VarId) -> Place {
        Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: WORD }
    }
    fn stmt(st: St) -> S { S { st, span: Default::default() } }
    fn load(v: VarId) -> Ex { Ex::new(ExK::Load(place(v)), 16, false) }
    fn assign(v: VarId, e: Ex) -> S { stmt(St::Assign(place(v), e)) }
    fn fixture() -> Program {
        let func = Func { asm: "F".into(), name: "F".into(), params: vec![], result: Some(2),
            body: vec![assign(0, Ex::konst(7, 16, false)), assign(2, load(0)),
                assign(1, Ex::konst(9, 16, false)), assign(2, load(1))],
            span: Default::default(), reg: false, ext: false, no_inline: true };
        Program { structs: Default::default(), exports: vec![], ext_funcs: vec![], externs: vec![], cfiles: vec![],
            vars: (0..3).map(|i| Var { asm: format!("V{i}"), name: format!("v{i}"), ty: WORD, bytes: 2,
                kind: if i == 2 { VarKind::Result } else { VarKind::Local }, owner: Some(0), init: None,
                by_ref: false, volatile: false }).collect(),
            funcs: vec![func.clone()], flash: vec![], main: Func { body: vec![], ..func }, label_names: vec![],
            device: String::new(), clock_mhz: 64.0, config: vec![], edata: vec![], isrs: vec![], n_saves: 0,
            isr_shadow: true, fetch_nop: true, speed: false }
    }
    #[test]
    fn separate_phases_reuse_storage_and_drop_only_the_replaced_entry_clear() {
        let mut p = fixture();
        p.funcs[0].body.splice(0..0, [stmt(St::Clear(place(0))), stmt(St::Clear(place(1)))]);
        assert!(reuse_locals(&mut p));
        let f = scan(&p.funcs[0].body);
        assert!(!f.read.contains(&1) && !f.written.contains(&1));
        assert!(matches!(p.funcs[0].body[0].st, St::Clear(_)));
        assert_eq!(p.funcs[0].body.len(), 5);
    }
    #[test]
    fn absolute_reads_outside_the_routine_prevent_local_reuse() {
        let tgt = crate::codegen::Target { ram: vec![(0x100, 0x400)], access: (0, 0x60),
            access_sfr: (0xf60, 0x1000), sfr: Default::default(), hw_context: false, ipen: None,
            prog_bytes: 0, data_top: 0x1000, hw_stack: 31, opt: true, keep_vars: false,
            debug_files: vec![], pic16: None };
        for (addr, name) in [(0x20, "RAM"), (0xfef, "INDF0")] {
            let mut p = fixture();
            let mut pl = place(0);
            pl.base = Base::Abs { addr, name: name.into() };
            p.main.body.push(assign(2, Ex::new(ExK::Load(pl), 16, false)));
            assert!(compact_storage(&p, &tgt).is_none());
        }
    }
    #[test]
    fn reset_page_source_proof_covers_aliases_shadow_registers_and_wide_accesses() {
        let tgt = crate::codegen::Target { ram: vec![(0x20, 0x70)], access: (0x70, 0x80),
            access_sfr: (0, 0), sfr: [("PCLATH_SHAD".into(), 0x1fe7)].into_iter().collect(), hw_context: false, ipen: None,
            prog_bytes: 0, data_top: 0x2000, hw_stack: 16, opt: true, keep_vars: false,
            debug_files: vec![], pic16: Some(crate::codegen::Pic16Mem { gpr: vec![(0x20, 0x70)], common: (0x70, 0x80), prog_words: 16384 }) };
        assert!(preserves_page_zero(&fixture(), &tgt));
        for addr in [0, 1, 2, 10, 0x18a, 0x1fe7] {
            let mut p = fixture();
            let mut pl = place(0);
            pl.ty = crate::types::BYTE;
            pl.base = Base::Abs { addr, name: "ALIAS".into() };
            p.main.body.push(assign(2, Ex::new(ExK::Load(pl), 8, false)));
            assert!(!preserves_page_zero(&p, &tgt), "alias {addr:#x}");
        }
        let mut p = fixture();
        let mut wide = place(0); wide.base = Base::Abs { addr: 9, name: "WIDE".into() };
        p.main.body.push(assign(2, Ex::new(ExK::Load(wide), 16, false)));
        assert!(!preserves_page_zero(&p, &tgt));
        let mut p = fixture();
        let mut block = place(0); block.ty = crate::types::BYTE; block.base = Base::Abs { addr: 8, name: "RANGE".into() };
        p.main.body.push(stmt(St::ClearMem(block, 4)));
        assert!(!preserves_page_zero(&p, &tgt));
        let mut p = fixture();
        let mut ptr = place(0); ptr.base = Base::Ptr(0);
        p.main.body.push(assign(2, Ex::new(ExK::Load(ptr), 16, false)));
        assert!(!preserves_page_zero(&p, &tgt));
        let mut p = fixture();
        let mut port = place(0); port.ty = crate::types::BYTE; port.base = Base::Abs { addr: 12, name: "PORTA".into() };
        p.main.body.push(assign(2, Ex::new(ExK::Load(port), 8, false)));
        assert!(preserves_page_zero(&p, &tgt));
    }
    #[test]
    fn storage_reuse_across_known_calls_preserves_live_and_recursive_frames() {
        for case in 0..5 {
            let mut p = fixture();
            let mut callee = p.funcs[0].clone();
            callee.asm = "G".into(); callee.name = "G".into();
            callee.result = None; callee.body.clear();
            p.funcs.push(callee);
            // The first value stays live across this call; the second starts after it dies.
            p.funcs[0].body.insert(1, stmt(St::Call(1, vec![])));
            match case {
                1 => p.funcs[1].ext = true,
                2 => p.funcs[1].body.push(stmt(St::Call(0, vec![]))),
                3 => p.funcs[1].body.push(assign(2, load(0))),
                4 => p.funcs[0].body.push(assign(2, load(0))),
                _ => {}
            }
            assert_eq!(reuse_locals(&mut p), case == 0, "call case {case}");
        }
    }
    #[test]
    fn storage_reuse_preserves_overlaps_initial_values_and_escaped_storage() {
        for case in 0..9 {
            let mut p = fixture();
            match case {
                0 => p.funcs[0].body.push(assign(2, load(0))), // a is still live
                1 => p.funcs[0].body.insert(2, assign(2, load(1))), // b's initial zero is read
                2 => p.vars[1].volatile = true,
                3 => p.vars[1].init = Some(3),
                4 => p.funcs[0].body.insert(2, stmt(St::Label(0))),
                5 => { // Taking an address anywhere prevents sharing that local.
                    p.main.body.push(assign(2, Ex::new(ExK::Addr(place(1)), 16, false)));
                }
                6 => { // Both values belong to the same loop interval.
                    let body = std::mem::take(&mut p.funcs[0].body);
                    p.funcs[0].body.push(stmt(St::While(Ex::konst(1, 8, false), body)));
                }
                7 => {
                    if let St::Assign(pl, _) = &mut p.funcs[0].body[2].st { pl.ty = crate::types::BYTE; }
                }
                8 => p.funcs[0].body.push(stmt(St::Clear(place(1)))),
                _ => unreachable!(),
            }
            assert!(!reuse_locals(&mut p), "unsafe case {case}");
        }
    }
}
