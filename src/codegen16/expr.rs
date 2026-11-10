//! Expressions: values in WREG (8 bits) or the accumulator A (wider), conditions as branches.

use super::layout::{lin, phys_off};
use super::*;
use crate::asm::Cc;

/// The expression converted to `w` bits (its own signedness decides how it is extended).
/// A byte expression whose high nibble is known to be clear: `x And m` with `m` below 16.
pub(crate) fn hi_nibble_clear(e: &Ex) -> bool {
    match &e.k {
        ExK::Bin(BinKind::And, x, y) => [x, y].iter().any(|v| v.as_const().is_some_and(|m| m & 0xF0 == 0)),
        _ => false,
    }
}

pub(crate) fn fit(e: &Ex, w: u8) -> Ex {
    if e.w == w {
        e.clone()
    } else if let ExK::Const(v) = e.k {
        // A constant is converted now.
        let v = if e.signed && w > e.w { super::stmt::sign_ext(v, e.w) as u32 } else { v };
        Ex::konst(v, w, e.signed)
    } else {
        Ex::new(ExK::Conv(Box::new(e.clone())), w, e.signed)
    }
}

/// Address an FSR holds for a data byte: linear data memory for banked RAM, the plain address otherwise.
pub(crate) fn fsr_addr(addr: u32) -> u32 {
    match lin(addr) {
        Some(l) => 0x2000 + l,
        None => addr,
    }
}

/// The index of a place as a byte, when the whole index is one: an 8-bit expression, or one widened from 8 bits.
fn byte_index(e: &Ex) -> Option<&Ex> {
    match &e.k {
        ExK::Conv(x) if !x.signed && x.w == 8 => Some(x),
        _ if e.w == 8 => Some(e),
        _ => None,
    }
}

impl<'p> G<'p> {
    // ---- places ---------------------------------------------------------------------------

    /// Direct memory for a place without an index (a variable or a fixed register), or None.
    pub fn place_mem(&mut self, p: &Place) -> Option<Mem> {
        if p.idx.is_some() {
            return None;
        }
        match &p.base {
            Base::Var(v) => Some(self.var_mem(*v, p.off)),
            // The pack defines a symbol for each single register but not for the 16-bit pairs (ADACQ, TMR1 ...): a
            // place wider than a byte is written with its address.
            Base::Abs { addr, .. } if p.width() > 8 => Some(Mem { sym: format!("0x{:03X}", addr + p.off), base: Some(addr + p.off), off: 0, lin: false }),
            Base::Abs { addr, name } => Some(self.reg_mem(name, *addr, p.off)),
            _ => None,
        }
    }

    /// A variable reached through an FSR by its numeric address never appears by name again: the comment keeps the
    /// peephole from treating its stores as dead.
    fn note_address_taken(&mut self, sym: &str) {
        self.items.push(Item::Comment(format!("address of {sym}")));
    }

    /// Constant data address (as an FSR sees it) of a place with no run-time part.
    pub(crate) fn const_fsr_addr(&mut self, p: &Place) -> Option<u32> {
        match (&p.base, &p.idx) {
            (Base::Var(v), None) => {
                let m = self.var_mem(*v, p.off);
                self.note_address_taken(&m.sym);
                Some(m.addr().map_or(0, fsr_addr))
            }
            (Base::Abs { addr, .. }, None) => Some(phys_off(*addr, p.off)),
            _ => None,
        }
    }

    /// Evaluates `e` as an unsigned 16-bit value into A0:A1.
    pub fn ev_a16(&mut self, e: &Ex) {
        let e16 = fit(&Ex { signed: false, ..e.clone() }, 16);
        self.ev(&e16);
    }

    /// Points FSR`n` at the first byte of an indirect place. Uses A when the place has a run-time index.
    pub fn set_fsr(&mut self, n: u32, p: &Place) {
        let (l, h) = (format!("FSR{n}L"), format!("FSR{n}H"));
        let lo = |me: &mut Self, v: u32| {
            if v == 0 {
                me.ins(format!("clrf {l}"));
            } else {
                me.ins(format!("movlw 0x{v:02X}"));
                me.ins(format!("movwf {l}"));
            }
        };
        let hi = |me: &mut Self, v: u32| {
            if v == 0 {
                me.ins(format!("clrf {h}"));
            } else {
                me.ins(format!("movlw 0x{v:02X}"));
                me.ins(format!("movwf {h}"));
            }
        };
        if let Some(a) = self.const_fsr_addr(p) {
            lo(self, a & 0xFF);
            hi(self, (a >> 8) & 0xFF);
            return;
        }
        // A symbol the assembler resolves: a constant table (its high byte carries bit 7 for program memory).
        let flash = match &p.base {
            Base::Flash(i) | Base::FlashNext(i) => {
                self.flash_used.insert(*i);
                Some(self.p.flash[*i].asm.clone())
            }
            _ => None,
        };
        let ptr = if let Base::Ptr(v) = &p.base { Some(*v) } else { None };
        let sym_off = |s: &str, off: u32| if off == 0 { s.to_string() } else { format!("{s}+{off}") };
        match (&p.idx, flash, ptr) {
            (None, Some(s), _) => {
                self.ins(format!("movlw low {}", sym_off(&s, p.off)));
                self.ins(format!("movwf {l}"));
                self.ins(format!("movlw (high ({})) | 0x80", sym_off(&s, p.off)));
                self.ins(format!("movwf {h}"));
            }
            (None, None, Some(v)) => {
                let m = self.var_mem(v, 0);
                self.fop("movf", &m, "w");
                self.ins(format!("movwf {l}"));
                self.fop("movf", &m.at(1), "w");
                self.ins(format!("movwf {h}"));
                self.add_fsr(n, p.off);
            }
            (Some(idx), fl, ptr) if byte_index(idx).is_some() => {
                // A byte index is added to the base address in WREG, with the carry into the high byte.
                self.ev(byte_index(idx).expect("checked"));
                if let Some(s) = fl {
                    let at = sym_off(&s, p.off);
                    self.ins(format!("addlw low {at}"));
                    self.ins(format!("movwf {l}"));
                    self.ins(format!("movlw (high ({at})) | 0x80"));
                    self.ins("btfsc STATUS, 0");
                    self.ins(format!("movlw ((high ({at})) + 1) | 0x80"));
                } else if let Some(v) = ptr {
                    let m = self.var_mem(v, 0);
                    self.fop("addwf", &m, "w");
                    self.ins(format!("movwf {l}"));
                    self.fop("movf", &m.at(1), "w");
                    self.ins("btfsc STATUS, 0");
                    self.fop("incf", &m.at(1), "w");
                } else {
                    let k = match &p.base {
                        Base::Var(v) => {
                            let m = self.var_mem(*v, p.off);
                            self.note_address_taken(&m.sym);
                            m.addr().map_or(0, fsr_addr)
                        }
                        Base::Abs { addr, .. } => phys_off(*addr, p.off),
                        _ => 0,
                    };
                    if k & 0xFF != 0 {
                        self.ins(format!("addlw 0x{:02X}", k & 0xFF));
                    }
                    self.ins(format!("movwf {l}"));
                    self.ins(format!("movlw 0x{:02X}", (k >> 8) & 0xFF));
                    if k & 0xFF != 0 {
                        self.ins("btfsc STATUS, 0");
                        self.ins(format!("movlw 0x{:02X}", ((k >> 8) + 1) & 0xFF));
                    }
                }
                self.ins(format!("movwf {h}"));
                if ptr.is_some() {
                    self.add_fsr(n, p.off);
                }
            }
            (Some(idx), fl, ptr) => {
                self.ev_a16(idx);
                let (a0, a1) = (self.a(0), self.a(1));
                if let Some(s) = fl {
                    self.ins(format!("movlw low {}", sym_off(&s, p.off)));
                    self.ins(format!("addwf {}, w", a0.text()));
                    self.ins(format!("movwf {l}"));
                    self.ins(format!("movlw (high ({})) | 0x80", sym_off(&s, p.off)));
                    self.ins(format!("addwfc {}, w", a1.text()));
                    self.ins(format!("movwf {h}"));
                } else if let Some(v) = ptr {
                    let m = self.var_mem(v, 0);
                    self.fop("movf", &m, "w");
                    self.ins(format!("addwf {}, w", a0.text()));
                    self.ins(format!("movwf {l}"));
                    self.fop("movf", &m.at(1), "w");
                    self.ins(format!("addwfc {}, w", a1.text()));
                    self.ins(format!("movwf {h}"));
                    self.add_fsr(n, p.off);
                } else {
                    let k = match &p.base {
                        Base::Var(v) => {
                            let m = self.var_mem(*v, p.off);
                            self.note_address_taken(&m.sym);
                            m.addr().map_or(0, fsr_addr)
                        }
                        Base::Abs { addr, .. } => phys_off(*addr, p.off),
                        _ => 0,
                    };
                    self.ins(format!("movlw 0x{:02X}", k & 0xFF));
                    self.ins(format!("addwf {}, w", a0.text()));
                    self.ins(format!("movwf {l}"));
                    self.ins(format!("movlw 0x{:02X}", (k >> 8) & 0xFF));
                    self.ins(format!("addwfc {}, w", a1.text()));
                    self.ins(format!("movwf {h}"));
                }
            }
            _ => self.err("this place cannot be reached through a pointer register"),
        }
    }

    /// FSR`n` += `k`.
    pub fn add_fsr(&mut self, n: u32, k: u32) {
        let k = k as i32;
        if k == 0 {
            return;
        }
        if (-32..32).contains(&k) {
            self.ins(format!("addfsr FSR{n}, {k}"));
        } else {
            self.ins(format!("movlw 0x{:02X}", k & 0xFF));
            self.ins(format!("addwf FSR{n}L, f"));
            self.ins(format!("movlw 0x{:02X}", (k >> 8) & 0xFF));
            self.ins(format!("addwfc FSR{n}H, f"));
        }
    }

    // ---- operands --------------------------------------------------------------------------

    /// True for a constant or a plain variable/register: an operand that needs no evaluation.
    pub fn simple(&self, e: &Ex) -> bool {
        match &e.k {
            ExK::Const(_) => true,
            ExK::Load(p) => !p.indirect() && !p.is_bit() && matches!(p.base, Base::Var(_) | Base::Abs { .. }),
            _ => false,
        }
    }

    /// The expression as an operand of the byte-wise operations. A complex expression is evaluated and
    /// kept in the temporary area (this uses A and WREG, so it comes before the other operand).
    pub fn operand(&mut self, e: &Ex) -> Opd {
        match &e.k {
            ExK::Const(v) => Opd::K(*v),
            ExK::Load(p) if self.simple(e) => Opd::M(self.place_mem(p).expect("simple place")),
            // An unsigned variable widened: the extra bytes are zero, no evaluation needed.
            ExK::Conv(x) if !x.signed && x.w < e.w && self.simple(x) && matches!(x.k, ExK::Load(_)) => {
                let ExK::Load(p) = &x.k else { unreachable!() };
                let m = self.place_mem(p).expect("simple place");
                Opd::Z(m, (x.w / 8) as u32)
            }
            _ => {
                let n = (e.w / 8) as u32;
                self.ev(e);
                let t = self.temp(n);
                self.spill(&t, n, e.w == 8);
                Opd::M(t)
            }
        }
    }

    /// Like [`operand`](Self::operand), for the byte-wise operations that read an operand through `opd_byte`: an
    /// unsigned value widened from fewer bytes is kept at its own width, the rest being zero.
    pub fn operand_nz(&mut self, e: &Ex) -> Opd {
        match &e.k {
            ExK::Conv(x) if !x.signed && x.w < e.w && !self.simple(x) => {
                let n = (x.w / 8) as u32;
                self.ev(x);
                let t = self.temp(n);
                self.spill(&t, n, x.w == 8);
                Opd::Z(t, n)
            }
            _ => self.operand(e),
        }
    }

    /// Stores the value just evaluated (WREG or A) into `t`.
    pub fn spill(&mut self, t: &Mem, n: u32, in_w: bool) {
        if in_w {
            self.fo("movwf", t);
        } else {
            for k in 0..n {
                let a = self.a(k);
                self.fop("movf", &a, "w");
                self.fo("movwf", &t.at(k));
            }
        }
    }

    // ---- values ----------------------------------------------------------------------------

    /// Evaluates `e` into WREG (8 bits) or A (wider).
    pub fn ev(&mut self, e: &Ex) {
        let n = (e.w / 8) as u32;
        match &e.k {
            ExK::Const(v) => {
                if n == 1 {
                    self.ins(format!("movlw 0x{:02X}", v & 0xFF));
                } else {
                    for k in 0..n {
                        let b = (v >> (8 * k)) & 0xFF;
                        let a = self.a(k);
                        if b == 0 {
                            self.fo("clrf", &a);
                        } else {
                            self.ins(format!("movlw 0x{b:02X}"));
                            self.fo("movwf", &a);
                        }
                    }
                }
            }
            ExK::Load(p) => self.load_place(p, e),
            ExK::Abs(x) => self.ev(&crate::lower::abs_expand((**x).clone())),
            ExK::Neg(x) => {
                let x = fit(x, e.w);
                self.ev(&x);
                if n == 1 {
                    self.ins("sublw 0");
                } else {
                    for k in 0..n {
                        let a = self.a(k);
                        self.ins(format!("comf {}, f", a.text()));
                    }
                    let a0 = self.a(0);
                    self.ins(format!("incf {}, f", a0.text()));
                    for k in 1..n {
                        let a = self.a(k);
                        self.ins("btfsc STATUS, 2");
                        self.ins(format!("incf {}, f", a.text()));
                    }
                }
            }
            ExK::Com(x) => {
                let x = fit(x, e.w);
                self.ev(&x);
                if n == 1 {
                    self.ins("xorlw 0xFF");
                } else {
                    for k in 0..n {
                        let a = self.a(k);
                        self.ins(format!("comf {}, f", a.text()));
                    }
                }
            }
            ExK::Bin(k, a, b) => self.bin(*k, a, b, e),
            ExK::Conv(x) => self.conv(x, e),
            ExK::Cmp(..) | ExK::AndAlso(..) | ExK::OrElse(..) | ExK::NotB(..) => {
                let (t, end) = (self.fresh(), self.fresh());
                let start = self.items.len();
                self.cond_jump(e, &t, true);
                // A test that ends in one bit skip or one flag branch sets the value with a skip: `movlw 0` / skip /
                // `movlw 1` (3 words) instead of the branch, `movlw 0`, `bra`, `movlw 1` (5). `movlw` leaves the flags alone.
                let refs = self.items[start..].iter().filter(|i| matches!(i, Item::Br(_, l) | Item::SkipBr(_, l) if *l == t)).count();
                let skip = match self.items.last() {
                    Some(Item::SkipBr(op, l)) if *l == t && refs == 1 => Some(op.clone()),
                    Some(Item::Br(cc, l)) if *l == t && refs == 1 => match cc {
                        Cc::Z => Some("btfsc STATUS, 2".to_string()),
                        Cc::Nz => Some("btfss STATUS, 2".to_string()),
                        Cc::C => Some("btfsc STATUS, 0".to_string()),
                        Cc::Nc => Some("btfss STATUS, 0".to_string()),
                        _ => None,
                    },
                    _ => None,
                };
                if let Some(op) = skip {
                    self.items.pop();
                    self.ins("movlw 0");
                    self.ins(op);
                    self.ins("movlw 1");
                    return;
                }
                self.ins("movlw 0");
                self.br(Cc::Always, &end);
                self.label(&t);
                self.ins("movlw 1");
                self.label(&end);
            }
            ExK::Call(f, args) => {
                let rec = self.recursive_call(*f);
                self.call_func(*f, args, true);
                // A register-call routine leaves its value in A (WREG when it is a byte).
                if self.p.funcs[*f].reg && !rec {
                    return;
                }
                let Some(r) = self.p.funcs[*f].result else {
                    self.err("a routine without a result used as a value");
                    return;
                };
                if rec {
                    // The value is already in A.
                    if n == 1 {
                        let a0 = self.a(0);
                        self.fop("movf", &a0, "w");
                    }
                    return;
                }
                for k in 0..n {
                    let m = self.var_mem(r, k);
                    self.fop("movf", &m, "w");
                    if n > 1 {
                        let a = self.a(k);
                        self.fo("movwf", &a);
                    }
                }
            }
            ExK::Addr(p) => {
                if let Some(a) = self.const_fsr_addr(p) {
                    for (k, v) in [a & 0xFF, (a >> 8) & 0xFF].into_iter().enumerate() {
                        let m = self.a(k as u32);
                        if v == 0 {
                            self.fo("clrf", &m);
                        } else {
                            self.ins(format!("movlw 0x{v:02X}"));
                            self.fo("movwf", &m);
                        }
                    }
                } else {
                    self.set_fsr(0, p);
                    let (a0, a1) = (self.a(0), self.a(1));
                    self.ins("movf FSR0L, w");
                    self.fo("movwf", &a0);
                    self.ins("movf FSR0H, w");
                    self.fo("movwf", &a1);
                }
                for k in 2..n {
                    let m = self.a(k);
                    self.fo("clrf", &m);
                }
            }
            ExK::FuncAddr(f) => {
                self.called.insert(*f);
                self.calls[self.cur].insert(*f);
                let label = self.p.funcs[*f].asm.clone();
                self.word_address(&label, n, false);
            }
            ExK::FlashAddr(i, off) => {
                let label = if *off == 0 { self.p.flash[*i].asm.clone() } else { format!("{}+{off}", self.p.flash[*i].asm) };
                self.word_address(&label, n, true);
            }
            ExK::StrEq(a, b) => {
                let (a, b) = (&self.cat_built(a), &self.cat_built(b));
                let StrSrc::Ram(pa) = a else {
                    self.err("internal: a string comparison needs a variable on the left");
                    return;
                };
                if pa.idx.as_ref().is_some_and(|i| i.uses_fsr()) {
                    self.unsupported("a string element whose index reads an array");
                    return;
                }
                match b {
                    StrSrc::Ram(pb) => {
                        self.set_fsr(1, pb);
                        self.set_fsr(0, pa);
                    }
                    StrSrc::Lit(l) => {
                        self.set_fsr(0, pa);
                        self.point_flash(l);
                    }
                    StrSrc::Char(_) | StrSrc::Cat { .. } => {
                        self.err("internal: a Char in a string comparison");
                        return;
                    }
                }
                self.call_helper("strq1");
            }
        }
    }

    /// The program-memory word address of a label, as a value of `n` bytes in A. With `fsr` it is the address an FSR
    /// reads the byte at (bit 7 of the high byte set, Example 9-2 of DS40002343F): what `AddressOf` of a table gives.
    fn word_address(&mut self, label: &str, n: u32, fsr: bool) {
        let (a0, a1) = (self.a(0), self.a(1));
        self.ins(format!("movlw low ({label})"));
        self.fo("movwf", &a0);
        let flag = if fsr { " | 0x80" } else { "" };
        self.ins(format!("movlw ((({label}) >> 8) & 0x7F){flag}"));
        self.fo("movwf", &a1);
        for k in 2..n {
            let m = self.a(k);
            self.fo("clrf", &m);
        }
    }

    /// Loads the value of a place into WREG or A.
    fn load_place(&mut self, p: &Place, e: &Ex) {
        let n = (e.w / 8) as u32;
        if p.dbit.is_some() {
            self.unsupported("a bit of an array element chosen at run time");
            return;
        }
        if let Some(bit) = p.bit {
            if let Some(m) = self.place_mem(p) {
                self.sel(&m);
                self.ins("movlw 0");
                self.ins(format!("btfsc {}, {bit}", m.text()));
                self.ins("movlw 1");
            } else {
                self.set_fsr(0, p);
                self.ins("movf INDF0, w");
                self.ins(format!("andlw 0x{:02X}", 1u32 << bit));
                self.ins("movlw 0");
                self.ins("btfss STATUS, 2");
                self.ins("movlw 1");
            }
            if n > 1 {
                let a0 = self.a(0);
                self.fo("movwf", &a0);
                for k in 1..n {
                    let m = self.a(k);
                    self.fo("clrf", &m);
                }
            }
            return;
        }
        let pn = p.bytes().min(n);
        if let Some(m) = self.place_mem(p) {
            for k in 0..pn {
                self.fop("movf", &m.at(k), "w");
                if n > 1 {
                    let a = self.a(k);
                    self.fo("movwf", &a);
                }
            }
        } else if matches!(p.base, Base::FlashNext(_)) {
            // Read through the table pointer (FSR1) and step it.
            self.ins("moviw FSR1++");
            if n > 1 {
                let a0 = self.a(0);
                self.fo("movwf", &a0);
                for k in 1..n {
                    let m = self.a(k);
                    self.fo("clrf", &m);
                }
            }
            return;
        } else {
            self.set_fsr(0, p);
            for k in 0..pn {
                self.ins(format!("moviw {k}[FSR0]"));
                if n > 1 {
                    let a = self.a(k);
                    self.fo("movwf", &a);
                }
            }
        }
        // A place narrower than the value (not expected: lowering converts) is zero-extended.
        for k in pn..n {
            let a = self.a(k);
            self.fo("clrf", &a);
        }
    }

    fn conv(&mut self, x: &Ex, e: &Ex) {
        let (sn, dn) = ((x.w / 8) as u32, (e.w / 8) as u32);
        self.ev(x);
        if dn == sn {
            return;
        }
        if dn < sn {
            if dn == 1 {
                let a0 = self.a(0);
                self.fop("movf", &a0, "w");
            }
            return;
        }
        if sn == 1 {
            let a0 = self.a(0);
            self.fo("movwf", &a0);
        }
        if x.signed {
            let top = self.a(sn - 1);
            self.ins("movlw 0");
            self.ins(format!("btfsc {}, 7", top.text()));
            self.ins("movlw 0xFF");
            for k in sn..dn {
                let m = self.a(k);
                self.fo("movwf", &m);
            }
        } else {
            for k in sn..dn {
                let m = self.a(k);
                self.fo("clrf", &m);
            }
        }
    }

    // ---- arithmetic ------------------------------------------------------------------------

    fn bin(&mut self, k: BinKind, a: &Ex, b: &Ex, e: &Ex) {
        match k {
            BinKind::Add | BinKind::Sub | BinKind::And | BinKind::Or | BinKind::Xor => self.alu(k, a, b, e),
            BinKind::Shl | BinKind::Shr => self.shift(k, a, b, e),
            BinKind::Mul | BinKind::Div | BinKind::Mod => self.muldiv(k, a, b, e),
            BinKind::Min | BinKind::Max => self.ev(&crate::lower::minmax_expand(k == BinKind::Max, a.clone(), b.clone())),
        }
    }

    fn alu(&mut self, k: BinKind, a: &Ex, b: &Ex, e: &Ex) {
        let n = (e.w / 8) as u32;
        let (a, b) = (fit(a, e.w), fit(b, e.w));
        // A constant on the left of a commutative operation goes to the right, where `addlw` / `andlw` / `iorlw` /
        // `xorlw` take it (`64 + x` was a copy to a temporary, `movlw`, `addwf`).
        let (a, b) = if matches!(k, BinKind::Add | BinKind::And | BinKind::Or | BinKind::Xor)
            && matches!(a.k, ExK::Const(_))
            && !matches!(b.k, ExK::Const(_))
        {
            (b, a)
        } else {
            (a, b)
        };
        let bo = self.operand_nz(&b);
        if n == 1 {
            // a - b with a plain: load b, then subtract it from a in place.
            if k == BinKind::Sub {
                match (&a.k, &bo) {
                    (ExK::Const(ka), _) => {
                        let s = self.opd_byte(&bo, 0);
                        self.ld_w(&s);
                        self.ins(format!("sublw 0x{:02X}", ka & 0xFF));
                        return;
                    }
                    (ExK::Load(p), _) if self.simple(&a) => {
                        let am = self.place_mem(p).expect("simple place");
                        let s = self.opd_byte(&bo, 0);
                        self.ld_w(&s);
                        self.fop("subwf", &am, "w");
                        return;
                    }
                    _ => {}
                }
            }
            self.ev(&a);
            match (&bo, k) {
                (Opd::K(v), BinKind::Add) => {
                    if v & 0xFF != 0 {
                        self.ins(format!("addlw 0x{:02X}", v & 0xFF));
                    }
                }
                (Opd::K(v), BinKind::Sub) => {
                    if v & 0xFF != 0 {
                        self.ins(format!("addlw 0x{:02X}", (256 - (v & 0xFF)) & 0xFF));
                    }
                }
                (Opd::K(v), BinKind::And) => {
                    if v & 0xFF != 0xFF {
                        self.ins(format!("andlw 0x{:02X}", v & 0xFF));
                    }
                }
                (Opd::K(v), BinKind::Or) => {
                    if v & 0xFF != 0 {
                        self.ins(format!("iorlw 0x{:02X}", v & 0xFF));
                    }
                }
                (Opd::K(v), BinKind::Xor) => {
                    if v & 0xFF != 0 {
                        self.ins(format!("xorlw 0x{:02X}", v & 0xFF));
                    }
                }
                (Opd::M(m), BinKind::Sub) => {
                    let a0 = self.a(0);
                    self.fo("movwf", &a0);
                    self.fop("movf", m, "w");
                    self.fop("subwf", &a0, "w");
                }
                (Opd::M(m), _) => {
                    let op = match k {
                        BinKind::Add => "addwf",
                        BinKind::And => "andwf",
                        BinKind::Or => "iorwf",
                        _ => "xorwf",
                    };
                    self.fop(op, m, "w");
                }
                _ => unreachable!("not an ALU operation"),
            }
            return;
        }
        self.ev(&a);
        for i in 0..n {
            let s = self.opd_byte(&bo, i);
            let am = self.a(i);
            match (k, &s) {
                (BinKind::And, Sb::K(0xFF)) | (BinKind::Or | BinKind::Xor, Sb::K(0)) => continue,
                (BinKind::And, Sb::K(0)) => {
                    self.fo("clrf", &am);
                    continue;
                }
                _ => {}
            }
            self.ld_w(&s);
            let op = match (k, i) {
                (BinKind::Add, 0) => "addwf",
                (BinKind::Add, _) => "addwfc",
                (BinKind::Sub, 0) => "subwf",
                (BinKind::Sub, _) => "subwfb",
                (BinKind::And, _) => "andwf",
                (BinKind::Or, _) => "iorwf",
                _ => "xorwf",
            };
            self.fop(op, &am, "f");
        }
    }

    /// One step of a shift of the n-byte accumulator.
    fn shift1(&mut self, left: bool, signed: bool, n: u32) {
        if left {
            for i in 0..n {
                let a = self.a(i);
                self.ins(format!("{} {}, f", if i == 0 { "lslf" } else { "rlf" }, a.text()));
            }
        } else {
            for i in (0..n).rev() {
                let a = self.a(i);
                let op = if i == n - 1 { if signed { "asrf" } else { "lsrf" } } else { "rrf" };
                self.ins(format!("{op} {}, f", a.text()));
            }
        }
    }

    fn shift(&mut self, k: BinKind, a: &Ex, b: &Ex, e: &Ex) {
        let n = (e.w / 8) as u32;
        let left = k == BinKind::Shl;
        let a = fit(a, e.w);
        if let Some(c) = b.as_const() {
            self.ev(&a);
            if c == 0 {
                return;
            }
            if n == 1 {
                // In WREG itself (a core register in every bank): `swapf` + a mask for the first four places of an
                // unsigned shift, then one `addwf`/`lsrf`/`asrf WREG, w` per place.
                if (left || !e.signed) && c >= 8 {
                    self.ins("movlw 0");
                } else {
                    let mut c = c.min(7);
                    if c == 7 && !e.signed {
                        // Two rotates through carry move the end bit round to the other end: 3 words, not 5.
                        let op = if left { "rrf" } else { "rlf" };
                        self.ins(format!("{op} WREG, w"));
                        self.ins(format!("{op} WREG, w"));
                        self.ins(if left { "andlw 0x80" } else { "andlw 0x01" });
                        return;
                    }
                    if c >= 4 && !e.signed {
                        self.ins("swapf WREG, w");
                        // `(x And 3) << 4`: the high nibble of the operand is clear, so the swap leaves a clear low nibble.
                        if !(left && hi_nibble_clear(&a)) {
                            self.ins(if left { "andlw 0xF0" } else { "andlw 0x0F" });
                        }
                        c -= 4;
                    }
                    let op = if left { "addwf" } else if e.signed { "asrf" } else { "lsrf" };
                    for _ in 0..c {
                        self.ins(format!("{op} WREG, w"));
                    }
                }
                return;
            }
            let (q, r) = (c / 8, c % 8);
            if q >= n {
                if !left && e.signed {
                    let top = self.a(n - 1);
                    self.ins("movlw 0");
                    self.ins(format!("btfsc {}, 7", top.text()));
                    self.ins("movlw 0xFF");
                    for i in 0..n {
                        let m = self.a(i);
                        self.fo("movwf", &m);
                    }
                } else {
                    for i in 0..n {
                        let m = self.a(i);
                        self.fo("clrf", &m);
                    }
                }
                return;
            }
            if q > 0 {
                let fill = if !left && e.signed {
                    let top = self.a(n - 1);
                    let d0 = self.d(0);
                    self.ins("movlw 0");
                    self.ins(format!("btfsc {}, 7", top.text()));
                    self.ins("movlw 0xFF");
                    self.fo("movwf", &d0);
                    Some(d0)
                } else {
                    None
                };
                if left {
                    for i in (q..n).rev() {
                        let (s, d) = (self.a(i - q), self.a(i));
                        self.fop("movf", &s, "w");
                        self.fo("movwf", &d);
                    }
                    for i in 0..q {
                        let m = self.a(i);
                        self.fo("clrf", &m);
                    }
                } else {
                    for i in 0..n - q {
                        let (s, d) = (self.a(i + q), self.a(i));
                        self.fop("movf", &s, "w");
                        self.fo("movwf", &d);
                    }
                    for i in n - q..n {
                        let m = self.a(i);
                        match &fill {
                            Some(d0) => {
                                self.fop("movf", d0, "w");
                                self.fo("movwf", &m);
                            }
                            None => self.fo("clrf", &m),
                        }
                    }
                }
            }
            for _ in 0..r {
                self.shift1(left, e.signed, n);
            }
            return;
        }
        // Run-time count: evaluate it first (it may be a call), then the value.
        let cnt = fit(&Ex { signed: false, ..b.clone() }, 8);
        let co = self.operand(&cnt);
        self.ev(&a);
        if n == 1 {
            let a0 = self.a(0);
            self.fo("movwf", &a0);
        }
        let s = self.opd_byte(&co, 0);
        self.ld_w(&s);
        let d0 = self.d(0);
        self.fo("movwf", &d0);
        let (top, done) = (self.fresh(), self.fresh());
        self.fop("movf", &d0, "f");
        self.br(Cc::Z, &done);
        self.label(&top);
        self.shift1(left, e.signed, n);
        self.items.push(Item::SkipBr(format!("decfsz {}, f", d0.text()), top));
        self.label(&done);
        if n == 1 {
            let a0 = self.a(0);
            self.fop("movf", &a0, "w");
        }
    }

    /// Puts the operands of a register-call routine in `A` and `B` (four bytes each; `b` is absent for a
    /// routine with one operand). `a` is evaluated before `b` whenever either calls a routine, as the arguments
    /// of a call are; without calls the order does not show and `b` goes first, which saves a copy.
    pub fn load_ab(&mut self, a: &Ex, b: Option<&Ex>) {
        let a = fit(a, 32);
        let Some(b) = b else {
            self.ev(&a);
            return;
        };
        let b = fit(b, 32);
        if !a.has_call() && !b.has_call() {
            let bo = self.operand(&b);
            self.ev(&a);
            self.fill_b(&bo);
        } else if b.as_const().is_some() {
            self.ev(&a);
            self.fill_b(&Opd::K(b.as_const().unwrap()));
        } else {
            // `a` waits in the temporary area while `b` is computed (a call in `b` would clobber `A`).
            self.ev(&a);
            let t = self.temp(4);
            self.spill(&t, 4, false);
            if self.simple(&b) {
                let bo = self.operand(&b);
                self.fill_b(&bo);
            } else {
                self.ev(&b);
                for i in 0..4 {
                    let (a, bm) = (self.a(i), self.b(i));
                    self.fop("movf", &a, "w");
                    self.fo("movwf", &bm);
                }
            }
            for i in 0..4 {
                let a = self.a(i);
                self.fop("movf", &t.at(i), "w");
                self.fo("movwf", &a);
            }
        }
    }

    /// Copies the four bytes of `bo` into `B`.
    fn fill_b(&mut self, bo: &Opd) {
        for i in 0..4 {
            let s = self.opd_byte(bo, i);
            self.ld_w(&s);
            let bm = self.b(i);
            self.fo("movwf", &bm);
        }
    }

    fn muldiv(&mut self, k: BinKind, a: &Ex, b: &Ex, e: &Ex) {
        let n = (e.w / 8) as u32;
        let (a, b) = (fit(a, e.w), fit(b, e.w));
        // Multiplication by a power of two is a shift.
        if k == BinKind::Mul && let Some(c) = b.as_const() && c.is_power_of_two() {
            let sh = Ex::konst(c.trailing_zeros(), 8, false);
            self.shift(BinKind::Shl, &a, &sh, e);
            return;
        }
        let bo = self.operand(&b);
        self.ev(&a);
        if n == 1 {
            let a0 = self.a(0);
            self.fo("movwf", &a0);
        }
        for i in 0..n {
            let s = self.opd_byte(&bo, i);
            self.ld_w(&s);
            let bm = self.b(i);
            self.fo("movwf", &bm);
        }
        let name = match (k, e.signed) {
            (BinKind::Mul, _) => format!("mul{n}"),
            (_, false) => format!("udiv{n}"),
            (_, true) => format!("sdiv{n}"),
        };
        self.helpers.insert(name.clone());
        self.call(&format!("__{name}"));
        if k == BinKind::Mod {
            for i in 0..n {
                let (c, a) = (self.c(i), self.a(i));
                self.fop("movf", &c, "w");
                self.fo("movwf", &a);
            }
        }
        if n == 1 {
            let a0 = self.a(0);
            self.fop("movf", &a0, "w");
        }
    }

    // ---- conditions --------------------------------------------------------------------------

    /// Branches to `target` when the truth of `e` equals `sense`; falls through otherwise.
    pub fn cond_jump(&mut self, e: &Ex, target: &str, sense: bool) {
        match &e.k {
            ExK::Const(v) => {
                if (*v != 0) == sense {
                    self.br(Cc::Always, target);
                }
            }
            ExK::NotB(x) => self.cond_jump(x, target, !sense),
            ExK::AndAlso(a, b) => {
                if sense {
                    let skip = self.fresh();
                    self.cond_jump(a, &skip, false);
                    self.cond_jump(b, target, true);
                    self.label(&skip);
                } else {
                    self.cond_jump(a, target, false);
                    self.cond_jump(b, target, false);
                }
            }
            ExK::OrElse(a, b) => {
                if sense {
                    self.cond_jump(a, target, true);
                    self.cond_jump(b, target, true);
                } else {
                    let skip = self.fresh();
                    self.cond_jump(a, &skip, true);
                    self.cond_jump(b, target, false);
                    self.label(&skip);
                }
            }
            // `bit = 1`, `bit <> 0` and the like: one bit skip on the bit itself, not the bit turned into a byte and compared.
            ExK::Cmp(k, a, b) => match self.bit_vs_const(a, b) {
                Some((bit, c)) if matches!(k, CmpKind::Eq | CmpKind::Ne) => {
                    let s = if (c == 1) == (*k == CmpKind::Eq) { sense } else { !sense };
                    self.cond_jump(&bit, target, s);
                }
                _ => self.cmp_jump(*k, a, b, target, sense),
            },
            ExK::Load(p) if p.bit.is_some() && p.dbit.is_none() && self.place_mem(p).is_some() => {
                let m = self.place_mem(p).expect("checked");
                self.sel(&m);
                // Branch when the instruction does not skip: `btfsc` skips on a clear bit.
                let op = if sense { "btfsc" } else { "btfss" };
                self.items.push(Item::SkipBr(format!("{op} {}, {}", m.text(), p.bit.expect("bit")), target.to_string()));
            }
            _ => {
                self.ev(e);
                if e.w > 8 {
                    let a0 = self.a(0);
                    self.fop("movf", &a0, "w");
                    for k in 1..(e.w / 8) as u32 {
                        let a = self.a(k);
                        self.fop("iorwf", &a, "w");
                    }
                } else {
                    self.ins("iorlw 0");
                }
                self.br(if sense { Cc::Nz } else { Cc::Z }, target);
            }
        }
    }

    /// A bit-test operand (a one-bit load the bit-skip arm of [`Self::cond_jump`] takes, perhaps zero-extended) compared with the
    /// constant 0 or 1, either way round: the load and the constant.
    fn bit_vs_const(&mut self, a: &Ex, b: &Ex) -> Option<(Ex, u32)> {
        fn bit_load(e: &Ex) -> Option<&Ex> {
            match &e.k {
                ExK::Load(p) if p.bit.is_some() && p.dbit.is_none() && !e.signed => Some(e),
                ExK::Conv(x) if !x.signed => bit_load(x),
                _ => None,
            }
        }
        for (x, y) in [(a, b), (b, a)] {
            if let (Some(l), ExK::Const(c)) = (bit_load(x), &y.k)
                && *c <= 1
                && let ExK::Load(p) = &l.k
                && self.place_mem(p).is_some()
            {
                return Some((l.clone(), *c));
            }
        }
        None
    }

    /// Branches to `target` when `a <kind> b` equals `sense`.
    pub fn cmp_jump(&mut self, kind: CmpKind, a: &Ex, b: &Ex, target: &str, sense: bool) {
        let kind = if sense { kind } else { kind.negate() };
        let w = a.w.max(b.w);
        let signed = a.signed && b.signed;
        let (a, b) = (fit(a, w), fit(b, w));
        // Unsigned against 0 or 1 where the answer is "is it zero": `x > 0`, `x >= 1`, `0 < x`, `1 <= x` are `x <> 0`,
        // and the negations `x = 0`; `movf x, f` and a branch per byte, not the value copied to __A and subtracted.
        if !signed {
            let k = |e: &Ex| e.as_const().map(|c| c & mask(w));
            let zero_test = match (kind, k(&a), k(&b)) {
                (CmpKind::Gt, None, Some(0)) | (CmpKind::Ge, None, Some(1)) => Some((&a, false)),
                (CmpKind::Le, None, Some(0)) | (CmpKind::Lt, None, Some(1)) => Some((&a, true)),
                (CmpKind::Lt, Some(0), None) | (CmpKind::Le, Some(1), None) => Some((&b, false)),
                (CmpKind::Ge, Some(0), None) | (CmpKind::Gt, Some(1), None) => Some((&b, true)),
                _ => None,
            };
            if let Some((x, eq)) = zero_test
                && self.simple(x)
            {
                let z = Ex::konst(0, x.w, false);
                self.eq_jump(x, &z, target, eq);
                return;
            }
        }
        // An unsigned 16-bit variable against a multiple of 256 (`x >= 256`, `x < 512`, and so `x > 255`, `x <= 511`) only
        // needs its high byte: `movf hi, f` and a branch for 256, `movlw`/`subwf hi, w` and a branch for the others.
        if !signed
            && w == 16
            && matches!(kind, CmpKind::Lt | CmpKind::Ge | CmpKind::Gt | CmpKind::Le)
        {
            let (kind, x, c) = match (&a.k, &b.k) {
                (ExK::Load(_), ExK::Const(c)) if self.simple(&a) => (kind, &a, *c & 0xFFFF),
                (ExK::Const(c), ExK::Load(_)) if self.simple(&b) => (
                    match kind {
                        CmpKind::Lt => CmpKind::Gt,
                        CmpKind::Gt => CmpKind::Lt,
                        CmpKind::Le => CmpKind::Ge,
                        _ => CmpKind::Le,
                    },
                    &b,
                    *c & 0xFFFF,
                ),
                _ => (kind, &a, u32::MAX),
            };
            // `x > K` is `x >= K + 1` and `x <= K` is `x < K + 1`; the limit is then the multiple of 256.
            let (lt, lim) = match kind {
                CmpKind::Lt => (true, c),
                CmpKind::Ge => (false, c),
                CmpKind::Le => (true, c.wrapping_add(1)),
                _ => (false, c.wrapping_add(1)),
            };
            if c <= 0xFFFF && lim % 256 == 0 && (256..=255 * 256).contains(&lim) {
                let ExK::Load(p) = &x.k else { unreachable!() };
                let hi = self.place_mem(p).expect("simple place").at(1);
                if lim == 256 {
                    self.fop("movf", &hi, "f");
                    self.br(if lt { Cc::Z } else { Cc::Nz }, target);
                } else {
                    self.ins(format!("movlw {}", lim >> 8));
                    self.fop("subwf", &hi, "w");
                    self.br(if lt { Cc::Nc } else { Cc::C }, target);
                }
                return;
            }
        }
        match kind {
            CmpKind::Eq | CmpKind::Ne => self.eq_jump(&a, &b, target, kind == CmpKind::Eq),
            _ if w == 8 && !signed => self.cmp8(kind, a, b, target),
            CmpKind::Lt | CmpKind::Ge => {
                self.order(&a, &b, signed);
                self.br(if kind == CmpKind::Lt { Cc::Nc } else { Cc::C }, target);
            }
            CmpKind::Gt | CmpKind::Le => {
                // a > b is b < a, a <= b is b >= a: C after b - a.
                self.order(&b, &a, signed);
                self.br(if kind == CmpKind::Gt { Cc::Nc } else { Cc::C }, target);
            }
        }
    }

    /// An unsigned byte compare in WREG: `sublw`/`subwf` leave C set when the operand in memory (or the literal) is at
    /// least the one in WREG, so the operand that must be in WREG is the right side of `>=` and `<`, the left side of
    /// `<=` and `>`. The sides swap when that puts a computed value in memory and a plain one in WREG.
    fn cmp8(&mut self, kind: CmpKind, a: Ex, b: Ex, target: &str) {
        let (mut kind, mut a, mut b) = (kind, a, b);
        let plain = |me: &Self, e: &Ex| matches!(e.k, ExK::Const(_)) || me.simple(e);
        let w_is_b = matches!(kind, CmpKind::Ge | CmpKind::Lt);
        let (u, v) = if w_is_b { (&b, &a) } else { (&a, &b) };
        if !plain(self, v) && plain(self, u) {
            std::mem::swap(&mut a, &mut b);
            kind = match kind {
                CmpKind::Ge => CmpKind::Le,
                CmpKind::Le => CmpKind::Ge,
                CmpKind::Lt => CmpKind::Gt,
                _ => CmpKind::Lt,
            };
        }
        let w_is_b = matches!(kind, CmpKind::Ge | CmpKind::Lt);
        let (u, v) = if w_is_b { (&b, &a) } else { (&a, &b) };
        let vo = self.operand(v);
        self.ev(u);
        match &vo {
            Opd::K(k) => self.ins(format!("sublw 0x{:02X}", k & 0xFF)),
            Opd::M(m) => self.fop("subwf", m, "w"),
            Opd::Z(..) => unreachable!("a byte operand"),
        }
        self.br(if matches!(kind, CmpKind::Ge | CmpKind::Le) { Cc::C } else { Cc::Nc }, target);
    }

    /// Leaves C set when `x >= y` (unsigned, or signed after flipping both sign bits).
    fn order(&mut self, x: &Ex, y: &Ex, signed: bool) {
        let n = (x.w / 8) as u32;
        let yo = self.operand(y);
        self.ev(x);
        if n == 1 {
            let a0 = self.a(0);
            self.fo("movwf", &a0);
        }
        let top = self.a(n - 1);
        if signed {
            self.ins("movlw 0x80");
            self.fop("xorwf", &top, "f");
        }
        for i in 0..n {
            let s = self.opd_byte(&yo, i);
            self.ld_w(&s);
            if signed && i == n - 1 {
                self.ins("xorlw 0x80");
            }
            let am = self.a(i);
            self.fop(if i == 0 { "subwf" } else { "subwfb" }, &am, "w");
        }
    }

    fn eq_jump(&mut self, a: &Ex, b: &Ex, target: &str, eq: bool) {
        let n = (a.w / 8) as u32;
        let bo = self.operand(b);
        // The left side: a plain variable is compared in place, anything else goes through A.
        let ao = if self.simple(a) {
            match &a.k {
                ExK::Load(p) => Opd::M(self.place_mem(p).expect("simple place")),
                _ => Opd::K(a.as_const().unwrap_or(0)),
            }
        } else {
            self.ev(a);
            if n == 1 {
                let a0 = self.a(0);
                self.fo("movwf", &a0);
            }
            Opd::M(self.a(0))
        };
        // A constant on the left swaps with a variable on the right.
        let (ao, bo) = if matches!(ao, Opd::K(_)) { (bo, ao) } else { (ao, bo) };
        let Opd::M(am) = &ao else {
            // Both constants: decided now.
            let (Opd::K(x), Opd::K(y)) = (&ao, &bo) else { unreachable!() };
            let mask = if a.w >= 32 { u32::MAX } else { (1u32 << a.w) - 1 };
            if ((x & mask) == (y & mask)) == eq {
                self.br(Cc::Always, target);
            }
            return;
        };
        let ne = self.fresh();
        for i in 0..n {
            let s = self.opd_byte(&bo, i);
            let last = i == n - 1;
            match &s {
                Sb::K(0) => {
                    self.fop("movf", &am.at(i), "f");
                }
                // `incf` / `decf` into W sets Z exactly when the byte is 0xFF / 1 (one word, not `movlw` + `xorwf`).
                Sb::K(k @ (1 | 0xFF)) => {
                    let op = if *k == 1 { "decf" } else { "incf" };
                    self.fop(op, &am.at(i), "w");
                }
                _ => {
                    self.ld_w(&s);
                    self.fop("xorwf", &am.at(i), "w");
                }
            }
            if last {
                self.br(if eq { Cc::Z } else { Cc::Nz }, target);
            } else if eq {
                self.br(Cc::Nz, &ne);
            } else {
                self.br(Cc::Nz, target);
            }
        }
        self.label(&ne);
    }
}
