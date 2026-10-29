//! Multiply and divide routines, written as instruction lists.
//!
//! Calling convention: the first operand is in `A`, the second in `B` (n bytes each, little endian). The
//! result comes back in `A`; division also leaves the remainder in `C`. `C` and `D0` are working storage.

use super::*;
use crate::asm::Cc;

impl<'p> G<'p> {
    pub fn emit_helper(&mut self, name: &str) {
        let n: u32 = name[name.len() - 1..].parse().expect("helper names end in a digit");
        self.depth = 0;
        self.bsr = None;
        self.label(&format!("__{name}"));
        match &name[..name.len() - 1] {
            "mul" => self.mul_helper(n),
            "udiv" => self.udiv_helper(n),
            "sdiv" => self.sdiv_helper(n),
            "strs" => self.str_append_helper(),
            "strc" => self.str_char_helper(),
            "stre" => self.str_end_helper(),
            "strq" => self.str_eq_helper(),
            _ => self.err(format!("unknown helper {name}")),
        }
    }

    fn shl_reg(&mut self, r: usize, n: u32) {
        for i in 0..n {
            let m = self.scr(r, i);
            self.ins(format!("{} {}, f", if i == 0 { "lslf" } else { "rlf" }, m.text()));
        }
    }

    /// A = A * B (low n bytes), shift-and-add over the bits of B.
    fn mul_helper(&mut self, n: u32) {
        let d0 = self.d(0);
        for i in 0..n {
            let c = self.c(i);
            self.fo("clrf", &c);
        }
        self.ins(format!("movlw {}", 8 * n));
        self.fo("movwf", &d0);
        let (lp, skip) = (self.fresh(), self.fresh());
        self.label(&lp);
        // The low bit of B, shifted out into carry.
        for i in (0..n).rev() {
            let b = self.b(i);
            self.ins(format!("{} {}, f", if i == n - 1 { "lsrf" } else { "rrf" }, b.text()));
        }
        self.br(Cc::Nc, &skip);
        for i in 0..n {
            let (a, c) = (self.a(i), self.c(i));
            self.fop("movf", &a, "w");
            self.fop(if i == 0 { "addwf" } else { "addwfc" }, &c, "f");
        }
        self.label(&skip);
        self.shl_reg(0, n);
        self.items.push(Item::SkipBr(format!("decfsz {}, f", d0.text()), lp));
        for i in 0..n {
            let (a, c) = (self.a(i), self.c(i));
            self.fop("movf", &c, "w");
            self.fo("movwf", &a);
        }
        self.ins("return");
    }

    /// A = A / B, C = A mod B, unsigned (restoring division). B = 0 gives A = all ones, C = A.
    fn udiv_helper(&mut self, n: u32) {
        let d0 = self.d(0);
        for i in 0..n {
            let c = self.c(i);
            self.fo("clrf", &c);
        }
        self.ins(format!("movlw {}", 8 * n));
        self.fo("movwf", &d0);
        let (lp, nosub) = (self.fresh(), self.fresh());
        self.label(&lp);
        // C:A <<= 1 (the top bit of A moves into C).
        self.shl_reg(0, n);
        for i in 0..n {
            let c = self.c(i);
            self.ins(format!("rlf {}, f", c.text()));
        }
        // C >= B ?  (carry set when no borrow)
        for i in 0..n {
            let (b, c) = (self.b(i), self.c(i));
            self.fop("movf", &b, "w");
            self.fop(if i == 0 { "subwf" } else { "subwfb" }, &c, "w");
        }
        self.br(Cc::Nc, &nosub);
        for i in 0..n {
            let (b, c) = (self.b(i), self.c(i));
            self.fop("movf", &b, "w");
            self.fop(if i == 0 { "subwf" } else { "subwfb" }, &c, "f");
        }
        let a0 = self.a(0);
        self.ins(format!("bsf {}, 0", a0.text()));
        self.label(&nosub);
        self.items.push(Item::SkipBr(format!("decfsz {}, f", d0.text()), lp));
        self.ins("return");
    }

    /// Signed division: the quotient takes the sign of A xor B, the remainder the sign of A (C code semantics).
    fn sdiv_helper(&mut self, n: u32) {
        // D1 bit 0: A was negative; bit 1: the signs differ.
        let d1 = self.d(1);
        self.fo("clrf", &d1);
        let (pa, pb) = (self.fresh(), self.fresh());
        let top_a = self.a(n - 1);
        // Negative A: remember it and negate. The jump is taken when the sign bit is clear.
        self.items.push(Item::SkipBr(format!("btfss {}, 7", top_a.text()), pa.clone()));
        self.fbit("bsf", &d1, 0);
        self.fbit("bsf", &d1, 1);
        self.neg_reg(0, n);
        self.label(&pa);
        let top_b = self.b(n - 1);
        self.items.push(Item::SkipBr(format!("btfss {}, 7", top_b.text()), pb.clone()));
        self.ins("movlw 2");
        self.fop("xorwf", &d1, "f");
        self.neg_reg(1, n);
        self.label(&pb);
        self.helpers.insert(format!("udiv{n}"));
        self.call(&format!("__udiv{n}"));
        let (q, r) = (self.fresh(), self.fresh());
        self.fbit("btfss", &d1, 1);
        self.br(Cc::Always, &q);
        self.neg_reg(0, n);
        self.label(&q);
        self.fbit("btfss", &d1, 0);
        self.br(Cc::Always, &r);
        self.neg_reg(2, n);
        self.label(&r);
        self.ins("return");
    }

    fn neg_reg(&mut self, r: usize, n: u32) {
        for i in 0..n {
            let m = self.scr(r, i);
            self.ins(format!("comf {}, f", m.text()));
        }
        let m0 = self.scr(r, 0);
        self.ins(format!("incf {}, f", m0.text()));
        for i in 1..n {
            let m = self.scr(r, i);
            self.ins("btfsc STATUS, 2");
            self.ins(format!("incf {}, f", m.text()));
        }
    }

    // ---- strings --------------------------------------------------------------------------------
    //
    // FSR0 is the destination (or the left string), FSR1 the source (RAM, or program memory with bit 7 of FSR1H
    // set: both read through `moviw`), `D2` the room left in the destination (the multiply, divide and shift routines that an index may need use D0 and D1).

    /// Appends the string at FSR1 to the one at FSR0 (stopping when D0 reaches zero) and Null-terminates it.
    fn str_append_helper(&mut self) {
        let (lp, done) = (self.fresh(), self.fresh());
        let d0 = self.d(2);
        self.label(&lp);
        self.fop("movf", &d0, "f");
        self.br(Cc::Z, &done);
        self.ins("moviw FSR1++");
        self.br(Cc::Z, &done);
        self.ins("movwi FSR0++");
        self.fop("decf", &d0, "f");
        self.br(Cc::Always, &lp);
        self.label(&done);
        self.ins("clrw");
        self.ins("movwi 0[FSR0]");
        self.ins("return");
    }

    /// Appends the character in WREG (unless it is Null or the room is gone) and Null-terminates.
    fn str_char_helper(&mut self) {
        let done = self.fresh();
        let d0 = self.d(2);
        self.ins("iorlw 0");
        self.br(Cc::Z, &done);
        self.fop("movf", &d0, "f");
        self.br(Cc::Z, &done);
        self.ins("movwi FSR0++");
        self.fop("decf", &d0, "f");
        self.label(&done);
        self.ins("clrw");
        self.ins("movwi 0[FSR0]");
        self.ins("return");
    }

    /// Moves FSR0 to the Null of the string it points at, or as far as D0 allows.
    fn str_end_helper(&mut self) {
        let (lp, done) = (self.fresh(), self.fresh());
        let d0 = self.d(2);
        self.label(&lp);
        self.ins("moviw 0[FSR0]");
        self.br(Cc::Z, &done);
        self.fop("movf", &d0, "f");
        self.br(Cc::Z, &done);
        self.ins("addfsr FSR0, 1");
        self.fop("decf", &d0, "f");
        self.br(Cc::Always, &lp);
        self.label(&done);
        self.ins("return");
    }

    /// WREG = 1 when the strings at FSR0 and FSR1 are equal.
    fn str_eq_helper(&mut self) {
        let (lp, ne) = (self.fresh(), self.fresh());
        let d0 = self.d(0);
        self.label(&lp);
        self.ins("moviw FSR1++");
        self.fo("movwf", &d0);
        self.ins("moviw FSR0++");
        self.fop("xorwf", &d0, "w");
        self.br(Cc::Nz, &ne);
        self.fop("movf", &d0, "f");
        self.br(Cc::Nz, &lp);
        self.ins("retlw 1");
        self.label(&ne);
        self.ins("retlw 0");
    }
}
