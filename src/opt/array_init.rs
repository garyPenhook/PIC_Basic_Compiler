//! Definite byte initialization of private arrays. This analyzes a trial with its entry clear
//! removed; ordinary explicit clears remain writes. Failure to prove safety keeps the original.
use super::*;

pub(super) fn candidate(p: &Program, tgt: &crate::codegen::Target) -> Option<Program> {
    if !p.vars.iter().any(eligible) || p.c_link() || !p.cfiles.is_empty() || opaque_ram_with(p, tgt, false)
        || p.funcs.iter().any(|f| scan(&f.body).asm) || scan(&p.main.body).asm { return None; }
    let mut q = p.clone();
    let mut changed = false;
    for v in 0..p.vars.len() {
        let var = &p.vars[v];
        let Some(fi) = var.owner else { continue };
        if !eligible(var) { continue; }
        let own = scan(&q.funcs[fi].body);
        if own.addr.contains(&v) { continue; }
        let outside = |body: &[S]| { let f = scan(body); f.read.contains(&v) || f.written.contains(&v) || f.addr.contains(&v) };
        if outside(&q.main.body) || q.funcs.iter().enumerate().any(|(j, f)| j != fi && outside(&f.body)) { continue; }
        let body = &q.funcs[fi].body;
        let Some(first) = body.iter().position(|s| mentions(std::slice::from_ref(s), v)) else { continue };
        let mut end = first;
        let mut bytes = 0;
        while end < body.len() {
            match &body[end].st {
                St::ClearMem(pl, n) if matches!(pl.base, Base::Var(x) if x == v)
                    && pl.off == bytes && pl.idx.is_none() && pl.bit.is_none() && pl.dbit.is_none()
                    && *n > 0 && *n <= var.bytes - bytes => { bytes += n; end += 1; }
                _ => break,
            }
            if bytes == var.bytes { break; }
        }
        if bytes != var.bytes { continue; }
        let mut trial = body.clone();
        trial.drain(first..end);
        let mut proof = Proof { var: v, owner: fi, vars: &p.vars, set: vec![false; var.bytes as usize], escaped: own.addr, values: HashMap::new(), budget: 4096 };
        if !proof.block(&trial) {
            q.funcs[fi].body = trial;
            changed = true;
        }
    }
    changed.then_some(q)
}

fn eligible(var: &Var) -> bool {
    var.owner.is_some() && var.kind == VarKind::Local && !var.volatile && !var.by_ref && var.init.is_none()
        && var.bytes > 0 && var.bytes <= 2048
        && matches!(&var.ty, Ty::Array(elem, _) if matches!(**elem, Ty::Int(..) | Ty::Char))
}

struct Proof<'a> {
    var: VarId,
    owner: FuncId,
    vars: &'a [Var],
    set: Vec<bool>,
    escaped: HashSet<VarId>,
    /// Only local, nonvolatile loop counters whose values are known during this analysis.
    values: HashMap<VarId, u32>,
    budget: usize,
}

impl Proof<'_> {
    fn full(&self) -> bool { self.set.iter().all(|x| *x) }
    fn value(&self, e: &Ex) -> Option<u32> {
        let v = match &e.k {
            ExK::Const(v) => *v,
            ExK::Load(pl) if pl.off == 0 && pl.idx.is_none() && pl.bit.is_none() && pl.dbit.is_none() => *self.values.get(&base_var(pl)?)?,
            ExK::Conv(x) => {
                let v = self.value(x)?;
                if x.signed && x.w < 32 && v & (1 << (x.w - 1)) != 0 { v | !mask(x.w) } else { v }
            }
            ExK::Bin(k, a, b) => {
                let (a, b) = (self.value(a)?, self.value(b)?);
                match k {
                    BinKind::Add => a.wrapping_add(b), BinKind::Sub => a.wrapping_sub(b), BinKind::Mul => a.wrapping_mul(b),
                    BinKind::And => a & b, BinKind::Or => a | b, BinKind::Xor => a ^ b,
                    BinKind::Shl if b < 32 => a << b,
                    _ => return None,
                }
            }
            _ => return None,
        };
        Some(v & mask(e.w))
    }
    fn range(&self, pl: &Place, bytes: u32) -> Option<std::ops::Range<usize>> {
        if !matches!(pl.base, Base::Var(v) if v == self.var) || pl.bit.is_some() || pl.dbit.is_some() { return None; }
        let index = match &pl.idx { Some(e) => self.value(e)?, None => 0 };
        let start = pl.off.checked_add(index)? as usize;
        let end = start.checked_add(bytes as usize)?;
        (end <= self.set.len()).then_some(start..end)
    }
    fn read(&self, pl: &Place, bytes: u32) -> bool {
        pl.idx.as_ref().is_some_and(|e| self.expr(e)) || pl.dbit.as_ref().is_some_and(|e| self.expr(e))
            || (base_var(pl) == Some(self.var) && self.range(pl, bytes).is_none_or(|r| self.set[r].iter().any(|b| !b)))
    }
    fn expr(&self, e: &Ex) -> bool {
        struct Reads<'a, 'b> { proof: &'a Proof<'b>, bad: bool }
        impl Visit for Reads<'_, '_> {
            fn ex(&mut self, e: &Ex) {
                match &e.k {
                    ExK::Load(pl) => self.bad |= self.proof.read(pl, pl.bytes()),
                    ExK::Addr(pl) => self.bad |= base_var(pl) == Some(self.proof.var),
                    ExK::Call(..) => self.bad = true,
                    _ => {}
                }
            }
            fn place(&mut self, pl: &Place, _: Acc) { self.bad |= self.proof.read(pl, pl.bytes()); }
        }
        let mut r = Reads { proof: self, bad: false };
        w_ex(&mut r, e);
        r.bad
    }
    fn write(&mut self, pl: &Place, bytes: u32) -> bool {
        if pl.idx.as_ref().is_some_and(|e| self.expr(e)) || pl.dbit.as_ref().is_some_and(|e| self.expr(e)) { return true; }
        if base_var(pl).is_some_and(|v| self.values.contains_key(&v)) { return true; }
        if base_var(pl) == Some(self.var) {
            let Some(r) = self.range(pl, bytes) else { return true };
            self.set[r].fill(true);
        }
        false
    }
    /// True means a possible read of an unwritten byte, or an unsupported proof obligation.
    fn block(&mut self, body: &[S]) -> bool {
        for s in body {
            if self.full() { return false; }
            if self.budget == 0 { return true; }
            self.budget -= 1;
            let bad = match &s.st {
                St::Assign(pl, e) => self.expr(e) || self.write(pl, pl.bytes()),
                St::Clear(pl) => self.write(pl, pl.bytes()),
                St::ClearMem(pl, n) => self.write(pl, *n),
                St::Copy { dst, src, bytes } => self.read(src, *bytes) || self.write(dst, *bytes),
                St::Add(pl, _) | St::SetBit(pl, _) | St::ToggleBit(pl) | St::Direction { place: pl, .. } => self.read(pl, pl.bytes()) || self.write(pl, pl.bytes()),
                St::If(arms, other) => {
                    let before = self.set.clone();
                    let mut meet = before.clone();
                    meet.fill(true);
                    for (e, b) in arms {
                        self.set.clone_from(&before);
                        if self.expr(e) || self.block(b) { return true; }
                        for (m, s) in meet.iter_mut().zip(&self.set) { *m &= *s; }
                    }
                    self.set = before;
                    if self.block(other) { return true; }
                    for (s, m) in self.set.iter_mut().zip(meet) { *s &= m; }
                    false
                }
                St::For { var, from, limit, step, body, .. } => {
                    if self.expr(from) || self.expr(limit) { return true; }
                    let Some(v) = whole_var(var, self.vars) else { return true };
                    if self.vars[v].volatile || self.vars[v].kind != VarKind::Local || self.vars[v].owner != Some(self.owner)
                        || self.values.contains_key(&v) || self.escaped.contains(&v) || *step == 0 { return true; }
                    let (Some(a), Some(b)) = (self.value(from), self.value(limit)) else { return true };
                    let signed = |v: u32, e: &Ex| if e.signed { if e.w == 32 { v as i32 as i64 } else if v & (1 << (e.w - 1)) != 0 { v as i64 - (1i64 << e.w) } else { v as i64 } } else { v as i64 };
                    let (mut a, b) = (signed(a, from), signed(b, limit));
                    while if *step > 0 { a <= b } else { a >= b } {
                        self.values.insert(v, a as u32 & mask(var.width()));
                        if self.block(body) { self.values.remove(&v); return true; }
                        if self.full() { self.values.remove(&v); return false; }
                        if self.budget == 0 { self.values.remove(&v); return true; }
                        self.budget -= 1; // Empty loop bodies must also consume the budget.
                        let Some(next) = a.checked_add(*step) else { return true };
                        a = next;
                    }
                    self.values.remove(&v);
                    false
                }
                St::DelayUs(e) | St::DelayMs(e) => self.expr(e),
                St::FlashSeek(_, _, e) => e.as_ref().is_some_and(|e| self.expr(e)),
                St::Int { .. } => false,
                // Dynamic loops, exits, calls, address escape and Save need stronger flow proofs.
                _ => true,
            };
            if bad { return true; }
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::BYTE;
    fn vars() -> Vec<Var> {
        (0..4).map(|v| Var { asm: format!("V{v}"), name: format!("v{v}"), ty: if v == 0 { Ty::Array(Box::new(BYTE), 4) } else { BYTE },
            bytes: if v == 0 { 4 } else { 1 }, kind: VarKind::Local, owner: Some(0), init: None, by_ref: false, volatile: false }).collect()
    }
    fn place(v: VarId, off: u32) -> Place { Place { base: Base::Var(v), off, idx: None, bit: None, dbit: None, ty: BYTE } }
    fn s(st: St) -> S { S { st, span: Default::default() } }
    fn load(v: VarId) -> Ex { Ex::new(ExK::Load(place(v, 0)), 8, false) }
    fn store(off: u32) -> S { s(St::Assign(place(0, off), Ex::konst(7, 8, false))) }
    fn read(off: u32) -> S { s(St::Assign(place(3, 0), Ex::new(ExK::Load(place(0, off)), 8, false))) }
    fn fill() -> Vec<S> { (0..4).map(store).collect() }
    fn unsafe_read(vars: &[Var], body: &[S]) -> bool {
        Proof { var: 0, owner: 0, vars, set: vec![false; 4], escaped: HashSet::new(), values: HashMap::new(), budget: 4096 }.block(body)
    }
    fn for_loop(from: u32, limit: u32, step: i64, body: Vec<S>) -> S {
        s(St::For { var: place(1, 0), from: Ex::konst(from, 8, false), limit: Ex::konst(limit, 8, false), step, body, free: false })
    }
    fn indexed() -> S {
        let mut pl = place(0, 0);
        pl.idx = Some(Box::new(load(1)));
        s(St::Assign(pl, Ex::konst(7, 8, false)))
    }
    #[test]
    fn full_initialization_can_replace_a_clear_but_partial_reads_cannot() {
        let v = vars();
        assert!(!unsafe_read(&v, &fill()));
        for missing in 0..4 {
            let mut body: Vec<_> = (0..4).filter(|&i| i != missing).map(store).collect();
            body.push(read(missing));
            assert!(unsafe_read(&v, &body));
        }
        let mut body = vec![read(0)];
        body.extend(fill());
        assert!(unsafe_read(&v, &body));
        assert!(unsafe_read(&v, &[s(St::Add(place(0, 0), 1))]));
    }
    #[test]
    fn branches_require_initialized_bytes_on_every_path() {
        let v = vars();
        let mut good = vec![s(St::If(vec![(load(2), fill())], fill()))];
        good.push(read(0));
        assert!(!unsafe_read(&v, &good));
        let mut bad = vec![s(St::If(vec![(load(2), fill())], vec![]))];
        bad.push(read(0));
        assert!(unsafe_read(&v, &bad));
        assert!(unsafe_read(&v, &[s(St::If(vec![(Ex::new(ExK::Load(place(0, 0)), 8, false), fill())], fill()))]));
    }
    #[test]
    fn constant_loops_are_checked_per_iteration_in_both_directions() {
        let v = vars();
        assert!(!unsafe_read(&v, &[for_loop(0, 3, 1, vec![indexed()]), read(3)]));
        assert!(!unsafe_read(&v, &[for_loop(3, 0, -1, vec![indexed()]), read(0)]));
        assert!(unsafe_read(&v, &[for_loop(0, 2, 1, vec![indexed()]), read(3)]));
        assert!(unsafe_read(&v, &[for_loop(1, 0, 1, vec![indexed()]), read(0)]));
        assert!(unsafe_read(&v, &[for_loop(0, 3, 1, vec![s(St::Break), indexed()]), read(0)]));
        assert!(unsafe_read(&v, &[for_loop(0, 3, 1, vec![s(St::Add(place(1, 0), 1)), indexed()])]));
        let mut volatile = v.clone();
        volatile[1].volatile = true;
        assert!(unsafe_read(&volatile, &[for_loop(0, 3, 1, vec![indexed()])]));
        let mut escaped = Proof { var: 0, owner: 0, vars: &v, set: vec![false; 4], escaped: [1].into_iter().collect(), values: HashMap::new(), budget: 4096 };
        assert!(escaped.block(&[for_loop(0, 3, 1, vec![indexed()])]));
        let mut global = v.clone();
        global[1].kind = VarKind::Global;
        assert!(unsafe_read(&global, &[for_loop(0, 3, 1, vec![indexed()])]));
    }
    #[test]
    fn nested_indices_and_signed_conversions_do_not_hide_unwritten_bytes() {
        let v = vars();
        let op = |k, a, b| Ex::new(ExK::Bin(k, Box::new(a), Box::new(b)), 16, false);
        let mut pl = place(0, 0);
        pl.idx = Some(Box::new(op(BinKind::Add, op(BinKind::Mul, load(1), Ex::konst(2, 16, false)), load(2))));
        let inner = s(St::For { var: place(2, 0), from: Ex::konst(0, 8, false), limit: Ex::konst(1, 8, false), step: 1,
            body: vec![s(St::Assign(pl, Ex::konst(7, 8, false)))], free: false });
        assert!(!unsafe_read(&v, &[for_loop(0, 1, 1, vec![inner]), read(3)]));
        let mut negative = place(0, 0);
        negative.idx = Some(Box::new(Ex::new(ExK::Conv(Box::new(Ex::konst(255, 8, true))), 16, false)));
        assert!(unsafe_read(&v, &[s(St::Assign(negative, Ex::konst(7, 8, false)))]));
    }
    #[test]
    fn copies_clears_and_aliases_track_bytes() {
        let v = vars();
        assert!(!unsafe_read(&v, &[s(St::ClearMem(place(0, 0), 4)), read(0)]));
        assert!(!unsafe_read(&v, &[s(St::Copy { dst: place(0, 0), src: place(2, 0), bytes: 4 }), read(0)]));
        assert!(unsafe_read(&v, &[s(St::Copy { dst: place(0, 0), src: place(0, 0), bytes: 4 })]));
        assert!(unsafe_read(&v, &[s(St::Assign(place(2, 0), Ex::new(ExK::Addr(place(0, 0)), 16, false)))]));
        let mut low = place(0, 0); low.bit = Some(0);
        assert!(unsafe_read(&v, &[s(St::Assign(low, Ex::konst(1, 8, false)))]));
        let mut high = place(0, 0); high.off = 4;
        assert!(unsafe_read(&v, &[s(St::Assign(high, Ex::konst(1, 8, false)))]));
    }
    #[test]
    fn unsupported_control_flow_and_calls_keep_the_clear() {
        let v = vars();
        for st in [St::Call(0, vec![]), St::Asm(vec![]), St::Return, St::Goto(0), St::Save { id: 0, items: vec![], body: vec![] }] {
            assert!(unsafe_read(&v, &[s(st)]));
        }
        let mut proof = Proof { var: 0, owner: 0, vars: &v, set: vec![false; 4], escaped: HashSet::new(), values: HashMap::new(), budget: 3 };
        assert!(proof.block(&[for_loop(0, 255, 1, vec![])]));
    }
}
