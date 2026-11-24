//! dsPIC33 code generator: IR in, `xc-dsc-as` assembly out.
//!
//! The core is a 16-bit machine with sixteen working registers `W0..W15`, 24-bit instructions, a data space of bytes
//! (words must sit at even addresses) and a software stack in RAM (`W15`, growing up). Facts are in
//! `docs/FACTS-dsPIC33CK64MC105.md`.
//!
//! Value model. An expression of 8 or 16 bits is evaluated into `W0` (a byte in the low byte, the high byte undefined),
//! one of 24 or 32 bits into `W1:W0` (24-bit values are kept sign- or zero-extended to 32). `W2:W3` is the second
//! operand, `W3` also the effective address of an indirect access, `W4..W7` are scratch for multiply, divide and the
//! helpers. A partial result that must survive another operand is pushed on the stack.
//!
//! Memory. The generator places every variable itself (data addresses from the start of RAM, words and larger
//! objects on even addresses); symbols are `.equ` constants, so the assembler checks every operand. The stack
//! follows the variables up to the end of RAM; `SPLIM` is set to the last word. Direct operands of byte
//! instructions reach 13 address bits (the first 8 Kbytes); anything above goes through `W4`.
//!
//! Code. Calls are `rcall` and branches `bra` (16-bit word displacement, which covers the part's program memory).
//! Not yet generated (reported as `E-BACKEND`): interrupts, `Float`, strings, constant tables, calls to C and recursion.

use crate::codegen::{Generated, Layout, Obj, Output, Target};
use crate::diag::Span;
use crate::fxhash::HashMap;
use crate::ir::*;
use std::collections::BTreeSet;

/// Direct (file register) operands of byte instructions have 13 address bits.
const NEAR: u32 = 0x2000;

fn sz(w: u8) -> u8 {
    if w <= 8 {
        1
    } else if w <= 16 {
        2
    } else {
        4
    }
}

fn reg(n: u8) -> String {
    format!("W{n}")
}

/// How an access reaches its bytes: at a fixed data address, or through the effective address held in `W3`.
#[derive(Clone, Copy, Debug)]
enum Acc {
    Direct(u32),
    /// `W3` points at the first byte; `even` when that address is known to be even.
    Reg { even: bool },
    /// `W3` points at the first byte in program memory (read with `tblrdl`); `even` as above.
    Prog { even: bool },
}

struct G<'p> {
    p: &'p Program,
    tgt: &'p Target,
    out: Vec<String>,
    lbl: u32,
    loops: Vec<(String, String)>,
    errors: Vec<(Span, String)>,
    addr: Vec<u32>,
    span: Span,
    helpers: BTreeSet<&'static str>,
    fcy: f64,
    calls: Vec<BTreeSet<FuncId>>,
    /// The routines each routine can reach through calls (one call or more).
    reach: Vec<BTreeSet<FuncId>>,
    cur: usize,
    /// Label that ends the interrupt handler being generated.
    isr_end: Option<String>,
    /// Data address of the table pointer (`FlashSeek`, `FlashNext`), once the program is known to use it.
    tblp: Option<u32>,
    need_tblp: bool,
    /// String literals (program memory) in the order they were first used.
    lits: Vec<Vec<u8>>,
    /// Whether the string cursor registers `W8` and `W9` are used.
    uses_w8: bool,
    /// `Save` blocks being generated: the loop depth they opened at and the code that restores them.
    saves: Vec<(usize, Vec<String>)>,
}

impl<'p> G<'p> {
    fn err(&mut self, m: impl Into<String>) {
        let m = m.into();
        if !self.errors.iter().any(|e| e.1 == m) {
            self.errors.push((self.span, m));
        }
    }
    fn i(&mut self, s: impl AsRef<str>) {
        self.out.push(format!("        {}", s.as_ref()));
    }
    fn fresh(&mut self) -> String {
        self.lbl += 1;
        format!("L{}", self.lbl)
    }
    fn label(&mut self, l: &str) {
        self.out.push(format!("{l}:"));
    }
    fn bra(&mut self, cc: &str, l: &str) {
        if cc.is_empty() {
            self.i(format!("bra {l}"));
        } else {
            self.i(format!("bra {cc},{l}"));
        }
    }

    // ---- constants and registers ------------------------------------------------------------------------------

    fn mov_const(&mut self, r: u8, v: u32, s: u8) {
        let lo = v & 0xFFFF;
        let hi = v >> 16;
        if lo == 0 {
            self.i(format!("clr {}", reg(r)));
        } else {
            self.i(format!("mov #0x{lo:X},{}", reg(r)));
        }
        if s == 4 {
            if hi == 0 {
                self.i(format!("clr {}", reg(r + 1)));
            } else {
                self.i(format!("mov #0x{hi:X},{}", reg(r + 1)));
            }
        }
    }

    /// `reg += n` for an address register.
    fn add_imm(&mut self, r: u8, n: u32) {
        if n == 0 {
            return;
        }
        if n < 1024 {
            self.i(format!("add #{n},{}", reg(r)));
        } else {
            self.i(format!("mov #{n},W4"));
            self.i(format!("add {},W4,{}", reg(r), reg(r)));
        }
    }

    fn push(&mut self, s: u8) {
        self.i(if s == 4 { "push.d W0" } else { "push W0" });
    }
    fn pop(&mut self, r: u8, s: u8) {
        self.i(if s == 4 { format!("pop.d {}", reg(r)) } else { format!("pop {}", reg(r)) });
    }
    /// Moves the result in `W1:W0` to `W3:W2` (or `W0` to `W2`).
    fn to_second(&mut self, s: u8) {
        if s == 4 {
            self.i("mov.d W0,W2");
        } else {
            self.i("mov W0,W2");
        }
    }

    // ---- memory access ----------------------------------------------------------------------------------------

    /// The address register of a data address (a PORT written goes to its latch).
    fn abs_addr(&self, addr: u32, name: &str, write: bool) -> u32 {
        if write {
            if let Some(port) = name.strip_prefix("PORT") {
                if let Some(a) = self.tgt.sfr.get(&format!("LAT{port}")) {
                    return *a;
                }
            }
        }
        addr
    }

    /// Whether the place has a fixed data address (and which).
    fn direct(&self, pl: &Place, write: bool) -> Option<u32> {
        if pl.idx.is_some() {
            return None;
        }
        match &pl.base {
            Base::Var(v) => Some(self.addr[*v] + pl.off),
            Base::Abs { addr, name } => Some(self.abs_addr(*addr, name, write) + pl.off),
            _ => None,
        }
    }

    /// Leaves the place's address in `W3` unless it is fixed. May clobber `W0..W7`.
    fn prep(&mut self, pl: &Place, write: bool) -> Acc {
        if pl.dbit.is_some() {
            self.err("a bit chosen at run time is not supported on the dsPIC33 yet");
        }
        match &pl.base {
            Base::Flash(t) => {
                if let Some(ix) = &pl.idx {
                    self.ev(ix);
                }
                let sym = self.p.flash[*t].asm.clone();
                self.i(format!("mov #tbloffset({sym}),W3"));
                if pl.idx.is_some() {
                    self.i("add W0,W3,W3");
                }
                self.add_imm(3, pl.off);
                Acc::Prog { even: pl.off % 2 == 0 }
            }
            Base::FlashNext(_) => {
                self.err("internal: a table read through the table pointer used as a place");
                Acc::Direct(0)
            }
            Base::Var(_) | Base::Abs { .. } if pl.idx.is_none() => Acc::Direct(self.direct(pl, write).unwrap()),
            _ => {
                let (base, off) = match &pl.base {
                    Base::Var(v) => (Some(self.addr[*v]), pl.off),
                    Base::Abs { addr, name } => (Some(self.abs_addr(*addr, name, write)), pl.off),
                    _ => (None, pl.off),
                };
                if let Some(ix) = &pl.idx {
                    self.ev(ix);
                }
                match (&pl.base, base) {
                    (_, Some(a)) => {
                        self.i(format!("mov #0x{:X},W3", a + off));
                        if pl.idx.is_some() {
                            self.i("add W0,W3,W3");
                        }
                        // A word array element is even when the array and the offset are.
                        Acc::Reg { even: (a + off) % 2 == 0 }
                    }
                    (Base::Ptr(v), None) => {
                        let a = self.addr[*v];
                        self.i(format!("mov 0x{a:X},W3"));
                        if pl.idx.is_some() {
                            self.i("add W0,W3,W3");
                        }
                        self.add_imm(3, off);
                        Acc::Reg { even: off % 2 == 0 }
                    }
                    _ => Acc::Direct(0),
                }
            }
        }
    }

    /// `[W3]` or `[W3+k]` as an operand.
    fn ind(k: u32) -> String {
        if k == 0 { "[W3]".to_string() } else { format!("[W3+{k}]") }
    }

    /// Loads one byte at `acc + k` into `r` (the high byte of `r` is left undefined).
    fn ld_byte(&mut self, acc: Acc, k: u32, r: u8) {
        match acc {
            Acc::Direct(a) if r == 0 && a + k < NEAR => self.i(format!("mov.b 0x{:X},WREG", a + k)),
            Acc::Direct(a) => {
                self.i(format!("mov #0x{:X},W4", a + k));
                self.i(format!("mov.b [W4],{}", reg(r)));
            }
            Acc::Reg { .. } => self.i(format!("mov.b {},{}", Self::ind(k), reg(r))),
            Acc::Prog { .. } => {
                // Bytes of a table are read in order through the pointer.
                self.i(format!("tblrdl.b [W3{}],{}", if k == 0 { "" } else { "++" }, reg(r)));
            }
        }
    }
    fn st_byte(&mut self, acc: Acc, k: u32, r: u8) {
        match acc {
            Acc::Direct(a) if r == 0 && a + k < NEAR => self.i(format!("mov.b WREG,0x{:X}", a + k)),
            Acc::Direct(a) => {
                self.i(format!("mov #0x{:X},W4", a + k));
                self.i(format!("mov.b {},[W4]", reg(r)));
            }
            Acc::Reg { .. } => self.i(format!("mov.b {},{}", reg(r), Self::ind(k))),
            Acc::Prog { .. } => self.err("program memory cannot be written"),
        }
    }
    /// Whether a word access at `acc + k` is on an even address.
    fn even(acc: Acc, k: u32) -> bool {
        match acc {
            Acc::Direct(a) => (a + k) % 2 == 0,
            Acc::Reg { even } | Acc::Prog { even } => even && k % 2 == 0,
        }
    }
    fn ld_word(&mut self, acc: Acc, k: u32, r: u8) {
        if Self::even(acc, k) {
            match acc {
                Acc::Direct(a) => self.i(format!("mov 0x{:X},{}", a + k, reg(r))),
                Acc::Reg { .. } => self.i(format!("mov {},{}", Self::ind(k), reg(r))),
                Acc::Prog { .. } => self.i(format!("tblrdl [W3{}],{}", if k == 0 { "" } else { "++" }, reg(r))),
            }
        } else {
            // Two bytes: low, then high shifted up (W6 is scratch).
            self.ld_byte(acc, k, r);
            self.i(format!("ze {0},{0}", reg(r)));
            self.ld_byte(acc, k + 1, 6);
            self.i("sl W6,#8,W6");
            self.i(format!("ior {0},W6,{0}", reg(r)));
        }
    }
    fn st_word(&mut self, acc: Acc, k: u32, r: u8) {
        if Self::even(acc, k) {
            match acc {
                Acc::Direct(a) => self.i(format!("mov {},0x{:X}", reg(r), a + k)),
                Acc::Reg { .. } => self.i(format!("mov {},{}", reg(r), Self::ind(k))),
                Acc::Prog { .. } => self.err("program memory cannot be written"),
            }
        } else {
            self.st_byte(acc, k, r);
            self.i(format!("lsr {},#8,W6", reg(r)));
            self.st_byte(acc, k + 1, 6);
        }
    }

    /// Reads `n` (1 to 4) bytes at `acc` into `W{r}` (`W{r+1}`); a 3-byte value gets its top byte zero-extended.
    fn rd(&mut self, acc: Acc, n: u32, r: u8) {
        if let Acc::Prog { even } = acc {
            // Read in order, each read stepping the pointer over what it took.
            let inc = |more: bool, w: bool| if more { "++" } else if w { "" } else { "" };
            match n {
                1 => self.i(format!("tblrdl.b [W3],{}", reg(r))),
                2 if even => self.i(format!("tblrdl [W3],{}", reg(r))),
                4 if even => {
                    self.i(format!("tblrdl [W3{}],{}", inc(true, true), reg(r)));
                    self.i(format!("tblrdl [W3],{}", reg(r + 1)));
                }
                3 if even => {
                    self.i(format!("tblrdl [W3{}],{}", inc(true, true), reg(r)));
                    self.i(format!("tblrdl.b [W3],{}", reg(r + 1)));
                    self.i(format!("ze {0},{0}", reg(r + 1)));
                }
                _ => {
                    // Odd address: byte by byte.
                    for w in 0..n.div_ceil(2) {
                        let dst = r + w as u8;
                        let t = if w == 0 { dst } else { dst };
                        self.i(format!("tblrdl.b [W3++],{}", reg(t)));
                        if n > 2 * w + 1 {
                            self.i(format!("ze {0},{0}", reg(t)));
                            self.i(format!("tblrdl.b [W3{}],W6", if n > 2 * w + 2 { "++" } else { "" }));
                            self.i("sl W6,#8,W6");
                            self.i(format!("ior {0},W6,{0}", reg(t)));
                        } else if n > 2 {
                            self.i(format!("ze {0},{0}", reg(t)));
                        }
                    }
                }
            }
            return;
        }
        match n {
            1 => self.ld_byte(acc, 0, r),
            2 => self.ld_word(acc, 0, r),
            3 => {
                self.ld_word(acc, 0, r);
                self.ld_byte(acc, 2, r + 1);
                self.i(format!("ze {0},{0}", reg(r + 1)));
            }
            _ => {
                self.ld_word(acc, 0, r);
                self.ld_word(acc, 2, r + 1);
            }
        }
    }
    fn wr(&mut self, acc: Acc, n: u32, r: u8) {
        match n {
            1 => self.st_byte(acc, 0, r),
            2 => self.st_word(acc, 0, r),
            3 => {
                self.st_word(acc, 0, r);
                self.st_byte(acc, 2, r + 1);
            }
            _ => {
                self.st_word(acc, 0, r);
                self.st_word(acc, 2, r + 1);
            }
        }
    }

    /// Sets, clears or toggles bit `b` of the byte at `acc`.
    fn bit_op(&mut self, op: &str, acc: Acc, b: u8) {
        match acc {
            Acc::Direct(a) if a < NEAR => self.i(format!("{op}.b 0x{a:X},#{b}")),
            Acc::Direct(a) => {
                self.i(format!("mov #0x{a:X},W4"));
                self.i(format!("{op}.b [W4],#{b}"));
            }
            Acc::Reg { .. } => self.i(format!("{op}.b [W3],#{b}")),
            Acc::Prog { .. } => self.err("program memory cannot be written"),
        }
    }

    /// The word file register and bit that test bit `b` of the byte at `a`, when it is a direct operand.
    fn word_bit(a: u32, b: u8) -> Option<(u32, u8)> {
        (a < NEAR).then(|| (a & !1, b + 8 * (a & 1) as u8))
    }

    /// A bit of a 16-bit register counts from bit 0 of the whole register: make it a bit (0 to 7) of the byte that holds it.
    fn byte_bit(pl: &Place) -> Place {
        match pl.bit {
            Some(b) if b >= 8 => Place { off: pl.off + u32::from(b / 8), bit: Some(b % 8), ..pl.clone() },
            _ => pl.clone(),
        }
    }

    // ---- loads ------------------------------------------------------------------------------------------------

    /// A load that needs no pointer and no evaluation: it can go straight into `W{r}`.
    fn simple(&self, e: &Ex) -> bool {
        match &e.k {
            ExK::Const(_) => true,
            ExK::Load(pl) => pl.bit.is_none() && self.direct(pl, false).is_some(),
            _ => false,
        }
    }

    fn ld_simple(&mut self, e: &Ex, r: u8) {
        let s = sz(e.w);
        match &e.k {
            ExK::Const(v) => {
                let mut v = *v;
                if e.signed && e.w == 24 && v & 0x80_0000 != 0 {
                    v |= 0xFF00_0000;
                }
                self.mov_const(r, v, s)
            }
            ExK::Load(pl) => {
                let a = self.direct(pl, false).unwrap();
                self.rd(Acc::Direct(a), pl.bytes(), r);
                self.norm_reg(e, r);
            }
            _ => unreachable!(),
        }
    }

    /// Keeps a 24-bit value sign- or zero-extended in its top word.
    fn norm_reg(&mut self, e: &Ex, r: u8) {
        if e.w == 24 {
            let hi = reg(r + 1);
            if e.signed {
                self.i(format!("se {hi},{hi}"));
            } else {
                self.i(format!("and #0xFF,{hi}"));
            }
        }
    }

    /// Evaluates `a` into `W0` and `b` into `W2` (with the high words in `W1` and `W3`).
    fn operands(&mut self, a: &Ex, b: &Ex) {
        let s = sz(a.w).max(sz(b.w));
        if self.simple(b) {
            self.ev(a);
            self.ld_simple(b, 2);
        } else {
            self.ev(a);
            self.push(s);
            self.ev(b);
            self.to_second(s);
            self.pop(0, s);
        }
    }

    /// Evaluates `e` into `W0` (`W1:W0` for 24 and 32 bits).
    fn ev(&mut self, e: &Ex) {
        let s = sz(e.w);
        match &e.k {
            ExK::Const(_) => self.ld_simple(e, 0),
            ExK::Load(pl) => self.load(pl, e),
            ExK::Neg(x) => {
                self.ev(x);
                match s {
                    1 => self.i("neg.b W0,W0"),
                    2 => self.i("neg W0,W0"),
                    _ => {
                        self.i("com W0,W0");
                        self.i("com W1,W1");
                        self.i("add #1,W0");
                        self.i("addc #0,W1");
                    }
                }
                self.norm(e);
            }
            ExK::Com(x) => {
                self.ev(x);
                match s {
                    1 => self.i("com.b W0,W0"),
                    2 => self.i("com W0,W0"),
                    _ => {
                        self.i("com W0,W0");
                        self.i("com W1,W1");
                    }
                }
                self.norm(e);
            }
            ExK::Abs(x) => {
                self.ev(x);
                let l = self.fresh();
                match s {
                    1 => {
                        self.i("cp0.b W0");
                        self.bra("ge", &l);
                        self.i("neg.b W0,W0");
                    }
                    2 => {
                        self.i("cp0 W0");
                        self.bra("ge", &l);
                        self.i("neg W0,W0");
                    }
                    _ => {
                        self.i("btss W1,#15");
                        self.bra("", &l);
                        self.i("com W0,W0");
                        self.i("com W1,W1");
                        self.i("add #1,W0");
                        self.i("addc #0,W1");
                    }
                }
                self.label(&l);
                self.norm(e);
            }
            ExK::Bin(k, a, b) => self.bin(*k, a, b, e),
            ExK::Conv(x) => {
                self.ev(x);
                let (ss, ds) = (sz(x.w), s);
                if ds > ss {
                    if ss == 1 {
                        self.i(if x.signed { "se W0,W0" } else { "ze W0,W0" });
                    }
                    if ds == 4 {
                        if x.signed {
                            self.i("asr W0,#15,W1");
                        } else {
                            self.i("clr W1");
                        }
                    }
                }
                self.norm(e);
            }
            ExK::Cmp(..) | ExK::AndAlso(..) | ExK::OrElse(..) | ExK::NotB(..) => {
                let (f, end) = (self.fresh(), self.fresh());
                self.cond_jump(e, false, &f);
                self.i("mov #1,W0");
                self.bra("", &end);
                self.label(&f);
                self.i("clr W0");
                self.label(&end);
            }
            ExK::Call(f, args) => {
                let restore = self.call(*f, args);
                match self.p.funcs[*f].result {
                    // A register-call routine returns its value in W1:W0.
                    _ if self.p.funcs[*f].reg => {}
                    Some(v) => {
                        let pl = Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: self.p.vars[v].ty.clone() };
                        let ex = Ex::new(ExK::Load(pl), e.w, e.signed);
                        self.ld_simple(&ex, 0);
                    }
                    None => self.err("a routine without a result used as a value"),
                }
                for l in restore {
                    self.i(l);
                }
            }
            ExK::Addr(pl) => {
                match &pl.base {
                    Base::Var(v) if pl.idx.is_none() => self.i(format!("mov #0x{:X},W0", self.addr[*v] + pl.off)),
                    Base::Abs { addr, .. } if pl.idx.is_none() => self.i(format!("mov #0x{:X},W0", addr + pl.off)),
                    _ => {
                        self.prep(pl, false);
                        self.i("mov W3,W0");
                    }
                }
            }
            ExK::FuncAddr(f) => {
                let name = self.p.funcs[*f].asm.clone();
                self.i(format!("mov #tbloffset({name}),W0"));
                self.i("clr W1");
            }
            ExK::FlashAddr(t, off) => {
                let sym = self.p.flash[*t].asm.clone();
                self.i(format!("mov #tbloffset({sym}),W0"));
                self.add_imm(0, *off);
                self.i("clr W1");
            }
            ExK::StrEq(a, b) => self.str_eq(a, b),
        }
    }

    fn norm(&mut self, e: &Ex) {
        self.norm_reg(e, 0);
    }

    fn load(&mut self, pl: &Place, e: &Ex) {
        if let Base::FlashNext(_) = pl.base {
            // One byte through the table pointer, which steps on.
            match self.tblp {
                Some(t) => {
                    self.i(format!("mov 0x{t:X},W3"));
                    self.i("tblrdl.b [W3],W0");
                    self.i(format!("inc 0x{t:X}"));
                }
                None => self.need_tblp = true,
            }
            return;
        }
        let pl = &Self::byte_bit(pl);
        if let Some(b) = pl.bit {
            // A single bit reads as 0 or 1.
            if let Some(a) = self.direct(pl, false) {
                if let Some((fa, fb)) = Self::word_bit(a, b) {
                    self.i("clr.b W0");
                    self.i(format!("btsc 0x{fa:X},#{fb}"));
                    self.i("inc.b W0,W0");
                    return;
                }
            }
            let acc = self.prep(pl, false);
            self.ld_byte(acc, 0, 0);
            self.i(format!("btst.c W0,#{b}"));
            self.i("clr.b W0");
            self.i("rlc.b W0,W0");
            return;
        }
        let acc = self.prep(pl, false);
        self.rd(acc, pl.bytes(), 0);
        self.norm(e);
    }

    // ---- arithmetic -------------------------------------------------------------------------------------------

    fn bin(&mut self, k: BinKind, a: &Ex, b: &Ex, e: &Ex) {
        let s = sz(e.w);
        let bw = if s == 1 { ".b" } else { "" };
        match k {
            BinKind::Shl | BinKind::Shr => return self.shift(k, a, b, e),
            BinKind::Add | BinKind::Sub => {
                if let Some(c) = b.as_const() {
                    // A small constant is a literal operand (10 bits).
                    let c = c & crate::ir::mask(e.w);
                    let mag = c;
                    if mag < 1024 && s <= 4 {
                        self.ev(a);
                        let op = if k == BinKind::Add { ("add", "addc") } else { ("sub", "subb") };
                        self.i(format!("{}{bw} #{mag},W0", op.0));
                        if s == 4 {
                            self.i(format!("{} #0,W1", op.1));
                        }
                        return self.norm(e);
                    }
                }
                self.operands(a, b);
                let op = if k == BinKind::Add { ("add", "addc") } else { ("sub", "subb") };
                self.i(format!("{}{bw} W0,W2,W0", op.0));
                if s == 4 {
                    self.i(format!("{} W1,W3,W1", op.1));
                }
            }
            BinKind::And | BinKind::Or | BinKind::Xor => {
                self.operands(a, b);
                let op = match k {
                    BinKind::And => "and",
                    BinKind::Or => "ior",
                    _ => "xor",
                };
                self.i(format!("{op}{bw} W0,W2,W0"));
                if s == 4 {
                    self.i(format!("{op} W1,W3,W1"));
                }
            }
            BinKind::Mul => {
                self.operands(a, b);
                if s < 4 {
                    self.i("mul.uu W0,W2,W0");
                } else {
                    // Low 32 bits of the product: alo*blo + ((ahi*blo + alo*bhi) << 16).
                    self.i("mul.uu W0,W2,W4");
                    self.i("mul.uu W1,W2,W6");
                    self.i("add W5,W6,W5");
                    self.i("mul.uu W0,W3,W6");
                    self.i("add W5,W6,W5");
                    self.i("mov.d W4,W0");
                }
            }
            BinKind::Div | BinKind::Mod => {
                self.operands(a, b);
                let signed = a.signed || b.signed;
                if s == 4 {
                    self.helpers.insert(if signed { "sdiv32" } else { "udiv32" });
                    self.i(format!("rcall __{}div32", if signed { "s" } else { "u" }));
                    if k == BinKind::Mod {
                        self.i("mov.d W4,W0");
                    }
                } else {
                    if s == 1 {
                        let (x, y) = if signed { ("se", "se") } else { ("ze", "ze") };
                        self.i(format!("{x} W0,W0"));
                        self.i(format!("{y} W2,W2"));
                    }
                    let zero = self.fresh();
                    let done = self.fresh();
                    if b.as_const().is_none() {
                        self.i("cp0 W2");
                        self.bra("z", &zero);
                    }
                    self.i("repeat #17");
                    self.i(if signed { "div.sw W0,W2" } else { "div.uw W0,W2" });
                    if k == BinKind::Mod {
                        self.i("mov W1,W0");
                    }
                    if b.as_const().is_none() {
                        self.bra("", &done);
                        // A zero divisor gives the largest quotient and leaves the dividend as the remainder.
                        self.label(&zero);
                        if k == BinKind::Div {
                            self.i("setm W0");
                        }
                        self.label(&done);
                    }
                }
            }
            BinKind::Min | BinKind::Max => {
                self.operands(a, b);
                let l = self.fresh();
                let signed = a.signed;
                if s == 4 {
                    self.i("cp W0,W2");
                    self.i("cpb W1,W3");
                } else {
                    self.i(format!("cp{bw} W0,W2"));
                }
                // Keep W0 when it already is the wanted one.
                let keep = match (k, signed) {
                    (BinKind::Min, true) => "le",
                    (BinKind::Min, false) => "leu",
                    (_, true) => "ge",
                    (_, false) => "geu",
                };
                self.bra(keep, &l);
                self.i(if s == 4 { "mov.d W2,W0" } else { "mov W2,W0" });
                self.label(&l);
            }
        }
        self.norm(e);
    }

    fn shift(&mut self, k: BinKind, a: &Ex, b: &Ex, e: &Ex) {
        let s = sz(e.w);
        let left = k == BinKind::Shl;
        let signed = a.signed;
        if let Some(n) = b.as_const() {
            self.ev(a);
            if s == 1 && !left {
                self.i(if signed { "se W0,W0" } else { "ze W0,W0" });
            }
            if n == 0 {
                return;
            }
            match s {
                1 | 2 => {
                    let bits = if s == 1 { 8 } else { 16 };
                    if n >= bits {
                        if left || !signed {
                            self.i("clr W0");
                        } else {
                            self.i("asr W0,#15,W0");
                        }
                    } else if n < 16 {
                        let op = if left { "sl" } else if signed { "asr" } else { "lsr" };
                        self.i(format!("{op} W0,#{n},W0"));
                    }
                }
                _ => {
                    let n = n.min(32);
                    if left {
                        if n >= 16 {
                            if n == 32 {
                                self.i("clr W1");
                            } else if n == 16 {
                                self.i("mov W0,W1");
                            } else {
                                self.i(format!("sl W0,#{},W1", n - 16));
                            }
                            self.i("clr W0");
                        } else {
                            self.i(format!("sl W1,#{n},W1"));
                            self.i(format!("lsr W0,#{},W2", 16 - n));
                            self.i("ior W1,W2,W1");
                            self.i(format!("sl W0,#{n},W0"));
                        }
                    } else {
                        let op = if signed { "asr" } else { "lsr" };
                        if n >= 16 {
                            if n == 16 {
                                self.i("mov W1,W0");
                            } else if n < 32 {
                                self.i(format!("{op} W1,#{},W0", n - 16));
                            } else {
                                self.i(format!("{op} W1,#15,W0"));
                            }
                            if signed {
                                self.i("asr W1,#15,W1");
                            } else {
                                self.i("clr W1");
                            }
                        } else {
                            self.i(format!("lsr W0,#{n},W0"));
                            self.i(format!("sl W1,#{},W2", 16 - n));
                            self.i("ior W0,W2,W0");
                            self.i(format!("{op} W1,#{n},W1"));
                        }
                    }
                }
            }
            return self.norm(e);
        }
        // A count known only at run time: one place per pass.
        self.operands(a, b);
        if s == 1 && !left {
            self.i(if signed { "se W0,W0" } else { "ze W0,W0" });
        }
        if sz(b.w) == 1 {
            self.i("ze W2,W2");
        }
        let (top, end) = (self.fresh(), self.fresh());
        self.i("cp0 W2");
        self.bra("z", &end);
        self.label(&top);
        match (left, s) {
            (true, 4) => {
                self.i("sl W0,W0");
                self.i("rlc W1,W1");
            }
            (true, _) => self.i("sl W0,W0"),
            (false, 4) => {
                self.i(if signed { "asr W1,W1" } else { "lsr W1,W1" });
                self.i("rrc W0,W0");
            }
            (false, _) => self.i(if signed { "asr W0,W0" } else { "lsr W0,W0" }),
        }
        self.i("dec W2,W2");
        self.bra("nz", &top);
        self.label(&end);
        self.norm(e);
    }

    // ---- conditions -------------------------------------------------------------------------------------------

    fn cc(k: CmpKind, signed: bool) -> &'static str {
        match (k, signed) {
            (CmpKind::Eq, _) => "z",
            (CmpKind::Ne, _) => "nz",
            (CmpKind::Lt, true) => "lt",
            (CmpKind::Lt, false) => "ltu",
            (CmpKind::Gt, true) => "gt",
            (CmpKind::Gt, false) => "gtu",
            (CmpKind::Le, true) => "le",
            (CmpKind::Le, false) => "leu",
            (CmpKind::Ge, true) => "ge",
            (CmpKind::Ge, false) => "geu",
        }
    }

    /// Jumps to `t` when the condition equals `when`; otherwise falls through. Operands are only evaluated once.
    fn cond_jump(&mut self, c: &Ex, when: bool, t: &str) {
        match &c.k {
            ExK::Const(v) => {
                if (*v != 0) == when {
                    self.bra("", t);
                }
            }
            ExK::NotB(x) => self.cond_jump(x, !when, t),
            ExK::AndAlso(a, b) => {
                if when {
                    let skip = self.fresh();
                    self.cond_jump(a, false, &skip);
                    self.cond_jump(b, true, t);
                    self.label(&skip);
                } else {
                    self.cond_jump(a, false, t);
                    self.cond_jump(b, false, t);
                }
            }
            ExK::OrElse(a, b) => {
                if when {
                    self.cond_jump(a, true, t);
                    self.cond_jump(b, true, t);
                } else {
                    let skip = self.fresh();
                    self.cond_jump(a, true, &skip);
                    self.cond_jump(b, false, t);
                    self.label(&skip);
                }
            }
            ExK::Cmp(k, a, b) => {
                let s = sz(a.w).max(sz(b.w));
                let signed = a.signed || b.signed;
                let kind = if when { *k } else { k.negate() };
                match b.as_const() {
                    Some(v) if v < 32 && s < 4 => {
                        self.ev(a);
                        self.i(format!("cp{} W0,#{v}", if s == 1 { ".b" } else { "" }));
                    }
                    _ => {
                        self.operands(a, b);
                        if s == 4 {
                            self.i("cp W0,W2");
                            self.i("cpb W1,W3");
                        } else {
                            self.i(format!("cp{} W0,W2", if s == 1 { ".b" } else { "" }));
                        }
                    }
                }
                self.bra(Self::cc(kind, signed), t);
            }
            ExK::Load(pl) if pl.bit.is_some() => {
                let pl = &Self::byte_bit(pl);
                if let Some(a) = self.direct(pl, false) {
                    if let Some((fa, fb)) = Self::word_bit(a, pl.bit.unwrap()) {
                        // btsc skips the branch when the bit is clear.
                        self.i(format!("{} 0x{fa:X},#{fb}", if when { "btsc" } else { "btss" }));
                        self.bra("", t);
                        return;
                    }
                }
                self.ev(c);
                self.i("cp0.b W0");
                self.bra(if when { "nz" } else { "z" }, t);
            }
            _ => {
                self.ev(c);
                self.i("cp0.b W0");
                self.bra(if when { "nz" } else { "z" }, t);
            }
        }
    }

    // ---- statements -------------------------------------------------------------------------------------------

    /// Stores the value of `e` in `pl`.
    fn store(&mut self, pl: &Place, e: &Ex) {
        let pl = &Self::byte_bit(pl);
        if let Some(b) = pl.bit {
            if let Some(v) = e.as_const() {
                return self.set_bit(pl, b, v != 0);
            }
            // A run-time value: set or clear by its truth.
            let (clr, end) = (self.fresh(), self.fresh());
            self.cond_jump(e, false, &clr);
            self.set_bit(pl, b, true);
            self.bra("", &end);
            self.label(&clr);
            self.set_bit(pl, b, false);
            self.label(&end);
            return;
        }
        let n = pl.bytes();
        let indirect = pl.idx.is_some() || matches!(pl.base, Base::Ptr(_));
        if !indirect {
            self.ev(e);
            let acc = self.prep(pl, true);
            self.wr(acc, n, 0);
        } else if self.simple(e) {
            // The address first (it uses W0), then the value.
            let acc = self.prep(pl, true);
            self.ld_simple(e, 0);
            self.wr(acc, n, 0);
        } else {
            let s = sz(e.w);
            self.ev(e);
            self.push(s);
            let acc = self.prep(pl, true);
            self.pop(0, s);
            self.wr(acc, n, 0);
        }
    }

    fn set_bit(&mut self, pl: &Place, b: u8, v: bool) {
        let acc = self.prep(pl, true);
        self.bit_op(if v { "bset" } else { "bclr" }, acc, b);
    }

    fn add_const(&mut self, pl: &Place, d: u32) {
        let n = pl.bytes();
        let w = (n * 8) as u8;
        let d = d & crate::ir::mask(w);
        // Reads of a port come back from its latch.
        let mut rd = pl.clone();
        if let Base::Abs { addr, name } = &pl.base {
            let a = self.abs_addr(*addr, name, true);
            rd.base = Base::Abs { addr: a, name: name.clone() };
        }
        let signed = pl.signed();
        if let Some(a) = self.direct(pl, true) {
            if n <= 2 && a < NEAR && (n == 1 || a % 2 == 0) {
                let bw = if n == 1 { ".b" } else { "" };
                if d == 1 {
                    return self.i(format!("inc{bw} 0x{a:X}"));
                }
                if d == mask(w) {
                    return self.i(format!("dec{bw} 0x{a:X}"));
                }
            }
        }
        let ld = Ex::new(ExK::Load(rd), w, signed);
        let add = Ex::new(ExK::Bin(BinKind::Add, Box::new(ld), Box::new(Ex::konst(d, w, signed))), w, signed);
        self.store(pl, &add);
    }

    /// Calls `f`. The result is the code that restores the caller's frame when the call is a recursive one (the routine's
    /// frame is static, so the caller's variables are pushed before and popped after); the caller of this routine emits
    /// it once it has taken the result out of `W0`.
    fn call(&mut self, f: FuncId, args: &[(Place, Ex)]) -> Vec<String> {
        self.calls[self.cur].insert(f);
        if self.p.funcs[f].reg {
            // A register call (the Float library): the first operand in W1:W0, the second in W3:W2; the parameters are not stored.
            match args {
                [(_, a)] => self.ev(a),
                [(_, a), (_, b)] => self.operands(a, b),
                _ => self.err(format!("internal: a register-call routine `{}` with {} operands", self.p.funcs[f].name, args.len())),
            }
            let name = self.p.funcs[f].asm.clone();
            self.i(format!("rcall {name}"));
            return Vec::new();
        }
        if self.p.funcs[f].ext {
            self.err("calling C is not supported on the dsPIC33 yet");
            return Vec::new();
        }
        let recursive = self.cur < self.p.funcs.len() && self.isr_end.is_none() && self.reach[f].contains(&self.cur);
        let mut restore = Vec::new();
        if recursive {
            let frame: BTreeSet<VarId> = self.p.vars.iter().enumerate().filter(|(_, v)| v.owner == Some(self.cur)).map(|(i, _)| i).collect();
            let (save, rest) = self.frame_lines(&frame);
            for l in save {
                self.i(l);
            }
            restore = rest;
        }
        if recursive || args.iter().any(|(_, e)| e.has_call()) && args.len() > 1 {
            // Another call in an argument would overwrite the parameters already stored: hold the values on the stack.
            for (_, e) in args {
                self.ev(e);
                self.push(sz(e.w));
            }
            for (pl, e) in args.iter().rev() {
                let s = sz(e.w);
                self.pop(0, s);
                let acc = self.prep(pl, true);
                self.wr(acc, pl.bytes(), 0);
            }
        } else {
            for (pl, e) in args {
                self.store(pl, e);
            }
        }
        let name = self.p.funcs[f].asm.clone();
        self.i(format!("rcall {name}"));
        restore
    }

    fn block(&mut self, body: &[S]) {
        for s in body {
            self.stmt(s);
        }
    }

    fn zero_bytes(&mut self, pl: &Place, n: u32) {
        let acc = self.prep(pl, true);
        match acc {
            Acc::Direct(a) => self.i(format!("mov #0x{a:X},W3")),
            Acc::Reg { .. } => {}
            Acc::Prog { .. } => self.err("program memory cannot be written"),
        }
        if n > 1 {
            self.i(format!("repeat #{}", n - 1));
        }
        self.i("clr.b [W3++]");
    }

    fn stmt(&mut self, s: &S) {
        self.span = s.span;
        match &s.st {
            St::Assign(pl, e) => self.store(pl, e),
            St::Add(pl, d) => self.add_const(pl, *d),
            St::SetBit(pl, v) => {
                let pl = &Self::byte_bit(pl);
                self.set_bit(pl, pl.bit.unwrap(), *v)
            }
            St::ToggleBit(pl) => {
                let pl = &Self::byte_bit(pl);
                let acc = self.prep(pl, true);
                self.bit_op("btg", acc, pl.bit.unwrap());
            }
            St::Clear(pl) => {
                let pl = &Self::byte_bit(pl);
                if let Some(b) = pl.bit {
                    self.set_bit(pl, b, false);
                } else {
                    self.store(pl, &Ex::konst(0, pl.width(), false));
                }
            }
            St::ClearMem(pl, n) => self.zero_bytes(pl, *n),
            St::Copy { dst, src, bytes } => {
                // Source address on the stack while the destination's is made.
                let a = Ex::new(ExK::Addr(src.clone()), 16, false);
                self.ev(&a);
                self.i("push W0");
                let b = Ex::new(ExK::Addr(dst.clone()), 16, false);
                self.ev(&b);
                self.i("mov W0,W3");
                self.i("pop W2");
                if *bytes > 1 {
                    self.i(format!("repeat #{}", bytes - 1));
                }
                // A table in program memory is read with tblrdl, not as data.
                if matches!(src.base, Base::Flash(_)) {
                    self.i("tblrdl.b [W2++],[W3++]");
                } else {
                    self.i("mov.b [W2++],[W3++]");
                }
            }
            St::Direction { place, output } => {
                let Base::Abs { name, .. } = &place.base else {
                    self.err("Input/Output needs a port bit or a port");
                    return;
                };
                let Some(tris) = name.strip_prefix("PORT").or_else(|| name.strip_prefix("LAT")).and_then(|r| self.tgt.sfr.get(&format!("TRIS{r}")).copied()) else {
                    self.err(format!("`{name}` has no direction register"));
                    return;
                };
                let t = Place { base: Base::Abs { addr: tris, name: format!("TRIS{}", name.trim_start_matches("PORT").trim_start_matches("LAT")) }, ..place.clone() };
                let place = &Self::byte_bit(place);
                match place.bit {
                    Some(b) => {
                        let acc = Acc::Direct(tris + place.off);
                        self.bit_op(if *output { "bclr" } else { "bset" }, acc, b);
                    }
                    None => {
                        let v = if *output { 0 } else { u32::MAX };
                        let mut tp = t;
                        tp.ty = place.ty.clone();
                        self.store(&tp, &Ex::konst(v, place.width(), false));
                    }
                }
            }
            St::Call(f, args) => {
                let restore = self.call(*f, args);
                for l in restore {
                    self.i(l);
                }
            }
            St::FlashSeek(t, off, idx) => {
                let Some(tp) = self.tblp else {
                    self.need_tblp = true;
                    return;
                };
                let sym = self.p.flash[*t].asm.clone();
                if let Some(ix) = idx {
                    self.ev(ix);
                    if sz(ix.w) == 1 {
                        self.i("ze W0,W0");
                    }
                }
                self.i(format!("mov #tbloffset({sym}),W3"));
                if idx.is_some() {
                    self.i("add W0,W3,W3");
                }
                self.add_imm(3, *off);
                self.i(format!("mov W3,0x{tp:X}"));
            }
            St::StrSet { dst, cap, parts, keep } => self.str_set(dst, *cap, parts, *keep),
            St::If(arms, otherwise) => {
                let end = self.fresh();
                let mut done = false;
                for (i, (c, body)) in arms.iter().enumerate() {
                    if let Some(v) = c.as_const() {
                        if v != 0 {
                            self.block(body);
                            done = true;
                            break;
                        }
                        continue;
                    }
                    let last = i + 1 == arms.len() && otherwise.is_empty();
                    let next = self.fresh();
                    self.cond_jump(c, false, &next);
                    self.block(body);
                    if !last {
                        self.bra("", &end);
                    }
                    self.label(&next);
                }
                if !done {
                    self.block(otherwise);
                }
                self.label(&end);
            }
            St::While(c, body) => {
                let (top, cond, end) = (self.fresh(), self.fresh(), self.fresh());
                if c.as_const().is_some_and(|v| v != 0) {
                    self.label(&top);
                    self.loops.push((top.clone(), end.clone()));
                    self.block(body);
                    self.loops.pop();
                    self.bra("", &top);
                } else {
                    self.bra("", &cond);
                    self.label(&top);
                    self.loops.push((cond.clone(), end.clone()));
                    self.block(body);
                    self.loops.pop();
                    self.label(&cond);
                    self.cond_jump(c, true, &top);
                }
                self.label(&end);
            }
            St::Repeat(body, c) => {
                let (top, cont, end) = (self.fresh(), self.fresh(), self.fresh());
                self.label(&top);
                self.loops.push((cont.clone(), end.clone()));
                self.block(body);
                self.loops.pop();
                self.label(&cont);
                self.cond_jump(c, false, &top);
                self.label(&end);
            }
            St::For { var, from, limit, step, body, .. } => {
                let (w, sg) = (var.width(), var.signed());
                let (top, cont, end) = (self.fresh(), self.fresh(), self.fresh());
                self.store(var, from);
                self.label(&top);
                // Leave when the variable is past the limit.
                let v = Ex::new(ExK::Load(var.clone()), w, sg);
                let past = Ex::boolean(ExK::Cmp(if *step > 0 { CmpKind::Gt } else { CmpKind::Lt }, Box::new(v), Box::new(limit.clone())));
                self.cond_jump(&past, true, &end);
                self.loops.push((cont.clone(), end.clone()));
                self.block(body);
                self.loops.pop();
                self.label(&cont);
                // The variable keeps the last value it took: leave before the step that would pass the limit.
                let n = var.bytes();
                let mag = step.unsigned_abs() as u32 & crate::ir::mask(w);
                if mag == 1 {
                    let ld = Ex::new(ExK::Load(var.clone()), w, sg);
                    let at_end = Ex::boolean(ExK::Cmp(CmpKind::Eq, Box::new(ld), Box::new(limit.clone())));
                    self.cond_jump(&at_end, true, &end);
                    self.add_const(var, *step as u32);
                } else {
                    let ld = Ex::new(ExK::Load(var.clone()), w, sg);
                    self.ev(&ld);
                    let bw = if n == 1 { ".b" } else { "" };
                    let (o1, o2) = if *step > 0 { ("add", "addc") } else { ("sub", "subb") };
                    if mag < 1024 {
                        self.i(format!("{o1}{bw} #{mag},W0"));
                        if n > 2 {
                            self.i(format!("{o2} #0,W1"));
                        }
                    } else {
                        self.i(format!("mov #0x{:X},W2", mag & 0xFFFF));
                        if n > 2 {
                            self.i(format!("mov #0x{:X},W3", mag >> 16));
                        }
                        self.i(format!("{o1}{bw} W0,W2,W0"));
                        if n > 2 {
                            self.i(format!("{o2} W1,W3,W1"));
                        }
                    }
                    // A step that wraps around the end of the type leaves the loop too.
                    self.bra(if sg { "ov" } else if *step > 0 { "c" } else { "nc" }, &end);
                    let sz_ = sz(w);
                    if self.simple(limit) {
                        self.ld_simple(limit, 2);
                    } else {
                        self.push(sz_);
                        self.ev(limit);
                        self.to_second(sz_);
                        self.pop(0, sz_);
                    }
                    if sz_ == 4 {
                        self.i("cp W0,W2");
                        self.i("cpb W1,W3");
                    } else {
                        self.i(format!("cp{bw} W0,W2"));
                    }
                    self.bra(Self::cc(if *step > 0 { CmpKind::Gt } else { CmpKind::Lt }, sg), &end);
                    let acc = self.prep_keep_flags(var);
                    self.wr(acc, n, 0);
                }
                self.bra("", &top);
                self.label(&end);
            }
            St::Count { counter, count, body, step } => {
                let (top, cont, end) = (self.fresh(), self.fresh(), self.fresh());
                self.store(counter, &Ex::konst(*count as u32, 8, false));
                self.label(&top);
                self.loops.push((cont.clone(), end.clone()));
                self.block(body);
                self.loops.pop();
                self.label(&cont);
                self.add_const(counter, 0xFF);
                let cl = Ex::new(ExK::Load(counter.clone()), 8, false);
                if let Some((var, k)) = step {
                    self.cond_jump(&cl, false, &end);
                    self.add_const(var, *k);
                } else {
                    self.cond_jump(&cl, true, &top);
                    self.label(&end);
                    return;
                }
                self.bra("", &top);
                self.label(&end);
            }
            St::Break => {
                if let Some((_, end)) = self.loops.last().cloned() {
                    self.unwind_saves(self.loops.len());
                    self.bra("", &end);
                }
            }
            St::Continue => {
                if let Some((cont, _)) = self.loops.last().cloned() {
                    self.unwind_saves(self.loops.len());
                    self.bra("", &cont);
                }
            }
            St::Return => {
                self.unwind_saves(0);
                match self.isr_end.clone() {
                    Some(end) => self.bra("", &end),
                    None => self.i("return"),
                }
            }
            St::Int { on, .. } => {
                // GIE is bit 15 of INTCON2 (DS70005399D Register 7-4, p.95); the sources are enabled by their own IECx bits.
                match self.tgt.sfr.get("INTCON2") {
                    Some(a) => self.i(format!("{} 0x{a:X},#15", if *on { "bset" } else { "bclr" })),
                    None => self.err("the device has no INTCON2"),
                }
            }
            St::Save { items, body, .. } => self.save_block(items, body),
            St::Goto(l) => {
                let name = self.p.label_names[*l].clone();
                self.bra("", &name);
            }
            St::GoSub(l) => {
                let name = self.p.label_names[*l].clone();
                self.i(format!("rcall {name}"));
            }
            St::SubRet => self.i("return"),
            St::Label(l) => {
                let name = self.p.label_names[*l].clone();
                self.label(&name);
            }
            St::Asm(lines) => {
                for l in lines {
                    self.out.push(format!("        {}", l.trim()));
                }
            }
            St::DelayUs(e) => self.delay(e, false),
            St::DelayMs(e) => self.delay(e, true),
            St::Halt => self.bra("", "__halt"),
        }
    }

    /// The label of a string literal held in program memory, with its Null.
    fn lit(&mut self, bytes: &[u8]) -> String {
        let i = match self.lits.iter().position(|l| l == bytes) {
            Some(i) => i,
            None => {
                self.lits.push(bytes.to_vec());
                self.lits.len() - 1
            }
        };
        format!("__SL{i}")
    }

    /// The address of the first character of a string place, in `W0`.
    fn str_addr(&mut self, pl: &Place) {
        let a = Ex::new(ExK::Addr(pl.clone()), 16, false);
        self.ev(&a);
    }

    /// `dst = parts[0] + parts[1] + ...`, cut off after `cap` characters. The cursor is `W8` and the room left `W9`; the
    /// pair is kept on the stack while a part is worked out.
    fn str_set(&mut self, dst: &Place, cap: u32, parts: &[StrSrc], keep: bool) {
        self.uses_w8 = true;
        // A character may come from the string being assigned (`s = t + s(0)`): take them all before anything is written.
        let chars: Vec<&Ex> = parts.iter().skip(usize::from(keep)).filter_map(|p| if let StrSrc::Char(e) = p { Some(&**e) } else { None }).collect();
        for e in &chars {
            self.ev(e);
            self.i("push W0");
        }
        let mut next_char = 0usize;
        self.str_addr(dst);
        self.i("mov W0,W8");
        self.i(format!("mov #{cap},W9"));
        if keep {
            self.helpers.insert("sskip");
            self.i("rcall __sskip");
        }
        for part in parts.iter().skip(usize::from(keep)) {
            match part {
                StrSrc::Ram(pl) => {
                    self.i("push.d W8");
                    self.str_addr(pl);
                    self.i("mov W0,W2");
                    self.i("pop.d W8");
                    self.helpers.insert("sapp_ram");
                    self.i("rcall __sapp_ram");
                }
                StrSrc::Lit(bytes) => {
                    if bytes.is_empty() {
                        continue;
                    }
                    let l = self.lit(bytes);
                    self.i(format!("mov #tbloffset({l}),W2"));
                    self.helpers.insert("sapp_lit");
                    self.i("rcall __sapp_lit");
                }
                StrSrc::Char(_) => {
                    // The value taken above sits on the stack, the later ones above it.
                    self.i(format!("mov [W15-{}],W0", 2 * (chars.len() - next_char)));
                    next_char += 1;
                    let skip = self.fresh();
                    self.i("cp0 W9");
                    self.bra("z", &skip);
                    self.i("mov.b W0,[W8++]");
                    self.i("dec W9,W9");
                    self.label(&skip);
                }
                StrSrc::Cat { .. } => self.err("a concatenation here is not supported on the dsPIC33 yet"),
            }
        }
        self.i("clr.b [W8]");
        if !chars.is_empty() {
            self.i(format!("sub #{},W15", 2 * chars.len()));
        }
    }

    /// `a = b` on strings: 1 in `W0` when they are equal.
    fn str_eq(&mut self, a: &StrSrc, b: &StrSrc) {
        let Some(pa) = self.str_place(a) else { return };
        self.str_addr(&pa);
        self.i("push W0");
        match b {
            StrSrc::Lit(bytes) => {
                let l = self.lit(bytes);
                self.i("pop W2");
                self.i(format!("mov #tbloffset({l}),W3"));
                self.helpers.insert("seq_lit");
                self.i("rcall __seq_lit");
            }
            other => {
                let Some(pb) = self.str_place(other) else { return };
                self.str_addr(&pb);
                self.i("mov W0,W3");
                self.i("pop W2");
                self.helpers.insert("seq_ram");
                self.i("rcall __seq_ram");
            }
        }
    }

    /// The place of a string source that is held in RAM; a concatenation is built into its hidden string first.
    fn str_place(&mut self, src: &StrSrc) -> Option<Place> {
        match src {
            StrSrc::Ram(pl) => Some(pl.clone()),
            StrSrc::Cat { tmp, parts } => {
                let cap = match tmp.ty {
                    crate::types::Ty::Str(n) => n,
                    _ => 0,
                };
                self.str_set(tmp, cap, parts, false);
                Some(tmp.clone())
            }
            _ => {
                self.err("a string comparison with a character is not supported on the dsPIC33 yet");
                None
            }
        }
    }

    /// Restores the `Save` blocks a jump leaves: those opened at loop depth `min_loops` or deeper.
    fn unwind_saves(&mut self, min_loops: usize) {
        let lists: Vec<Vec<String>> = self.saves.iter().rev().filter(|(l, _)| *l >= min_loops).map(|(_, r)| r.clone()).collect();
        for r in lists {
            for l in r {
                self.i(l);
            }
        }
    }

    /// `Save(items) ... Restore`: the bytes of the named variables and of the frames of the routines named, and (inside an
    /// interrupt handler) of every routine the block calls, are pushed on the stack and popped after the block. The
    /// working registers are kept by the handler's own entry code, so `Save(0)` adds nothing.
    fn save_block(&mut self, items: &[SaveIt], body: &[S]) {
        let mut roots: BTreeSet<FuncId> = BTreeSet::new();
        let mut vars: BTreeSet<VarId> = BTreeSet::new();
        for it in items {
            match it {
                SaveIt::Func(f) => {
                    roots.insert(*f);
                }
                SaveIt::Var(v) => {
                    vars.insert(*v);
                }
                SaveIt::Regs => {}
            }
        }
        if self.isr_end.is_some() {
            crate::codegen::stmt_calls(body, &mut roots);
            let mut lines = Vec::new();
            crate::opt::collect_asm(body, &mut lines);
            for l in lines {
                for tok in l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).filter(|t| !t.is_empty()) {
                    if let Some(f) = self.p.funcs.iter().position(|f| f.asm == tok) {
                        roots.insert(f);
                    }
                }
            }
        }
        // The frames of the roots and of everything they call.
        let mut all: BTreeSet<FuncId> = BTreeSet::new();
        let mut stack: Vec<FuncId> = roots.into_iter().collect();
        while let Some(f) = stack.pop() {
            if f < self.p.funcs.len() && all.insert(f) {
                let mut c = BTreeSet::new();
                crate::codegen::stmt_calls(&self.p.funcs[f].body, &mut c);
                stack.extend(c);
            }
        }
        for (i, v) in self.p.vars.iter().enumerate() {
            if v.owner.is_some_and(|o| all.contains(&o)) {
                vars.insert(i);
            }
        }
        let (save, ordered) = self.frame_lines(&vars);
        for l in &save {
            self.i(l);
        }
        self.saves.push((self.loops.len(), ordered.clone()));
        self.block(body);
        self.saves.pop();
        for l in ordered {
            self.i(l);
        }
    }

    /// The code that pushes the bytes of the variables on the stack, and the code that pops them back (in the opposite
    /// order). A word at a time, then a last odd byte as a byte; `W4` and `W5` are the scratch registers, so a value in
    /// `W0:W1` survives the restore.
    fn frame_lines(&self, vars: &BTreeSet<VarId>) -> (Vec<String>, Vec<String>) {
        let mut parts: Vec<(u32, bool)> = Vec::new();
        for &v in vars {
            let (a, n) = (self.addr[v], self.p.vars[v].bytes);
            let mut k = 0;
            while k < n {
                if n - k >= 2 && (a + k) % 2 == 0 {
                    parts.push((a + k, true));
                    k += 2;
                } else {
                    parts.push((a + k, false));
                    k += 1;
                }
            }
        }
        let mut save = Vec::new();
        for &(a, word) in &parts {
            if word {
                save.push(format!("mov 0x{a:X},W4"));
            } else {
                save.push(format!("mov #0x{a:X},W4"));
                save.push("mov.b [W4],W4".to_string());
            }
            save.push("push W4".to_string());
        }
        let mut restore = Vec::new();
        for &(a, word) in parts.iter().rev() {
            restore.push("pop W4".to_string());
            if word {
                restore.push(format!("mov W4,0x{a:X}"));
            } else {
                restore.push(format!("mov #0x{a:X},W5"));
                restore.push("mov.b W4,[W5]".to_string());
            }
        }
        (save, restore)
    }

    /// The address of `pl` for a store that must not change the flags the loop test reads: a direct place needs no code.
    fn prep_keep_flags(&mut self, pl: &Place) -> Acc {
        if pl.idx.is_none() && !matches!(pl.base, Base::Ptr(_)) {
            return self.prep(pl, true);
        }
        self.err("a loop variable that is an array element or a ByRef parameter is not supported on the dsPIC33 yet");
        Acc::Direct(0)
    }

    // ---- delays -----------------------------------------------------------------------------------------------

    /// Cycles of `Fcy` in `per` seconds.
    fn cycles(&self, per: f64) -> u64 {
        (self.fcy * per).round() as u64
    }

    fn spin(&mut self, cycles: u64) {
        // `repeat #n; nop` takes n + 2 cycles; a loop of four-cycle passes handles longer waits.
        if cycles == 0 {
            return;
        }
        if cycles <= 16383 + 2 {
            if cycles >= 3 {
                self.i(format!("repeat #{}", cycles - 2));
                self.i("nop");
            } else {
                for _ in 0..cycles {
                    self.i("nop");
                }
            }
            return;
        }
        let n = (cycles - 1) / 4;
        let rem = (cycles - 1) % 4;
        self.i(format!("mov #0x{:X},W0", n & 0xFFFF));
        self.i(format!("mov #0x{:X},W1", n >> 16));
        let l = self.fresh();
        self.label(&l);
        self.i("sub #1,W0");
        self.i("subb #0,W1");
        self.bra("nz", &l);
        for _ in 0..rem {
            self.i("nop");
        }
    }

    fn delay(&mut self, e: &Ex, ms: bool) {
        let per = if ms { 1e-3 } else { 1e-6 };
        if let Some(v) = e.as_const() {
            if self.fcy == 0.0 {
                self.err("DelayUs/DelayMs need a `Clock = MHz` line");
                return;
            }
            self.spin(self.cycles(per) * v as u64);
            return;
        }
        if self.fcy == 0.0 {
            self.err("DelayUs/DelayMs need a `Clock = MHz` line");
            return;
        }
        self.ev(e);
        if sz(e.w) == 1 {
            self.i("ze W0,W0");
        }
        self.helpers.insert(if ms { "dly_ms" } else { "dly_us" });
        self.i(format!("rcall __dly_{}", if ms { "ms" } else { "us" }));
    }

    fn helper_code(&mut self) {
        if self.helpers.contains("sdiv32") {
            self.helpers.insert("udiv32");
        }
        let helpers: Vec<&'static str> = self.helpers.iter().copied().collect();
        for h in helpers {
            let lines: Vec<String> = match h {
                "udiv32" => [
                    "__udiv32:", "        clr W4", "        clr W5", "        mov #32,W6", "1:      sl W0,W0", "        rlc W1,W1", "        rlc W4,W4", "        rlc W5,W5",
                    "        cp W4,W2", "        cpb W5,W3", "        bra ltu,2f", "        sub W4,W2,W4", "        subb W5,W3,W5", "        bset W0,#0",
                    "2:      dec W6,W6", "        bra nz,1b", "        return",
                ]
                .iter()
                .map(|l| l.to_string())
                .collect(),
                "sdiv32" => [
                    "__sdiv32:", "        clr W7", "        btss W1,#15", "        bra 1f", "        com W0,W0", "        com W1,W1", "        add #1,W0", "        addc #0,W1",
                    "        mov #3,W7", "1:      btss W3,#15", "        bra 2f", "        com W2,W2", "        com W3,W3", "        add #1,W2", "        addc #0,W3",
                    "        btg W7,#0", "2:      rcall __udiv32", "        btss W7,#0", "        bra 3f", "        com W0,W0", "        com W1,W1", "        add #1,W0",
                    "        addc #0,W1", "3:      btss W7,#1", "        return", "        com W4,W4", "        com W5,W5", "        add #1,W4", "        addc #0,W5",
                    "        return",
                ]
                .iter()
                .map(|l| l.to_string())
                .collect(),
                "sskip" => ["__sskip:", "1:      cp0 W9", "        bra z,2f", "        mov.b [W8],W0", "        cp0.b W0", "        bra z,2f", "        inc W8,W8", "        dec W9,W9", "        bra 1b", "2:      return"]
                    .iter()
                    .map(|l| l.to_string())
                    .collect(),
                "sapp_ram" | "sapp_lit" => {
                    let rd = if h == "sapp_ram" { "mov.b [W2++],W0" } else { "tblrdl.b [W2++],W0" };
                    vec![format!("__{h}:"), "1:      cp0 W9".into(), "        bra z,2f".into(), format!("        {rd}"), "        cp0.b W0".into(), "        bra z,2f".into(), "        mov.b W0,[W8++]".into(), "        dec W9,W9".into(), "        bra 1b".into(), "2:      return".into()]
                }
                "seq_ram" | "seq_lit" => {
                    let rd = if h == "seq_ram" { "mov.b [W3++],W1" } else { "tblrdl.b [W3++],W1" };
                    vec![
                        format!("__{h}:"),
                        "1:      mov.b [W2++],W0".into(),
                        format!("        {rd}"),
                        "        cp.b W0,W1".into(),
                        "        bra nz,3f".into(),
                        "        cp0.b W0".into(),
                        "        bra nz,1b".into(),
                        "        mov #1,W0".into(),
                        "        return".into(),
                        "3:      clr W0".into(),
                        "        return".into(),
                    ]
                }
                "dly_ms" | "dly_us" => {
                    let ms = h == "dly_ms";
                    let per = self.cycles(if ms { 1e-3 } else { 1e-6 });
                    let mut v: Vec<String> = vec![format!("__{h}:"), "        cp0 W0".into(), "        bra z,2f".into(), "1:".into()];
                    if ms {
                        // A millisecond is a count of four-cycle passes less the loop's own cost.
                        let n = per.saturating_sub(8) / 4;
                        v.push("        push W0".into());
                        v.push(format!("        mov #0x{:X},W0", n & 0xFFFF));
                        v.push(format!("        mov #0x{:X},W1", n >> 16));
                        v.push("3:      sub #1,W0".into());
                        v.push("        subb #0,W1".into());
                        v.push("        bra nz,3b".into());
                        v.push("        pop W0".into());
                    } else if per > 5 {
                        // dec and bra take 3 cycles when the branch is taken.
                        v.push(format!("        repeat #{}", per - 5));
                        v.push("        nop".into());
                    } else {
                        for _ in 3..per {
                            v.push("        nop".into());
                        }
                    }
                    v.push("        dec W0,W0".into());
                    v.push("        bra nz,1b".into());
                    v.push("2:      return".into());
                    v
                }
                _ => vec![],
            };
            self.out.extend(lines);
        }
    }
}

pub fn generate(p: &Program, tgt: &Target) -> Generated {
    let (g, need) = generate_with(p, tgt, false);
    if !need {
        return g;
    }
    // The program steps through a table: give the table pointer a word of RAM and generate again.
    generate_with(p, tgt, true).0
}

fn generate_with(p: &Program, tgt: &Target, want_tblp: bool) -> (Generated, bool) {
    let mem = tgt.dspic.as_ref().expect("the dsPIC33 generator needs the dsPIC33 memory description");
    let nf = p.funcs.len();
    let fail = |errors: Vec<(Span, String)>| {
        (
            Generated {
                out: Output { text: String::new(), words: 0, labels: HashMap::default(), func_words: vec![] },
                stack_levels: 0,
                objs: vec![],
                layout: Layout::default(),
                errors,
                debug: Default::default(),
            },
            false,
        )
    };
    if p.c_link() {
        return fail(vec![(Span::default(), "calling C (CFile, Extern, Export) is not supported on the dsPIC33 yet".into())]);
    }

    // Data layout: variables in order from the start of RAM; anything of two bytes or more on an even address.
    let mut addr = Vec::new();
    let mut objs = Vec::new();
    let mut at = mem.ram.0;
    for v in &p.vars {
        if v.bytes >= 2 || matches!(v.ty, crate::types::Ty::Array(..) | crate::types::Ty::Struct(..)) {
            at = (at + 1) & !1;
        }
        addr.push(at);
        objs.push(Obj { name: v.asm.clone(), bytes: v.bytes, weight: 0, force_access: false, zero: true, owner: v.owner });
        at += v.bytes;
    }
    at = (at + 1) & !1;
    let tblp = want_tblp.then(|| {
        let a = at;
        at += 2;
        addr.push(a);
        objs.push(Obj { name: "__tblp".into(), bytes: 2, weight: 0, force_access: false, zero: true, owner: None });
        a
    });
    let stack_base = at;
    // Which routines each routine can reach: a call from a routine to one that reaches it again is a recursive call.
    let direct: Vec<BTreeSet<FuncId>> = p
        .funcs
        .iter()
        .map(|f| {
            let mut c = BTreeSet::new();
            crate::codegen::stmt_calls(&f.body, &mut c);
            let mut lines = Vec::new();
            crate::opt::collect_asm(&f.body, &mut lines);
            for l in lines {
                for tok in l.split(|ch: char| !(ch.is_ascii_alphanumeric() || ch == '_')).filter(|t| !t.is_empty()) {
                    if let Some(g) = p.funcs.iter().position(|x| x.asm == tok) {
                        c.insert(g);
                    }
                }
            }
            c
        })
        .collect();
    let reach: Vec<BTreeSet<FuncId>> = (0..nf)
        .map(|f| {
            let mut seen = BTreeSet::new();
            let mut stack: Vec<FuncId> = direct[f].iter().copied().collect();
            while let Some(x) = stack.pop() {
                if seen.insert(x) {
                    stack.extend(direct[x].iter().copied());
                }
            }
            seen
        })
        .collect();
    let mut g = G {
        p,
        tgt,
        out: Vec::new(),
        lbl: 0,
        loops: Vec::new(),
        errors: Vec::new(),
        addr: addr.clone(),
        span: Span::default(),
        helpers: BTreeSet::new(),
        fcy: p.clock_mhz * 1e6 / 2.0,
        calls: vec![BTreeSet::new(); nf + 1],
        reach,
        cur: nf,
        isr_end: None,
        tblp,
        need_tblp: false,
        lits: Vec::new(),
        uses_w8: false,
        saves: Vec::new(),
    };
    let mut func_words: Vec<(String, u32)> = Vec::new();
    let count = |lines: &[String]| lines.iter().filter(|l| l.starts_with("        ") && !l.trim_start().starts_with('.') && !l.trim().is_empty()).count() as u32;

    // Start-up: stack, stack limit, zeroed RAM, initial values; then the program body.
    g.out.push(format!("; basil output for {}", p.device));
    g.out.push("        .text".into());
    g.out.push("        .global __reset".into());
    g.out.push("__reset:".into());
    g.i(format!("mov #0x{stack_base:X},W15"));
    g.i(format!("mov #0x{:X},W0", mem.ram.1 - 2));
    match tgt.sfr.get("SPLIM") {
        Some(a) => g.i(format!("mov W0,0x{a:X}")),
        None => g.errors.push((Span::default(), "the device description has no SPLIM".into())),
    }
    if at > mem.ram.0 {
        let words = (at - mem.ram.0).div_ceil(2);
        g.i(format!("mov #0x{:X},W0", mem.ram.0));
        // `repeat` counts to 16383; RAM is 4 K words.
        g.i(format!("repeat #{}", words - 1));
        g.i("clr [W0++]");
    }
    for (i, v) in p.vars.iter().enumerate() {
        if let (Some(init), VarKind::Global) = (v.init, v.kind) {
            for k in 0..v.bytes.min(4) {
                let b = (init >> (8 * k)) & 0xFF;
                if b != 0 {
                    g.i(format!("mov #0x{b:X},W0"));
                    g.i(format!("mov.b WREG,0x{:X}", addr[i] + k));
                }
            }
        }
    }
    g.span = p.main.span;
    g.cur = nf;
    g.block(&p.main.body);
    g.out.push("        .global __halt".into());
    g.out.push("__halt:".into());
    g.bra("", "__halt");
    func_words.push(("(start-up and program body)".into(), count(&g.out)));
    let mut before = count(&g.out);
    let isr_set: BTreeSet<FuncId> = p.isrs.iter().map(|x| x.0).collect();
    for (fi, f) in p.funcs.iter().enumerate() {
        if isr_set.contains(&fi) {
            continue;
        }
        g.cur = fi;
        g.span = f.span;
        g.out.push(format!("{}:", f.asm));
        g.block(&f.body);
        g.i("return");
        let now = count(&g.out);
        func_words.push((f.asm.clone(), now - before));
        before = now;
    }
    // Interrupt handlers: the linker script's vector table names `__<Source>Interrupt`.
    for &(f, _) in &p.isrs {
        let func = &p.funcs[f];
        let Some(src) = mem.vectors.iter().find(|v| v.eq_ignore_ascii_case(&func.name)) else {
            g.errors.push((func.span, format!("`{}` is not an interrupt source of this part: name the handler after the source (T1, INT0, U1RX, ...; see the IFSx registers)", func.name)));
            continue;
        };
        g.cur = f;
        g.span = func.span;
        let end = g.fresh();
        g.isr_end = Some(end.clone());
        g.out.push(format!("        .global __{src}Interrupt"));
        g.out.push(format!("__{src}Interrupt:"));
        // The body first, to learn whether the string cursor registers need saving.
        let outer = std::mem::take(&mut g.out);
        g.block(&func.body);
        g.label(&end);
        let body = std::mem::replace(&mut g.out, outer);
        // Everything the generated code uses: W0-W7 (W8 and W9 with strings), the flags and the repeat counter.
        let w8 = g.uses_w8;
        for l in ["push.d W0", "push.d W2", "push.d W4", "push.d W6", "push SR", "push RCOUNT"] {
            g.i(l);
        }
        if w8 {
            g.i("push.d W8");
        }
        g.out.extend(body);
        if w8 {
            g.i("pop.d W8");
        }
        for l in ["pop RCOUNT", "pop SR", "pop.d W6", "pop.d W4", "pop.d W2", "pop.d W0", "retfie"] {
            g.i(l);
        }
        g.isr_end = None;
        let now = count(&g.out);
        func_words.push((func.asm.clone(), now - before));
        before = now;
    }
    g.helper_code();

    // Constant tables and string literals follow the code: two bytes to a program word (its low 16 bits).
    let mut data: Vec<String> = Vec::new();
    let words_of = |label: &str, bytes: &[u8], nul: bool, data: &mut Vec<String>| {
        data.push(format!("{label}:"));
        let mut b = bytes.to_vec();
        if nul {
            b.push(0);
        }
        for pair in b.chunks(2) {
            let hi = pair.get(1).copied().unwrap_or(0);
            data.push(format!("        .word 0x{:02X}{:02X}", hi, pair[0]));
        }
    };
    for t in &p.flash {
        words_of(&t.asm, &t.bytes, false, &mut data);
    }
    let lits = g.lits.clone();
    for (i, l) in lits.iter().enumerate() {
        words_of(&format!("__SL{i}"), l, true, &mut data);
    }
    g.out.extend(data);
    if let Some(t) = g.tblp {
        g.out.insert(1, format!("        .equ __tblp, 0x{t:X}"));
    }

    // Variables as constants, the stack, and the configuration words.
    let mut text = String::new();
    let mut head: Vec<String> = Vec::new();
    for (i, v) in p.vars.iter().enumerate() {
        head.push(format!("        .equ {}, 0x{:X}    ; {} ({} bytes)", v.asm, addr[i], v.name, v.bytes));
    }
    let mut cfg = Vec::new();
    for (name, _addr, value) in &p.config {
        cfg.push(format!("        .section __{name}.sec,code\n        .global __{name}\n__{name}:\n        .pword 0x{:06X}", 0xFF0000 | u32::from(*value)));
    }
    let first = g.out.remove(0);
    text.push_str(&first);
    text.push('\n');
    text.push_str(&head.join("\n"));
    text.push('\n');
    text.push_str(&g.out.join("\n"));
    text.push('\n');
    text.push_str(&cfg.join("\n"));
    text.push('\n');
    let words = count(&g.out);
    let mut errors = g.errors;
    if errors.is_empty() && words > mem.prog_words {
        errors.push((Span::default(), format!("the program needs {} words of program memory but the device has {}", words, mem.prog_words)));
    }
    if errors.is_empty() && stack_base + 32 > mem.ram.1 {
        errors.push((Span::default(), format!("out of data RAM: the variables need {} bytes", stack_base - mem.ram.0)));
    }
    let mut size: Vec<u32> = p.vars.iter().map(|v| v.bytes).collect();
    if tblp.is_some() {
        size.push(2);
    }
    let need = g.need_tblp;
    (
        Generated {
            out: Output { text, words, labels: HashMap::default(), func_words },
            stack_levels: 0,
            objs,
            layout: Layout { addr: addr.into_iter().map(Some).collect(), size },
            errors,
            debug: Default::default(),
        },
        need,
    )
}
