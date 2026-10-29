//! Statements, routine calls, interrupt entry, start-up and delays.

use super::expr::{fit, fsr_addr};
use super::*;
use crate::asm::Cc;

impl<'p> G<'p> {
    pub fn block(&mut self, b: &[S]) {
        for s in b {
            self.stmt(s);
        }
    }

    fn stmt(&mut self, s: &S) {
        self.span = s.span;
        let mark = self.temp_cur;
        match &s.st {
            St::Assign(p, e) => self.store(p, e),
            St::Add(p, k) => self.add_const(p, *k),
            St::SetBit(p, on) => self.bit_op(p, if *on { 1 } else { 0 }),
            St::ToggleBit(p) => self.bit_op(p, 2),
            St::Clear(p) => self.clear_place(p),
            St::ClearMem(p, n) => self.clear_mem(p, *n),
            St::Copy { dst, src, bytes } => self.copy_mem(dst, src, *bytes),
            St::StrSet { dst, cap, parts, keep } => self.str_set(dst, *cap, parts, *keep),
            St::Direction { place, output } => self.direction(place, *output),
            St::Call(f, args) => self.call_func(*f, args, false),
            St::FlashSeek(i, n, idx) => {
                // FSR1 is the table pointer; `Base::FlashNext` loads read through it and advance it.
                let p = Place { base: Base::Flash(*i), off: *n, bit: None, idx: idx.clone().map(Box::new), dbit: None, ty: crate::types::BYTE };
                self.set_fsr(1, &p);
            }
            St::If(arms, other) => {
                let end = self.fresh();
                for (i, (c, body)) in arms.iter().enumerate() {
                    let next = self.fresh();
                    self.cond_jump(c, &next, false);
                    self.block(body);
                    if i + 1 < arms.len() || !other.is_empty() {
                        self.br(Cc::Always, &end);
                    }
                    self.label(&next);
                }
                self.block(other);
                self.label(&end);
            }
            St::While(c, body) => {
                let (top, end) = (self.fresh(), self.fresh());
                self.depth += 1;
                self.label(&top);
                self.cond_jump(c, &end, false);
                self.loops.push((top.clone(), end.clone()));
                self.block(body);
                self.loops.pop();
                self.br(Cc::Always, &top);
                self.depth -= 1;
                self.label(&end);
            }
            St::Repeat(body, c) => {
                let (top, cont, end) = (self.fresh(), self.fresh(), self.fresh());
                self.depth += 1;
                self.label(&top);
                self.loops.push((cont.clone(), end.clone()));
                self.block(body);
                self.loops.pop();
                self.label(&cont);
                self.cond_jump(c, &top, false);
                self.depth -= 1;
                self.label(&end);
            }
            St::For { var, from, limit, step, body } => self.for_loop(var, from, limit, *step, body),
            St::Count { counter, count, body, step } => {
                let (top, cont, end) = (self.fresh(), self.fresh(), self.fresh());
                self.store(counter, &Ex::konst(*count as u32, 8, false));
                self.depth += 1;
                self.label(&top);
                self.loops.push((cont.clone(), end.clone()));
                self.block(body);
                self.loops.pop();
                self.label(&cont);
                let m = self.place_mem(counter).expect("a loop counter is a plain variable");
                self.sel(&m);
                if let Some((var, k)) = step {
                    // Leave before stepping so the variable never goes past its last value.
                    let more = self.fresh();
                    self.items.push(Item::SkipBr(format!("decfsz {}, f", m.text()), more.clone()));
                    self.br(Cc::Always, &end);
                    self.label(&more);
                    self.add_const(var, *k);
                    self.br(Cc::Always, &top);
                } else {
                    self.items.push(Item::SkipBr(format!("decfsz {}, f", m.text()), top));
                }
                self.depth -= 1;
                self.label(&end);
            }
            St::Break => match self.loops.last().cloned() {
                Some((_, end)) => {
                    self.unwind_saves(self.loops.len());
                    self.br(Cc::Always, &end);
                }
                None => self.err("Break outside a loop"),
            },
            St::Continue => match self.loops.last().cloned() {
                Some((cont, _)) => {
                    self.unwind_saves(self.loops.len());
                    self.br(Cc::Always, &cont);
                }
                None => self.err("Continue outside a loop"),
            },
            St::Return => {
                self.unwind_saves(0);
                match self.isr_end.clone() {
                    Some(end) => self.br(Cc::Always, &end),
                    None => self.ins("return"),
                }
            }
            St::Goto(l) => {
                let name = self.p.label_names[*l].clone();
                self.br(Cc::Always, &name);
            }
            St::Label(l) => {
                let name = self.p.label_names[*l].clone();
                self.label(&name);
            }
            St::Asm(lines) => {
                for l in lines {
                    for tok in l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')) {
                        if let Some(i) = self.p.vars.iter().position(|v| v.asm == tok) {
                            self.uses[i] += weight(self.depth);
                        }
                        if let Some(f) = self.p.funcs.iter().position(|f| f.asm == tok) {
                            self.called.insert(f);
                            self.calls[self.cur].insert(f);
                        } else if let Some(r) = SCRATCH.iter().position(|s| tok.strip_prefix("__").and_then(|t| t.strip_prefix(*s)).is_some_and(|d| d.len() == 1 && (b'0'..=b'3').contains(&d.as_bytes()[0]))) {
                            self.scr(r, u32::from(tok.as_bytes()[3] - b'0'));
                        }
                    }
                    self.items.push(Item::Raw(l.clone()));
                }
                self.bsr = None;
            }
            St::DelayUs(e) => self.delay(e, false),
            St::DelayMs(e) => self.delay(e, true),
            St::Halt => self.br(Cc::Always, "__halt"),
            St::Int { level, on } => self.int_control(*level, *on),
            St::Save { id, items, body } => self.save_block(*id, items, body),
        }
        self.temp_cur = mark;
        self.items.push(Item::Fence);
    }

    // ---- stores ----------------------------------------------------------------------------

    pub fn store(&mut self, p: &Place, e: &Ex) {
        if p.dbit.is_some() {
            self.unsupported("a bit of an array element chosen at run time");
            return;
        }
        if p.is_bit() {
            self.store_bit(p, e);
            return;
        }
        let w = p.width();
        let n = (w / 8) as u32;
        let e = fit(e, w);
        if let Some(m) = self.place_mem(p) {
            if let ExK::Const(v) = e.k {
                let mut last: Option<u32> = None;
                for k in 0..n {
                    let b = (v >> (8 * k)) & 0xFF;
                    if b == 0 {
                        self.fo("clrf", &m.at(k));
                    } else {
                        if last != Some(b) {
                            self.ins(format!("movlw 0x{b:02X}"));
                            last = Some(b);
                        }
                        self.fo("movwf", &m.at(k));
                    }
                }
                return;
            }
            // `x = x op y` is done in place, byte by byte, without going through the accumulator.
            if let ExK::Bin(op @ (BinKind::Add | BinKind::Sub | BinKind::And | BinKind::Or | BinKind::Xor), l, r) = &e.k
                && matches!(&l.k, ExK::Load(lp) if lp == p)
                && l.w == w
                && !r.has_call()
                && !matches!(&r.k, ExK::Load(rp) if rp != p && rp.base == p.base)
            {
                self.in_place(p, &m, *op, &fit(r, w));
                return;
            }
            self.ev(&e);
            if n == 1 {
                self.fo("movwf", &m);
            } else {
                for k in 0..n {
                    let a = self.a(k);
                    self.fop("movf", &a, "w");
                    self.fo("movwf", &m.at(k));
                }
            }
            return;
        }
        // Through FSR0. A value that is cheap to compute afterwards is computed after the pointer is set;
        // anything else is evaluated first and parked in the temporary area.
        if self.simple(&e) {
            self.set_fsr(0, p);
            let o = self.operand(&e);
            for k in 0..n {
                let s = self.opd_byte(&o, k);
                self.ld_w(&s);
                self.ins(format!("movwi {k}[FSR0]"));
            }
            return;
        }
        let o = self.operand(&e);
        self.set_fsr(0, p);
        for k in 0..n {
            let s = self.opd_byte(&o, k);
            self.ld_w(&s);
            self.ins(format!("movwi {k}[FSR0]"));
        }
    }

    /// `place = place op r` on the variable's own bytes.
    fn in_place(&mut self, p: &Place, m: &Mem, op: BinKind, r: &Ex) {
        let n = p.bytes();
        // A constant added or subtracted is the same as an increment of the place.
        if let Some(k) = r.as_const() {
            match op {
                BinKind::Add => return self.add_const(p, k),
                BinKind::Sub => return self.add_const(p, k.wrapping_neg()),
                _ => {}
            }
        }
        let o = self.operand(r);
        for i in 0..n {
            let s = self.opd_byte(&o, i);
            match (op, &s) {
                (BinKind::And, Sb::K(0xFF)) | (BinKind::Or | BinKind::Xor, Sb::K(0)) => continue,
                (BinKind::And, Sb::K(0)) => {
                    self.fo("clrf", &m.at(i));
                    continue;
                }
                _ => {}
            }
            self.ld_w(&s);
            let name = match (op, i) {
                (BinKind::Add, 0) => "addwf",
                (BinKind::Add, _) => "addwfc",
                (BinKind::Sub, 0) => "subwf",
                (BinKind::Sub, _) => "subwfb",
                (BinKind::And, _) => "andwf",
                (BinKind::Or, _) => "iorwf",
                _ => "xorwf",
            };
            self.fop(name, &m.at(i), "f");
        }
    }

    /// Assignment to a single bit: any non-zero value sets it.
    fn store_bit(&mut self, p: &Place, e: &Ex) {
        let bit = p.bit.expect("bit place");
        if let Some(v) = e.as_const() {
            self.bit_op(p, if v & 1 != 0 { 1 } else { 0 });
            return;
        }
        let (set, end) = (self.fresh(), self.fresh());
        let e8 = fit(e, 8);
        // Evaluate first (it may use FSR0), then act on the bit.
        let o = self.operand(&e8);
        let s = self.opd_byte(&o, 0);
        self.ld_w(&s);
        self.ins("andlw 1");
        self.br(Cc::Nz, &set);
        self.bit_op(p, 0);
        self.br(Cc::Always, &end);
        self.label(&set);
        self.bit_op(p, 1);
        self.label(&end);
        let _ = bit;
    }

    /// 0 clears the bit, 1 sets it, 2 toggles it.
    fn bit_op(&mut self, p: &Place, op: u8) {
        let bit = p.bit.expect("bit place");
        if let Some(m) = self.place_mem(p) {
            match op {
                0 => self.fbit("bcf", &m, bit),
                1 => self.fbit("bsf", &m, bit),
                _ => {
                    self.ins(format!("movlw 0x{:02X}", 1u32 << bit));
                    self.fop("xorwf", &m, "f");
                }
            }
            return;
        }
        self.set_fsr(0, p);
        let mask = 1u32 << bit;
        match op {
            0 => {
                self.ins(format!("movlw 0x{:02X}", !mask & 0xFF));
                self.ins("andwf INDF0, f");
            }
            1 => {
                self.ins(format!("movlw 0x{mask:02X}"));
                self.ins("iorwf INDF0, f");
            }
            _ => {
                self.ins(format!("movlw 0x{mask:02X}"));
                self.ins("xorwf INDF0, f");
            }
        }
    }

    fn clear_place(&mut self, p: &Place) {
        if p.is_bit() {
            self.bit_op(p, 0);
            return;
        }
        let n = p.bytes();
        if let Some(m) = self.place_mem(p) {
            for k in 0..n {
                self.fo("clrf", &m.at(k));
            }
        } else {
            self.set_fsr(0, p);
            self.ins("clrw");
            for k in 0..n {
                self.ins(format!("movwi {k}[FSR0]"));
            }
        }
    }

    fn clear_mem(&mut self, p: &Place, n: u32) {
        if let Some(m) = self.place_mem(p) && n <= 4 && !self.crosses_bank(&m, n) {
            for k in 0..n {
                self.fo("clrf", &m.at(k));
            }
            return;
        }
        self.set_fsr(0, p);
        self.counted_loop(n, true, &["movwi FSR0++"]);
    }

    /// `n` passes of `body` (instructions that leave WREG alone unless they are the move itself), counted in D0
    /// (and D1 above 255). With `zero` WREG is cleared first and holds 0 for the whole loop.
    fn counted_loop(&mut self, n: u32, zero: bool, body: &[&str]) {
        let d0 = self.d(0);
        let l = self.fresh();
        if n <= 255 {
            self.ins(format!("movlw {n}"));
            self.fo("movwf", &d0);
        } else {
            // The low counter runs `n mod 256` passes the first time round and 256 after that.
            let d1 = self.d(1);
            self.ins(format!("movlw {}", n & 0xFF));
            self.fo("movwf", &d0);
            self.ins(format!("movlw {}", (n >> 8) + u32::from(n & 0xFF != 0)));
            self.fo("movwf", &d1);
        }
        if zero {
            self.ins("clrw");
        }
        self.label(&l);
        for b in body {
            self.ins(*b);
        }
        self.items.push(Item::SkipBr(format!("decfsz {}, f", d0.text()), l.clone()));
        if n > 255 {
            let d1 = self.d(1);
            self.items.push(Item::SkipBr(format!("decfsz {}, f", d1.text()), l));
        }
    }

    fn crosses_bank(&self, m: &Mem, n: u32) -> bool {
        match (m.addr(), m.at(n.saturating_sub(1)).addr()) {
            (Some(a), Some(b)) => a >> 7 != b >> 7,
            _ => false,
        }
    }

    fn copy_mem(&mut self, dst: &Place, src: &Place, bytes: u32) {
        if let (Some(d), Some(s)) = (self.place_mem(dst), self.place_mem(src)) && bytes <= 4 && !self.crosses_bank(&d, bytes) && !self.crosses_bank(&s, bytes) {
            self.copy_bytes(&d, &s, bytes);
            return;
        }
        if src.idx.as_ref().is_some_and(|i| i.uses_fsr()) {
            self.unsupported("a copy whose source index reads an array");
            return;
        }
        // Destination first: its index may be worked out with FSR0.
        self.set_fsr(1, dst);
        self.set_fsr(0, src);
        self.counted_loop(bytes, false, &["moviw FSR0++", "movwi FSR1++"]);
    }

    pub fn add_const(&mut self, p: &Place, k: u32) {
        let w = p.width();
        let n = (w / 8) as u32;
        let kk = k & crate::ir::mask(w);
        if kk == 0 && !p.is_bit() {
            return;
        }
        if !p.is_bit() && let Some(m) = self.place_mem(p) {
            self.sel(&m);
            if n == 1 {
                match kk {
                    1 => self.fop("incf", &m, "f"),
                    255 => self.fop("decf", &m, "f"),
                    _ => {
                        self.ins(format!("movlw 0x{kk:02X}"));
                        self.fop("addwf", &m, "f");
                    }
                }
            } else if kk == 1 && !self.crosses_bank(&m, n) {
                // The skip must jump over exactly one instruction, so no bank switch may sit between them.
                self.fop("incf", &m, "f");
                for i in 1..n {
                    self.ins("btfsc STATUS, 2");
                    self.fop("incf", &m.at(i), "f");
                }
            } else {
                for i in 0..n {
                    let b = (kk >> (8 * i)) & 0xFF;
                    if i > 0 && b == 0 {
                        self.ins("movlw 0");
                    } else {
                        self.ins(format!("movlw 0x{b:02X}"));
                    }
                    self.fop(if i == 0 { "addwf" } else { "addwfc" }, &m.at(i), "f");
                }
            }
            return;
        }
        let cur = Ex::new(ExK::Load(p.clone()), w, p.signed());
        let sum = Ex::new(ExK::Bin(BinKind::Add, Box::new(cur), Box::new(Ex::konst(kk, w, p.signed()))), w, p.signed());
        self.store(p, &sum);
    }

    fn for_loop(&mut self, var: &Place, from: &Ex, limit: &Ex, step: i64, body: &[S]) {
        let (w, sg) = (var.width(), var.signed());
        let load = |p: &Place| Ex::new(ExK::Load(p.clone()), w, sg);
        self.store(var, from);
        let (top, cont, end) = (self.fresh(), self.fresh(), self.fresh());
        let runs = match (from.as_const(), limit.as_const()) {
            (Some(f), Some(l)) => {
                let v = |x: u32| if sg { sign_ext(x, w) } else { x as i64 };
                if step > 0 { v(f) <= v(l) } else { v(f) >= v(l) }
            }
            _ => false,
        };
        self.depth += 1;
        if !runs {
            let kind = if step > 0 { CmpKind::Gt } else { CmpKind::Lt };
            self.cmp_jump(kind, &load(var), limit, &end, true);
        }
        self.label(&top);
        self.loops.push((cont.clone(), end.clone()));
        self.block(body);
        self.loops.pop();
        self.label(&cont);
        if step == 1 || step == -1 {
            self.cmp_jump(CmpKind::Eq, &load(var), limit, &end, true);
        } else {
            // Leave when fewer than |step| remain, so the counter never wraps past the limit.
            let (a, b) = if step > 0 { (limit.clone(), load(var)) } else { (load(var), limit.clone()) };
            let rem = Ex::new(ExK::Bin(BinKind::Sub, Box::new(Ex { signed: false, ..a }), Box::new(Ex { signed: false, ..b })), w, false);
            let k = Ex::konst(step.unsigned_abs() as u32, w, false);
            self.cmp_jump(CmpKind::Lt, &rem, &k, &end, true);
        }
        self.add_const(var, step as u32);
        self.br(Cc::Always, &top);
        self.depth -= 1;
        self.label(&end);
    }

    // ---- strings ------------------------------------------------------------------------------

    /// Points FSR1 at a string literal in program memory (stored once, Null-terminated).
    pub fn point_flash(&mut self, lit: &[u8]) {
        let n = match self.lits.iter().position(|l| l == lit) {
            Some(n) => n,
            None => {
                self.lits.push(lit.to_vec());
                self.lits.len() - 1
            }
        };
        self.ins(format!("movlw low __STR{n}"));
        self.ins("movwf FSR1L");
        self.ins(format!("movlw (high __STR{n}) | 0x80"));
        self.ins("movwf FSR1H");
    }

    pub fn call_helper(&mut self, name: &str) {
        self.helpers.insert(name.to_string());
        self.call(&format!("__{name}"));
    }

    /// `dst = parts[0] + parts[1] + ...` through the string helpers: FSR0 is the write pointer, `D2` the room
    /// left, and each part is appended and the text Null-terminated.
    fn str_set(&mut self, dst: &Place, cap: u32, parts: &[StrSrc], keep: bool) {
        let todo = &parts[keep as usize..];
        if keep && todo.is_empty() {
            return;
        }
        if cap > 255 {
            self.unsupported("a string longer than 255 characters");
            return;
        }
        // Char values other than constants are read first: computing one can use FSR0 and the scratch bytes, and a
        // plain variable (`s(0)` of the target itself) must not be read after earlier parts have been written over it.
        let mut saved: Vec<Option<Mem>> = Vec::new();
        for p in todo {
            match p {
                StrSrc::Char(e) if e.as_const().is_none() => {
                    let e8 = fit(e, 8);
                    self.ev(&e8);
                    let t = self.temp(1);
                    self.fo("movwf", &t);
                    saved.push(Some(t));
                }
                _ => saved.push(None),
            }
        }
        // A source addressed with a run-time index that itself reads through an FSR would undo the pointer set up before it.
        if todo.iter().any(|p| matches!(p, StrSrc::Ram(pl) if pl.idx.as_ref().is_some_and(|i| i.uses_fsr()))) {
            self.unsupported("a string element whose index reads an array");
            return;
        }
        self.set_fsr(0, dst);
        let d0 = self.d(2);
        self.ins(format!("movlw {cap}"));
        self.fo("movwf", &d0);
        if keep {
            self.call_helper("stre1");
        }
        let mut wrote = keep;
        for (p, t) in todo.iter().zip(&saved) {
            match p {
                StrSrc::Ram(pl) => {
                    self.set_fsr(1, pl);
                    self.call_helper("strs1");
                    wrote = true;
                }
                StrSrc::Lit(b) if b.is_empty() => {}
                StrSrc::Lit(b) => {
                    self.point_flash(b);
                    self.call_helper("strs1");
                    wrote = true;
                }
                StrSrc::Char(e) => {
                    match t {
                        Some(m) => self.fop("movf", m, "w"),
                        None => {
                            let k = e.as_const().expect("an unspilled Char is a constant");
                            self.ins(format!("movlw 0x{:02X}", k & 0xFF));
                        }
                    }
                    self.call_helper("strc1");
                    wrote = true;
                }
            }
        }
        if !wrote {
            self.ins("clrw");
            self.ins("movwi 0[FSR0]");
        }
    }

    // ---- calls --------------------------------------------------------------------------------

    /// True when a call from the routine being generated to `f` can come back to it.
    pub fn recursive_call(&self, f: FuncId) -> bool {
        self.cur < self.p.funcs.len() && (f == self.cur || self.reach[f].contains(&self.cur))
    }

    /// Every byte of the running routine's frame: its variables and its temporary area.
    fn frame_bytes(&mut self) -> Vec<Mem> {
        let mut out = Vec::new();
        for i in 0..self.p.vars.len() {
            let v = &self.p.vars[i];
            if v.owner != Some(self.cur) || v.bytes == 0 {
                continue;
            }
            let bytes = v.bytes;
            if self.layout.is_some_and(|l| l.size[i] == 0) {
                continue;
            }
            let m = self.var_mem(i, 0);
            out.extend((0..bytes).map(|k| m.at(k)));
        }
        let obj = self.nvars + 4 + self.cur;
        let tn = match self.layout {
            Some(l) => l.size[obj],
            None => self.temp_max[self.cur],
        };
        let sym = format!("{}__TMP", self.cur_asm);
        let tm = self.obj_mem(obj, sym, 0);
        out.extend((0..tn).map(|k| tm.at(k)));
        out
    }

    /// FSR0 = the software stack pointer.
    fn load_ssp(&mut self) -> (Mem, Mem) {
        let obj = self.nvars + 4 + self.p.funcs.len() + 1 + self.p.n_saves + self.p.isrs.len() + 1;
        let base = self.layout.and_then(|l| l.addr[obj]);
        let lo = Mem { sym: "__SSP".into(), base, off: 0, lin: false };
        let hi = lo.at(1);
        self.ins(format!("movf {}, w", lo.text()));
        self.ins("movwf FSR0L");
        self.ins(format!("movf {}, w", hi.text()));
        self.ins("movwf FSR0H");
        (lo, hi)
    }

    fn save_ssp(&mut self, lo: &Mem, hi: &Mem) {
        self.ins("movf FSR0L, w");
        self.ins(format!("movwf {}", lo.text()));
        self.ins("movf FSR0H, w");
        self.ins(format!("movwf {}", hi.text()));
    }

    /// Calls routine `f`. `want` is set when the value is wanted: after a recursive call it is left in A (the
    /// caller's frame is put back first, which uses WREG); otherwise the caller reads the result variable.
    pub fn call_func(&mut self, f: FuncId, args: &[(Place, Ex)], want: bool) {
        self.called.insert(f);
        self.calls[self.cur].insert(f);
        // A recursive call would run over this activation's variables, so they wait on the software stack for
        // the call and are put back after it.
        let rec = self.recursive_call(f);
        let frame = if rec { self.frame_bytes() } else { Vec::new() };
        if rec {
            self.soft_max = self.soft_max.max(frame.len() as u32);
            let (lo, hi) = self.load_ssp();
            for m in &frame {
                self.fop("movf", m, "w");
                self.ins("movwi FSR0++");
            }
            self.save_ssp(&lo, &hi);
        }
        if self.p.funcs[f].reg && !rec {
            match args {
                [(_, a)] => self.load_ab(a, None),
                [(_, a), (_, b)] => match b.sign_flipped() {
                    Some(x) => {
                        self.load_ab(a, Some(x));
                        self.ins("movlw 0x80");
                        let b3 = self.b(3);
                        self.fop("xorwf", &b3, "f");
                    }
                    None => self.load_ab(a, Some(b)),
                },
                _ => self.err("a register-call routine takes one or two operands"),
            }
            let asm = self.p.funcs[f].asm.clone();
            self.call(&asm);
            return;
        }
        // An argument that calls a routine is evaluated first, into the temporary area, so the parameters
        // being filled in cannot be overwritten by a nested call to the same routine. A recursive call stores
        // into the very parameters its arguments may read, so with several arguments they all go through
        // the temporary area.
        let park_all = rec && args.len() > 1;
        let mut parked: Vec<Option<Opd>> = Vec::new();
        for (p, e) in args {
            if e.has_call() || park_all {
                let e = fit(e, p.width());
                let n = (e.w / 8) as u32;
                self.ev(&e);
                let t = self.temp(n);
                self.spill(&t, n, e.w == 8);
                parked.push(Some(Opd::M(t)));
            } else {
                parked.push(None);
            }
        }
        for ((p, e), park) in args.iter().zip(parked) {
            match park {
                Some(o) => {
                    let n = p.bytes();
                    if let Some(m) = self.place_mem(p) {
                        for k in 0..n {
                            let s = self.opd_byte(&o, k);
                            self.ld_w(&s);
                            self.fo("movwf", &m.at(k));
                        }
                    } else {
                        self.set_fsr(0, p);
                        for k in 0..n {
                            let s = self.opd_byte(&o, k);
                            self.ld_w(&s);
                            self.ins(format!("movwi {k}[FSR0]"));
                        }
                    }
                }
                None => self.store(p, e),
            }
        }
        let asm = self.p.funcs[f].asm.clone();
        self.call(&asm);
        if rec {
            if want && let Some(rv) = self.p.funcs[f].result {
                let n = self.p.vars[rv].bytes;
                for k in 0..n {
                    let m = self.var_mem(rv, k);
                    self.fop("movf", &m, "w");
                    let a = self.a(k);
                    self.fo("movwf", &a);
                }
            }
            let (lo, hi) = self.load_ssp();
            for m in frame.iter().rev() {
                self.ins("moviw --FSR0");
                self.fo("movwf", m);
            }
            self.save_ssp(&lo, &hi);
            self.bsr = None;
        }
    }

    // ---- Save ... Restore -------------------------------------------------------------------------

    fn restore_copies(&mut self, pairs: &[(Mem, Mem)]) {
        for (slot, src) in pairs {
            self.fop("movf", slot, "w");
            self.fo("movwf", src);
        }
    }

    /// Emits the restore copies of the `Save` blocks opened inside `min_loops` loops or fewer (a jump out of them).
    fn unwind_saves(&mut self, min_loops: usize) {
        let lists: Vec<Vec<(Mem, Mem)>> = self.save_stack.iter().rev().filter(|(l, _)| *l >= min_loops).map(|(_, r)| r.clone()).collect();
        for r in lists {
            self.restore_copies(&r);
        }
    }

    /// Copies the working registers, variables and frames named by `items` to a private area, runs `body`, copies
    /// them back. In a handler the frames of everything the body calls are copied too (the interrupted code may
    /// be in the middle of using them).
    fn save_block(&mut self, id: usize, items: &[SaveIt], body: &[S]) {
        let mut bytes: Vec<Mem> = Vec::new();
        if self.layout.is_some() {
            let in_isr = self.isr_end.is_some();
            let mut callees = BTreeSet::new();
            stmt_calls(body, &mut callees);
            let prev = self.prev_calls.clone();
            let closure = move |roots: &BTreeSet<FuncId>| {
                let mut all: BTreeSet<FuncId> = BTreeSet::new();
                let mut stack: Vec<FuncId> = roots.iter().copied().collect();
                while let Some(f) = stack.pop() {
                    if all.insert(f) {
                        stack.extend(prev[f].iter().copied());
                    }
                }
                all
            };
            let mut roots: BTreeSet<FuncId> = if in_isr { callees.clone() } else { BTreeSet::new() };
            for it in items {
                if let SaveIt::Func(f) = it {
                    roots.insert(*f);
                }
            }
            if items.contains(&SaveIt::Regs) {
                for r in 0..4 {
                    for k in 0..self.isr_scratch[r] {
                        bytes.push(self.scr(r, k));
                    }
                }
                if !in_isr {
                    for n in ["FSR0L", "FSR0H", "FSR1L", "FSR1H"] {
                        bytes.extend(self.sfr(n));
                    }
                }
            }
            for it in items {
                if let SaveIt::Var(v) = it {
                    for k in 0..self.p.vars[*v].bytes {
                        bytes.push(self.var_mem(*v, k));
                    }
                }
            }
            for f in closure(&roots) {
                for i in 0..self.p.vars.len() {
                    if self.p.vars[i].owner == Some(f) {
                        for k in 0..self.p.vars[i].bytes {
                            bytes.push(self.var_mem(i, k));
                        }
                    }
                }
                let obj = self.nvars + 4 + f;
                let n = self.layout.map_or(0, |l| l.size[obj]);
                let sym = format!("{}__TMP", self.p.funcs[f].asm);
                for k in 0..n {
                    bytes.push(Mem { sym: sym.clone(), base: self.layout.and_then(|l| l.addr[obj]), off: k, lin: true });
                }
            }
            // The same byte reached twice (a variable inside a frame) is copied once.
            let mut seen = BTreeSet::new();
            bytes.retain(|m| m.addr().map_or(true, |a| seen.insert(a)));
        }
        let obj = self.nvars + 4 + self.p.funcs.len() + 1 + id;
        if self.layout.is_some() {
            self.save_max[id] = self.save_max[id].max(bytes.len() as u32);
        }
        let area = format!("__SAV{id}");
        let pairs: Vec<(Mem, Mem)> = bytes.iter().enumerate().map(|(i, m)| (Mem { sym: area.clone(), base: self.layout.and_then(|l| l.addr[obj]), off: i as u32, lin: true }, m.clone())).collect();
        for (slot, src) in &pairs {
            self.fop("movf", src, "w");
            self.fo("movwf", slot);
        }
        self.save_stack.push((self.loops.len(), pairs.clone()));
        self.block(body);
        self.save_stack.pop();
        self.restore_copies(&pairs);
        self.bsr = None;
    }

    // ---- ports, interrupts, delays ----------------------------------------------------------------

    fn direction(&mut self, p: &Place, output: bool) {
        let Base::Abs { name, .. } = &p.base else {
            self.err("Input/Output needs a port bit or a port");
            return;
        };
        let tris = name.strip_prefix("PORT").map(|r| format!("TRIS{r}"));
        let Some((t, ta)) = tris.and_then(|t| self.tgt.sfr.get(&t).map(|a| (t.clone(), *a))) else {
            self.err(format!("`{name}` has no direction register"));
            return;
        };
        let m = self.reg_mem(&t, ta, p.off);
        match p.bit {
            Some(b) => self.fbit(if output { "bcf" } else { "bsf" }, &m, b),
            None => {
                for i in 0..p.bytes() {
                    if output {
                        self.fo("clrf", &m.at(i));
                    } else {
                        self.ins("movlw 0xFF");
                        self.fo("movwf", &m.at(i));
                    }
                }
            }
        }
    }

    fn int_control(&mut self, level: Level, on: bool) {
        let Some(m) = self.sfr("INTCON") else {
            self.err("this device has no INTCON register");
            return;
        };
        self.items.push(Item::Keep(true));
        match (on, level) {
            (true, _) => {
                self.fbit("bsf", &m, 6);
                self.fbit("bsf", &m, 7);
            }
            (false, Level::Low) => self.fbit("bcf", &m, 6),
            (false, _) => {
                // An interrupt taken between the clear and the next instruction would set GIE again on `retfie`.
                let l = self.fresh();
                self.label(&l);
                self.fbit("bcf", &m, 7);
                self.items.push(Item::SkipBr("btfsc INTCON, 7".into(), l));
            }
        }
        self.items.push(Item::Keep(false));
    }

    fn fcy_per_us(&self) -> f64 {
        self.p.clock_mhz / 4.0
    }

    fn delay(&mut self, e: &Ex, ms: bool) {
        if self.p.clock_mhz <= 0.0 {
            self.err("DelayMS/DelayUS need a `Clock = <MHz>` line");
            return;
        }
        let unit = if ms { self.fcy_per_us() * 1000.0 } else { self.fcy_per_us() };
        if let Some(n) = e.as_const() {
            let cycles = (n as f64 * unit).round() as u64;
            self.items.push(Item::Keep(true));
            self.emit_cycles(cycles, 0);
            self.items.push(Item::Keep(false));
            return;
        }
        if e.w > 16 {
            self.err("a variable delay takes a Byte or Word");
            return;
        }
        if (unit - unit.round()).abs() > 1e-9 {
            self.err(format!("at Clock = {} MHz one {} is {unit} cycles; a variable delay needs a whole number (use a constant)", self.p.clock_mhz, if ms { "millisecond" } else { "microsecond" }));
            return;
        }
        let per = unit.round() as i64;
        // The loop adds seven cycles of its own per pass (the branch back is a flag test and a `bra`).
        let body = per - 7;
        if body < 0 {
            self.err("a variable DelayUS needs a Clock of at least 28 MHz; use a constant");
            return;
        }
        let e16 = fit(&Ex { signed: false, ..e.clone() }, 16);
        self.ev(&e16);
        self.items.push(Item::Keep(true));
        let (a0, a1) = (self.a(0), self.a(1));
        let (d0, d1) = (self.d(0), self.d(1));
        let skip = self.fresh();
        self.fop("movf", &a0, "w");
        self.fop("iorwf", &a1, "w");
        self.br(Cc::Z, &skip);
        // counter = value - 1
        self.ins("movlw 1");
        self.fop("subwf", &a0, "f");
        self.ins("movlw 0");
        self.fop("subwfb", &a1, "f");
        self.copy_bytes(&d0, &a0, 1);
        self.copy_bytes(&d1, &a1, 1);
        let lp = self.fresh();
        self.label(&lp);
        self.emit_cycles(body as u64, 2);
        self.ins("movlw 1");
        self.fop("subwf", &d0, "f");
        self.ins("movlw 0");
        self.fop("subwfb", &d1, "f");
        self.br(Cc::C, &lp);
        self.label(&skip);
        self.items.push(Item::Keep(false));
    }

    /// Code that takes exactly `n` cycles, using counters from `D<first>` up.
    fn emit_cycles(&mut self, n: u64, first: u32) {
        if n == 0 {
            return;
        }
        if n <= 12 {
            for _ in 0..n / 2 {
                let l = self.fresh();
                self.ins(format!("bra {l}"));
                self.items.push(Item::Label(l));
            }
            if n % 2 == 1 {
                self.ins("nop");
            }
            return;
        }
        if n <= 769 {
            // One counter loop costs 3c + 1 cycles for c in 1..=256.
            let c = ((n - 1) / 3).clamp(1, 256);
            let used = 3 * c + 1;
            let ctr = self.d(first);
            self.ins(format!("movlw {}", c & 0xFF));
            self.fo("movwf", &ctr);
            let l = self.fresh();
            self.items.push(Item::Label(l.clone()));
            self.items.push(Item::Ins(format!("decfsz {}, f", ctr.text())));
            self.items.push(Item::Ins(format!("bra {l}")));
            self.emit_cycles(n - used, first);
            return;
        }
        // M passes of an exact inner block of P cycles cost M * (P + 3) + 1.
        let m = 256u64;
        let p = ((n - 1) / m).saturating_sub(3);
        let used = m * (p + 3) + 1;
        let ctr = self.d(first);
        self.ins("movlw 0");
        self.fo("movwf", &ctr);
        let l = self.fresh();
        self.items.push(Item::Label(l.clone()));
        self.emit_cycles(p, first + 1);
        self.items.push(Item::Ins(format!("decfsz {}, f", ctr.text())));
        self.items.push(Item::Ins(format!("bra {l}")));
        self.emit_cycles(n - used, first);
    }

    // ---- start-up and interrupt entry -------------------------------------------------------------

    pub fn startup(&mut self) {
        let Some(layout) = self.layout else { return };
        // The software stack pointer of recursive calls.
        let sw = self.nvars + 4 + self.p.funcs.len() + 1 + self.p.n_saves + self.p.isrs.len();
        if layout.size[sw] > 0 {
            let a = fsr_addr(layout.addr[sw].unwrap_or(0));
            let lo = Mem { sym: "__SSP".into(), base: layout.addr[sw + 1], off: 0, lin: false };
            self.ins(format!("movlw 0x{:02X}", a & 0xFF));
            self.ins(format!("movwf {}", lo.text()));
            self.ins(format!("movlw 0x{:02X}", (a >> 8) & 0xFF));
            self.ins(format!("movwf {}", lo.at(1).text()));
        }
        // Zero ranges in the address space an FSR sees: all allocated program-wide variables, merged.
        let mut ranges: Vec<(u32, u32)> = Vec::new();
        for (i, v) in self.p.vars.iter().enumerate() {
            // A routine's own variables share overlaid storage and are cleared on entry instead.
            if v.owner.is_none() && let Some(a) = layout.addr[i] {
                if v.bytes > 0 {
                    ranges.push((fsr_addr(a), v.bytes));
                }
            }
        }
        ranges.sort();
        let mut merged: Vec<(u32, u32)> = Vec::new();
        for (a, n) in ranges {
            match merged.last_mut() {
                Some(l) if l.0 + l.1 == a => l.1 += n,
                _ => merged.push((a, n)),
            }
        }
        // Variables about to be given a value need no clearing.
        let inits: Vec<(usize, u32)> = self.p.vars.iter().enumerate().filter(|(i, v)| v.init.is_some() && layout.addr[*i].is_some() && v.kind == VarKind::Global).map(|(i, v)| (i, v.init.unwrap())).collect();
        let mut covered: BTreeSet<u32> = BTreeSet::new();
        for (i, _) in &inits {
            let a = fsr_addr(layout.addr[*i].unwrap());
            for b in 0..self.p.vars[*i].bytes {
                covered.insert(a + b);
            }
        }
        for (s, n) in merged {
            let mut run: Option<u32> = None;
            let mut spans: Vec<(u32, u32)> = Vec::new();
            for a in s..=s + n {
                let need = a < s + n && !covered.contains(&a);
                match (need, run) {
                    (true, None) => run = Some(a),
                    (false, Some(r)) => {
                        spans.push((r, a - r));
                        run = None;
                    }
                    _ => {}
                }
            }
            for (a, len) in spans {
                self.zero_range(a, len);
            }
        }
        for (i, v) in inits {
            let n = self.p.vars[i].bytes;
            let m = self.var_mem(i, 0);
            for k in 0..n {
                let b = (v >> (8 * k)) & 0xFF;
                if b == 0 {
                    self.fo("clrf", &m.at(k));
                } else {
                    self.ins(format!("movlw 0x{b:02X}"));
                    self.fo("movwf", &m.at(k));
                }
            }
        }
    }

    /// Clears `len` bytes at FSR address `addr`.
    fn zero_range(&mut self, addr: u32, len: u32) {
        if len <= 4 {
            for i in 0..len {
                let a = addr + i;
                // Back to a data address: the linear space is bank * 80 + offset - 20h.
                let phys = if a >= 0x2000 { super::layout::phys(a - 0x2000) } else { a };
                let m = Mem { sym: format!("0x{phys:03X}"), base: Some(phys), off: 0, lin: false };
                self.fo("clrf", &m);
            }
            return;
        }
        let mut a = addr;
        let mut left = len;
        let d0 = self.d(0);
        while left > 0 {
            let chunk = left.min(255);
            self.ins(format!("movlw 0x{:02X}", a & 0xFF));
            self.ins("movwf FSR0L");
            self.ins(format!("movlw 0x{:02X}", (a >> 8) & 0xFF));
            self.ins("movwf FSR0H");
            self.ins(format!("movlw {chunk}"));
            self.fo("movwf", &d0);
            self.ins("clrw");
            let l = self.fresh();
            self.items.push(Item::Label(l.clone()));
            self.ins("movwi FSR0++");
            self.items.push(Item::SkipBr(format!("decfsz {}, f", d0.text()), l));
            a += chunk;
            left -= chunk;
        }
    }

    /// The interrupt handler: the hardware saved WREG, STATUS, BSR, the FSRs and PCLATH; the compiler's scratch
    /// registers (common RAM, shared with the interrupted code) are saved here when the handler or anything it
    /// calls uses them.
    pub fn gen_isr(&mut self, j: usize) {
        let p = self.p;
        let (f, _level) = p.isrs[j];
        let func = &p.funcs[f];
        self.cur = f;
        self.cur_asm = func.asm.clone();
        self.temp_cur = 0;
        self.depth = 0;
        self.bsr = None;
        let start = self.items.len();
        self.items.push(Item::Comment(format!("Interrupt {}", func.name)));
        self.label("__ISR_H");
        self.label(&func.asm);
        let body_at = self.items.len();
        let end = format!("__isr_end{j}");
        self.isr_end = Some(end.clone());
        self.block(&func.body);
        self.isr_end = None;
        self.label(&end);
        // Which scratch bytes does the handler touch? Any call or raw assembly may reach every register.
        let any = self.items[body_at..].iter().any(|it| matches!(it, Item::Call(_) | Item::Raw(_)));
        let mut regs: Vec<(usize, u32)> = Vec::new();
        for r in 0..4 {
            for k in 0..self.isr_scratch[r] {
                let name = format!("__{}{}", SCRATCH[r], k);
                let used = any || self.items[body_at..].iter().any(|it| matches!(it, Item::Ins(t) | Item::Raw(t) if t.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).any(|tok| tok == name)));
                if used {
                    regs.push((r, k));
                }
            }
        }
        if self.layout.is_some() {
            let k = p.n_saves + j;
            self.save_max[k] = self.save_max[k].max(regs.len() as u32);
        }
        let obj = self.nvars + 4 + p.funcs.len() + 1 + p.n_saves + j;
        let area = format!("__ISV{j}");
        let saved_items = std::mem::take(&mut self.items);
        let mut texts = Vec::new();
        for pass in 0..2 {
            self.bsr = None;
            for (i, &(r, k)) in regs.iter().enumerate() {
                let src = self.scr(r, k);
                let slot = Mem { sym: area.clone(), base: self.layout.and_then(|l| l.addr[obj]), off: i as u32, lin: true };
                self.fop("movf", if pass == 0 { &src } else { &slot }, "w");
                self.fo("movwf", if pass == 0 { &slot } else { &src });
            }
            texts.push(std::mem::take(&mut self.items));
        }
        self.items = saved_items;
        let epi = texts.pop().expect("epilogue");
        let pro = texts.pop().expect("prologue");
        self.items.splice(body_at..body_at, pro);
        self.items.extend(epi);
        self.ins("retfie");
        self.ranges.push((f, start, self.items.len()));
    }
}

pub(crate) fn sign_ext(v: u32, w: u8) -> i64 {
    if w >= 32 {
        v as i32 as i64
    } else if v & (1 << (w - 1)) != 0 {
        (v | !crate::ir::mask(w)) as i32 as i64
    } else {
        v as i64
    }
}

/// The routines a statement list calls directly.
pub(crate) fn stmt_calls(ss: &[S], out: &mut BTreeSet<FuncId>) {
    fn ex(e: &Ex, out: &mut BTreeSet<FuncId>) {
        match &e.k {
            ExK::Call(f, args) => {
                out.insert(*f);
                for (p, a) in args {
                    place(p, out);
                    ex(a, out);
                }
            }
            ExK::Load(p) | ExK::Addr(p) => place(p, out),
            ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) => ex(x, out),
            ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => {
                ex(a, out);
                ex(b, out);
            }
            ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) | ExK::StrEq(..) => {}
        }
    }
    fn place(p: &Place, out: &mut BTreeSet<FuncId>) {
        if let Some(i) = &p.idx {
            ex(i, out);
        }
    }
    for s in ss {
        match &s.st {
            St::Assign(p, e) => {
                place(p, out);
                ex(e, out);
            }
            St::Call(f, args) => {
                out.insert(*f);
                for (p, a) in args {
                    place(p, out);
                    ex(a, out);
                }
            }
            St::If(arms, other) => {
                for (c, b) in arms {
                    ex(c, out);
                    stmt_calls(b, out);
                }
                stmt_calls(other, out);
            }
            St::While(c, b) | St::Repeat(b, c) => {
                ex(c, out);
                stmt_calls(b, out);
            }
            St::For { from, limit, body, .. } => {
                ex(from, out);
                ex(limit, out);
                stmt_calls(body, out);
            }
            St::Count { body, .. } | St::Save { body, .. } => stmt_calls(body, out),
            St::DelayUs(e) | St::DelayMs(e) => ex(e, out),
            _ => {}
        }
    }
}

