//! Instruction emitters: banking, memory operands, bytes moved through WREG.

use super::*;
use crate::asm::Cc;

impl<'p> G<'p> {
    pub fn ins(&mut self, s: impl Into<String>) {
        self.items.push(Item::Ins(s.into()));
    }

    pub fn label(&mut self, l: &str) {
        self.items.push(Item::Label(l.to_string()));
        self.bsr = None;
    }

    pub fn fresh(&mut self) -> String {
        self.lbl += 1;
        format!("_L{}", self.lbl)
    }

    pub fn br(&mut self, cc: Cc, l: &str) {
        self.items.push(Item::Br(cc, l.to_string()));
    }

    /// A call: the callee may select any bank.
    pub fn call(&mut self, l: &str) {
        self.items.push(Item::Call(l.to_string()));
        self.bsr = None;
    }

    // ---- memory ---------------------------------------------------------------------------

    fn layout_addr(&self, obj: usize) -> Option<u32> {
        self.layout.and_then(|l| l.addr[obj])
    }

    /// Byte `off` of the program object `obj` (a variable, scratch register or temporary area).
    pub fn obj_mem(&mut self, obj: usize, sym: String, off: u32) -> Mem {
        self.uses[obj] += weight(self.depth);
        Mem { sym, base: self.layout_addr(obj), off, lin: true }
    }

    pub fn var_mem(&mut self, v: VarId, off: u32) -> Mem {
        let sym = self.p.vars[v].asm.clone();
        self.obj_mem(v, sym, off)
    }

    /// Byte `k` of scratch register `A`, `B`, `C` or `D`.
    pub fn scr(&mut self, r: usize, k: u32) -> Mem {
        self.scratch_max[r] = self.scratch_max[r].max(k + 1);
        let obj = self.nvars + r;
        let base = self.layout_addr(obj);
        Mem { sym: format!("__{}{}", SCRATCH[r], k), base: base.map(|a| a + k), off: 0, lin: false }
    }

    pub fn a(&mut self, k: u32) -> Mem {
        self.scr(0, k)
    }
    pub fn b(&mut self, k: u32) -> Mem {
        self.scr(1, k)
    }
    pub fn c(&mut self, k: u32) -> Mem {
        self.scr(2, k)
    }
    pub fn d(&mut self, k: u32) -> Mem {
        self.scr(3, k)
    }

    /// `n` bytes of the current routine's temporary area, returned as a `Mem` for the first byte.
    pub fn temp(&mut self, n: u32) -> Mem {
        let at = self.temp_cur;
        self.temp_cur += n;
        self.temp_max[self.cur] = self.temp_max[self.cur].max(self.temp_cur);
        let obj = self.nvars + 4 + self.cur;
        let sym = format!("{}__TMP", if self.cur < self.p.funcs.len() { &self.p.funcs[self.cur].asm } else { &self.p.main.asm });
        self.obj_mem(obj, sym, at)
    }

    /// A device register (or other fixed address): the symbol pic-as knows.
    pub fn reg_mem(&self, name: &str, addr: u32, off: u32) -> Mem {
        Mem { sym: name.to_string(), base: Some(addr), off, lin: false }
    }

    pub fn sfr(&self, name: &str) -> Option<Mem> {
        self.tgt.sfr.get(name).map(|&a| self.reg_mem(name, a, 0))
    }

    /// Selects the bank of `m` unless it is visible from every bank (core registers and common RAM).
    pub fn sel(&mut self, m: &Mem) {
        let Some(a) = m.addr() else { return };
        let off = a & 0x7F;
        if !(0x0C..0x70).contains(&off) {
            return;
        }
        let b = a >> 7;
        if self.bsr != Some(b) {
            self.ins(format!("movlb {b}"));
            self.bsr = Some(b);
        }
    }

    /// `op f` (movwf, clrf, incf f,f ...).
    pub fn fo(&mut self, op: &str, m: &Mem) {
        self.sel(m);
        self.ins(format!("{op} {}", m.text()));
    }

    /// `op f, d` (d is `w` or `f`).
    pub fn fop(&mut self, op: &str, m: &Mem, d: &str) {
        self.sel(m);
        self.ins(format!("{op} {}, {d}", m.text()));
    }

    /// `bsf`, `bcf`, `btfsc`, `btfss`.
    pub fn fbit(&mut self, op: &str, m: &Mem, bit: u8) {
        self.sel(m);
        self.ins(format!("{op} {}, {bit}", m.text()));
    }

    // ---- bytes through WREG -----------------------------------------------------------------

    pub fn ld_w(&mut self, s: &Sb) {
        match s {
            Sb::K(k) => self.ins(format!("movlw 0x{k:02X}")),
            Sb::M(m) => self.fop("movf", m, "w"),
        }
    }

    /// Byte `k` of an operand.
    pub fn opd_byte(&self, o: &Opd, k: u32) -> Sb {
        match o {
            Opd::K(v) => Sb::K(((*v >> (8 * k)) & 0xFF) as u8),
            Opd::M(m) => Sb::M(m.at(k)),
            Opd::Z(m, n) => if k < *n { Sb::M(m.at(k)) } else { Sb::K(0) },
        }
    }

    /// Copies `n` bytes between two memory operands through WREG.
    pub fn copy_bytes(&mut self, dst: &Mem, src: &Mem, n: u32) {
        for k in 0..n {
            self.fop("movf", &src.at(k), "w");
            self.fo("movwf", &dst.at(k));
        }
    }
}
