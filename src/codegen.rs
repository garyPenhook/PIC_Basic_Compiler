//! PIC18 code generator (Route A, PLAN §7.1): IR in, pic-as assembly out.
//!
//! Value model. An expression of 8 bits is evaluated into `WREG`; wider ones into the
//! accumulator `__A0..__A3` (little endian). `__B`, `__C` and `__D` are the second operand,
//! remainder and counter registers of the multiply/divide/shift helpers. All four live in the
//! Access Bank and are only allocated when used. Every routine owns a temporary area (spills of
//! partial results) in its static frame, so a call can never clobber its caller's temporaries.
//!
//! Layout. The generator runs twice. The first run only counts how often each object is used
//! (weighted by loop depth) and how large each temporary area gets; `plan_layout` then assigns
//! addresses, hottest objects first into the Access Bank; the second run emits final code with
//! exact bank-select decisions.

use crate::asm::{Assembled, Cc, Item, assemble};
use crate::diag::Span;
use crate::ir::*;
use std::collections::{BTreeSet, HashMap};

// ---- layout ------------------------------------------------------------------------------

/// What the code generator needs to know about the device's RAM.
#[derive(Clone, Debug)]
pub struct Target {
    /// Usable general-purpose RAM ranges `[start, end)` outside the Access Bank, in order.
    pub ram: Vec<(u32, u32)>,
    /// Access Bank RAM `[start, end)`.
    pub access: (u32, u32),
    /// First address of the Access Bank's SFR half.
    pub access_sfr: u32,
    pub sfr: HashMap<String, u32>,
}

#[derive(Clone, Debug, Default)]
pub struct Layout {
    /// Address of each object (user variables, then scratch, then temporary areas).
    pub addr: Vec<Option<u32>>,
}

/// An allocatable object.
#[derive(Clone, Debug)]
pub struct Obj {
    pub name: String,
    pub bytes: u32,
    pub weight: u64,
    pub force_access: bool,
    /// Zero-initialised at start-up (user variables only).
    pub zero: bool,
}

const SCRATCH: [&str; 4] = ["A", "B", "C", "D"];

pub fn plan_layout(objs: &[Obj], tgt: &Target) -> Result<Layout, String> {
    let mut addr: Vec<Option<u32>> = vec![None; objs.len()];
    let (a_lo, a_hi) = tgt.access;
    let mut acc_next = a_lo;
    // Scratch first, in order, so the helpers' registers sit at fixed low addresses.
    for (i, o) in objs.iter().enumerate() {
        if o.force_access && o.bytes > 0 {
            if acc_next + o.bytes > a_hi {
                return Err("out of Access Bank RAM for compiler scratch registers".into());
            }
            addr[i] = Some(acc_next);
            acc_next += o.bytes;
        }
    }
    let mut order: Vec<usize> = (0..objs.len()).filter(|&i| !objs[i].force_access && objs[i].bytes > 0).collect();
    order.sort_by(|&x, &y| objs[y].weight.cmp(&objs[x].weight).then(x.cmp(&y)));
    // Hot objects go into the Access Bank while it has room; the rest are banked.
    let mut banked: Vec<usize> = Vec::new();
    for &i in &order {
        if acc_next + objs[i].bytes <= a_hi {
            addr[i] = Some(acc_next);
            acc_next += objs[i].bytes;
        } else {
            banked.push(i);
        }
    }
    let mut ranges: Vec<(u32, u32)> = tgt.ram.clone();
    for &i in &banked {
        let n = objs[i].bytes;
        let mut placed = false;
        for r in ranges.iter_mut() {
            let mut s = r.0;
            // Keep an object inside one 256-byte bank so a single BSR value covers it.
            if (s >> 8) != ((s + n - 1) >> 8) {
                s = ((s >> 8) + 1) << 8;
            }
            if s + n <= r.1 {
                addr[i] = Some(s);
                r.0 = s + n;
                placed = true;
                break;
            }
        }
        if !placed {
            return Err(format!("out of data RAM placing `{}` ({} bytes)", objs[i].name, n));
        }
    }
    Ok(Layout { addr })
}

// ---- operands ------------------------------------------------------------------------------

#[derive(Clone, Debug)]
struct Mem {
    sym: String,
    addr: Option<u32>,
    /// Object counted when this memory is touched.
    obj: Option<usize>,
    /// A device register rather than program RAM.
    reg: bool,
}

impl Mem {
    fn at(&self, i: u32) -> Mem {
        Mem { sym: if i == 0 { self.sym.clone() } else { format!("{}+{}", self.sym, i) }, addr: self.addr.map(|a| a + i), obj: self.obj, reg: self.reg }
    }
}

#[derive(Clone, Debug)]
enum Bs {
    Imm(u8),
    Mem(Mem),
}

/// An operand that needs no code to read: a constant or memory, possibly zero-extended.
#[derive(Clone, Debug)]
enum Src {
    Imm(u32),
    /// Memory holding `real` bytes; higher bytes read as zero.
    Mem(Mem, u32),
}

impl Src {
    fn byte(&self, i: u32) -> Bs {
        match self {
            Src::Imm(v) => Bs::Imm(((*v >> (8 * i)) & 0xFF) as u8),
            Src::Mem(m, real) => {
                if i < *real {
                    Bs::Mem(m.at(i))
                } else {
                    Bs::Imm(0)
                }
            }
        }
    }
}

fn is_access(tgt: &Target, addr: Option<u32>) -> bool {
    match addr {
        None => true,
        Some(a) => a < tgt.access.1 || a >= tgt.access_sfr,
    }
}

// ---- generator ---------------------------------------------------------------------------

pub struct Output {
    pub text: String,
    pub words: u32,
    pub labels: HashMap<String, u32>,
    /// Program words per function (assembly label, words).
    pub func_words: Vec<(String, u32)>,
}

pub struct FirstPass {
    pub objs: Vec<Obj>,
}

struct Gen<'p> {
    p: &'p Program,
    tgt: &'p Target,
    layout: Option<&'p Layout>,
    items: Vec<Item>,
    bsr: Option<u8>,
    lbl: u32,
    uses: Vec<u64>,
    depth: u32,
    cur: usize,
    cur_asm: String,
    temp_cur: u32,
    temp_max: Vec<u32>,
    scratch_max: [u32; 4],
    loops: Vec<(String, String)>,
    called: BTreeSet<FuncId>,
    helpers: BTreeSet<String>,
    /// String literals held in program memory, in first-use order (label `__STR<n>`).
    lits: Vec<Vec<u8>>,
    errors: Vec<(Span, String)>,
    span: Span,
    nvars: usize,
}

fn weight(depth: u32) -> u64 {
    8u64.pow(depth.min(4))
}

impl<'p> Gen<'p> {
    fn new(p: &'p Program, tgt: &'p Target, layout: Option<&'p Layout>) -> Gen<'p> {
        let nvars = p.vars.len();
        let nobj = nvars + 4 + p.funcs.len() + 1;
        Gen {
            p,
            tgt,
            layout,
            items: Vec::new(),
            bsr: Some(0),
            lbl: 0,
            uses: vec![0; nobj],
            depth: 0,
            cur: p.funcs.len(),
            cur_asm: p.main.asm.clone(),
            temp_cur: 0,
            temp_max: vec![0; p.funcs.len() + 1],
            scratch_max: [0; 4],
            loops: Vec::new(),
            called: BTreeSet::new(),
            helpers: BTreeSet::new(),
            lits: Vec::new(),
            errors: Vec::new(),
            span: Span::default(),
            nvars,
        }
    }

    fn err(&mut self, msg: impl Into<String>) {
        self.errors.push((self.span, msg.into()));
    }

    // ---- emission primitives ----------------------------------------------------------

    fn ins(&mut self, s: impl Into<String>) {
        self.items.push(Item::Ins(s.into()));
    }

    fn label(&mut self, l: &str) {
        self.items.push(Item::Label(l.to_string()));
        self.bsr = None;
    }

    fn fresh(&mut self) -> String {
        self.lbl += 1;
        format!("_L{}", self.lbl)
    }

    fn br(&mut self, cc: Cc, l: &str) {
        self.items.push(Item::Br(cc, l.to_string()));
    }

    fn obj_scratch(&self, r: usize) -> usize {
        self.nvars + r
    }
    fn obj_temp(&self, f: usize) -> usize {
        self.nvars + 4 + f
    }

    fn mem_obj(&self, obj: usize, sym: String) -> Mem {
        let addr = self.layout.and_then(|l| l.addr[obj]);
        Mem { sym, addr, obj: Some(obj), reg: false }
    }

    fn scr(&mut self, r: usize, i: u32) -> Mem {
        self.scratch_max[r] = self.scratch_max[r].max(i + 1);
        let mut m = self.mem_obj(self.obj_scratch(r), format!("__{}{}", SCRATCH[r], i));
        m.addr = m.addr.map(|a| a + i);
        m
    }
    fn a(&mut self, i: u32) -> Mem {
        self.scr(0, i)
    }
    fn b(&mut self, i: u32) -> Mem {
        self.scr(1, i)
    }
    fn c(&mut self, i: u32) -> Mem {
        self.scr(2, i)
    }
    fn d(&mut self, i: u32) -> Mem {
        self.scr(3, i)
    }

    fn place_mem(&self, pl: &Place, write: bool) -> Mem {
        let m = match &pl.base {
            Base::Ptr(_) => unreachable!("an indirect place has no direct memory operand"),
            Base::Var(v) => self.mem_obj(*v, self.p.vars[*v].asm.clone()),
            Base::Abs { addr, name } => {
                // Writes to a port go to its latch (read-modify-write on PORT is unreliable).
                let mut name = name.clone();
                let mut addr = *addr;
                if write && let Some(rest) = name.strip_prefix("PORT") {
                    let lat = format!("LAT{rest}");
                    if let Some(&la) = self.tgt.sfr.get(&lat) {
                        name = lat;
                        addr = la;
                    }
                }
                Mem { sym: name, addr: Some(addr), obj: None, reg: true }
            }
        };
        m.at(pl.off)
    }

    fn temp(&mut self, n: u32) -> Mem {
        let off = self.temp_cur;
        self.temp_cur += n;
        self.temp_max[self.cur] = self.temp_max[self.cur].max(self.temp_cur);
        let base = self.mem_obj(self.obj_temp(self.cur), format!("{}__TMP", self.cur_asm));
        base.at(off)
    }
    fn free(&mut self, n: u32) {
        self.temp_cur -= n;
    }

    /// Selects the bank for a memory operand; returns the access flag.
    fn acc_flag(&mut self, m: &Mem) -> &'static str {
        if let Some(o) = m.obj {
            self.uses[o] += weight(self.depth);
        }
        if is_access(self.tgt, m.addr) {
            return "c";
        }
        let bank = (m.addr.unwrap() >> 8) as u8;
        if self.bsr != Some(bank) {
            self.ins(format!("movlb {bank}"));
            self.bsr = Some(bank);
        }
        "b"
    }

    /// `op f, d, a`
    fn fop(&mut self, op: &str, m: &Mem, d: &str) {
        let a = self.acc_flag(m);
        self.ins(format!("{op} {}, {d}, {a}", m.sym));
    }
    /// `op f, a` (movwf, clrf, setf, tstfsz, negf, cpfseq, mulwf, ...)
    fn fo(&mut self, op: &str, m: &Mem) {
        let a = self.acc_flag(m);
        self.ins(format!("{op} {}, {a}", m.sym));
    }
    /// `op f, bit, a`
    fn fbit(&mut self, op: &str, m: &Mem, bit: u8) {
        let a = self.acc_flag(m);
        self.ins(format!("{op} {}, {bit}, {a}", m.sym));
    }

    fn movff(&mut self, dst: &Mem, src: &Mem) {
        for m in [dst, src] {
            if let Some(o) = m.obj {
                self.uses[o] += weight(self.depth);
            }
        }
        self.ins(format!("movff {}, {}", src.sym, dst.sym));
    }

    // ---- operand access ---------------------------------------------------------------

    fn simple(&self, e: &Ex) -> Option<Src> {
        match &e.k {
            ExK::Const(v) => Some(Src::Imm(*v & mask(e.w))),
            ExK::Load(p) if p.bit.is_none() && !p.indirect() => Some(Src::Mem(self.place_mem(p, false), p.bytes())),
            ExK::Conv(inner) => {
                let s = self.simple(inner)?;
                if e.w <= inner.w {
                    return Some(match s {
                        Src::Imm(v) => Src::Imm(v & mask(e.w)),
                        Src::Mem(m, real) => Src::Mem(m, real.min(e.w as u32 / 8)),
                    });
                }
                if inner.signed { None } else { Some(s) }
            }
            _ => None,
        }
    }

    fn src_to_w(&mut self, b: &Bs) {
        match b {
            Bs::Imm(k) => self.ins(format!("movlw 0x{k:02X}")),
            Bs::Mem(m) => self.fop("movf", m, "w"),
        }
    }

    /// Writes a byte source into memory.
    fn put_byte(&mut self, dst: &Mem, b: &Bs) {
        match b {
            Bs::Imm(0) => self.fo("clrf", dst),
            Bs::Imm(0xFF) => self.fo("setf", dst),
            Bs::Imm(k) => {
                self.ins(format!("movlw 0x{k:02X}"));
                self.fo("movwf", dst);
            }
            Bs::Mem(m) => {
                if dst.reg {
                    self.fop("movf", m, "w");
                    self.fo("movwf", dst);
                } else {
                    self.movff(dst, m);
                }
            }
        }
    }

    fn store_src(&mut self, dst: &Mem, n: u32, s: &Src) {
        // Constant stores reuse W when consecutive bytes are equal.
        let mut w_has: Option<u8> = None;
        for i in 0..n {
            let b = s.byte(i);
            if let Bs::Imm(k) = b
                && k != 0
                && k != 0xFF
            {
                if w_has != Some(k) {
                    self.ins(format!("movlw 0x{k:02X}"));
                    w_has = Some(k);
                }
                self.fo("movwf", &dst.at(i));
            } else {
                self.put_byte(&dst.at(i), &b);
            }
        }
    }

    // ---- values ---------------------------------------------------------------------------

    fn nb(e: &Ex) -> u32 {
        e.w as u32 / 8
    }

    /// Evaluates `e`: into WREG when 8 bits wide, into `__A` otherwise.
    fn gen_val(&mut self, e: &Ex) {
        let n = Self::nb(e);
        match &e.k {
            ExK::Const(v) => {
                if n == 1 {
                    self.ins(format!("movlw 0x{:02X}", *v & 0xFF));
                } else {
                    let a = self.a(0);
                    self.store_src(&a, n, &Src::Imm(*v));
                }
            }
            ExK::Load(p) => self.load_place(p, n),
            ExK::Addr(p) => {
                if p.indirect() {
                    // Leaves the address in __A0:__A1 as well.
                    self.point_fsr0(p);
                } else {
                    let sym = match &p.base {
                        Base::Var(v) => {
                            self.uses[*v] += weight(self.depth);
                            self.p.vars[*v].asm.clone()
                        }
                        Base::Abs { name, .. } => name.clone(),
                        Base::Ptr(_) => unreachable!(),
                    };
                    let at = if p.off == 0 { sym } else { format!("{sym}+{}", p.off) };
                    let (a0, a1) = (self.a(0), self.a(1));
                    self.ins(format!("movlw low({at})"));
                    self.fo("movwf", &a0);
                    self.ins(format!("movlw high({at})"));
                    self.fo("movwf", &a1);
                }
            }
            ExK::StrEq(a, b) => {
                let StrSrc::Ram(pa) = a else {
                    self.err("internal: a string comparison needs a variable on the left");
                    return;
                };
                self.point_str(0, pa);
                match b {
                    StrSrc::Ram(pb) => {
                        self.point_str(1, pb);
                        self.call_helper("strqr1".into());
                    }
                    StrSrc::Lit(l) => {
                        self.point_flash(l);
                        self.call_helper("strqf1".into());
                    }
                    StrSrc::Char(_) => self.err("internal: a Char in a string comparison"),
                }
            }
            ExK::Conv(inner) => self.gen_conv(inner, e.w, e.signed),
            ExK::Neg(x) => {
                self.gen_val(x);
                if n == 1 {
                    self.ins("sublw 0");
                } else {
                    for i in (1..n).rev() {
                        let m = self.a(i);
                        self.fop("comf", &m, "f");
                    }
                    let m = self.a(0);
                    self.fo("negf", &m);
                    self.ins("movlw 0");
                    for i in 1..n {
                        let m = self.a(i);
                        self.fop("addwfc", &m, "f");
                    }
                }
            }
            ExK::Com(x) => {
                self.gen_val(x);
                if n == 1 {
                    self.ins("xorlw 0xFF");
                } else {
                    for i in 0..n {
                        let m = self.a(i);
                        self.fop("comf", &m, "f");
                    }
                }
            }
            ExK::Bin(op, l, r) => self.gen_bin(*op, l, r, e),
            ExK::Cmp(..) | ExK::AndAlso(..) | ExK::OrElse(..) | ExK::NotB(..) => {
                let (lf, le) = (self.fresh(), self.fresh());
                self.cond_jump(e, false, &lf);
                self.ins("movlw 1");
                self.br(Cc::Always, &le);
                self.label(&lf);
                self.ins("movlw 0");
                self.label(&le);
            }
            ExK::Call(f, args) => {
                self.do_call(*f, args);
                let rv = self.p.funcs[*f].result.expect("a value call has a result");
                let m = self.mem_obj(rv, self.p.vars[rv].asm.clone());
                if n == 1 {
                    self.fop("movf", &m, "w");
                } else {
                    for i in 0..n {
                        let d = self.a(i);
                        self.movff(&d, &m.at(i));
                    }
                }
            }
        }
    }

    /// A special function register by name, for the indirect-addressing registers.
    fn sfr_mem(&self, name: &str) -> Mem {
        Mem { sym: name.to_string(), addr: self.tgt.sfr.get(name).copied(), obj: None, reg: false }
    }

    /// Points FSR0 at the byte an indirect place names: `base + off (+ idx)`, where the base is
    /// an array or the address held by a `ByRef` parameter. Clobbers `__A`.
    fn point_fsr0(&mut self, p: &Place) {
        let (a0, a1) = (self.a(0), self.a(1));
        let ptr = match &p.base {
            Base::Ptr(v) => {
                let m = self.mem_obj(*v, self.p.vars[*v].asm.clone());
                Some((*v, m))
            }
            _ => None,
        };
        if let Some(idx) = &p.idx {
            self.gen_to_acc(idx);
        } else if let Some((_, m)) = &ptr {
            self.movff(&a0, m);
            self.movff(&a1, &m.at(1));
        } else {
            self.err("internal: an indirect place without an index or pointer");
            return;
        }
        match (&p.base, &ptr) {
            (Base::Var(v), _) => {
                // Counted once, not by loop depth: FSR0 access gains nothing from the Access Bank.
                self.uses[*v] += 1;
                let sym = &self.p.vars[*v].asm;
                let at = if p.off == 0 { sym.clone() } else { format!("{sym}+{}", p.off) };
                self.ins(format!("movlw low({at})"));
                self.fop("addwf", &a0, "f");
                self.ins(format!("movlw high({at})"));
                self.fop("addwfc", &a1, "f");
            }
            (_, Some((_, m))) => {
                if p.idx.is_some() {
                    self.fop("movf", m, "w");
                    self.fop("addwf", &a0, "f");
                    self.fop("movf", &m.at(1), "w");
                    self.fop("addwfc", &a1, "f");
                }
                if p.off != 0 {
                    self.ins(format!("movlw 0x{:02X}", p.off & 0xFF));
                    self.fop("addwf", &a0, "f");
                    self.ins(format!("movlw 0x{:02X}", (p.off >> 8) & 0xFF));
                    self.fop("addwfc", &a1, "f");
                }
            }
            _ => self.err("internal: an indirect place on a device register"),
        }
        let (f0l, f0h) = (self.sfr_mem("FSR0L"), self.sfr_mem("FSR0H"));
        self.movff(&f0l, &a0);
        self.movff(&f0h, &a1);
    }

    /// Points FSR`fsr` at the first byte of a RAM string (a variable or a `ByRef` parameter).
    fn point_str(&mut self, fsr: u8, p: &Place) {
        match &p.base {
            Base::Var(v) => {
                self.uses[*v] += weight(self.depth);
                let sym = self.p.vars[*v].asm.clone();
                let at = if p.off == 0 { sym } else { format!("{sym}+{}", p.off) };
                self.ins(format!("lfsr {fsr}, {at}"));
            }
            Base::Ptr(v) => {
                if p.off != 0 {
                    self.err("internal: an offset into a ByRef string");
                }
                let m = self.mem_obj(*v, self.p.vars[*v].asm.clone());
                let (l, h) = (self.sfr_mem(&format!("FSR{fsr}L")), self.sfr_mem(&format!("FSR{fsr}H")));
                self.movff(&l, &m);
                self.movff(&h, &m.at(1));
            }
            Base::Abs { .. } => self.err("internal: a string in a device register"),
        }
    }

    /// Points TBLPTR at a string literal in program memory (stored once, Null-terminated).
    fn point_flash(&mut self, lit: &[u8]) {
        let n = match self.lits.iter().position(|l| l == lit) {
            Some(n) => n,
            None => {
                self.lits.push(lit.to_vec());
                self.lits.len() - 1
            }
        };
        for (reg, op) in [("TBLPTRL", "low"), ("TBLPTRH", "high"), ("TBLPTRU", "highword")] {
            self.ins(format!("movlw {op}(__STR{n})"));
            let m = self.sfr_mem(reg);
            self.fo("movwf", &m);
        }
    }

    /// `dst = parts[0] + parts[1] + …` through the string helpers: FSR0 is the write pointer,
    /// `__D0` the room left, and each part is appended and the text Null-terminated.
    fn str_set(&mut self, dst: &Place, cap: u32, parts: &[StrSrc], keep: bool) {
        let todo = &parts[keep as usize..];
        if keep && todo.is_empty() {
            return;
        }
        // Char values other than constants are read first: computing one can use FSR0 and the
        // scratch bytes, and a plain variable (`s(0)` of the target itself) must not be read
        // after earlier parts have been written over it.
        let mut saved: Vec<Option<Mem>> = Vec::new();
        let mut ntemps = 0;
        for p in todo {
            match p {
                StrSrc::Char(e) if e.as_const().is_none() => {
                    saved.push(Some(self.spill(e)));
                    ntemps += 1;
                }
                _ => saved.push(None),
            }
        }
        self.point_str(0, dst);
        self.ins(format!("movlw {cap}"));
        let d0 = self.d(0);
        self.fo("movwf", &d0);
        if keep {
            self.call_helper("stre1".into());
        }
        let mut wrote = keep;
        for (p, t) in todo.iter().zip(&saved) {
            match p {
                StrSrc::Ram(pl) => {
                    self.point_str(1, pl);
                    self.call_helper("strr1".into());
                    wrote = true;
                }
                StrSrc::Lit(b) if b.is_empty() => {}
                StrSrc::Lit(b) => {
                    self.point_flash(b);
                    self.call_helper("strf1".into());
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
                    self.call_helper("strc1".into());
                    wrote = true;
                }
            }
        }
        if !wrote {
            let m = self.sfr_mem("INDF0");
            self.fo("clrf", &m);
        }
        self.free(ntemps);
    }

    fn load_place(&mut self, p: &Place, n: u32) {
        if p.indirect() {
            self.point_fsr0(p);
            if n == 1 {
                let m = self.sfr_mem("INDF0");
                self.fop("movf", &m, "w");
            } else {
                let post = self.sfr_mem("POSTINC0");
                for i in 0..n {
                    let d = self.a(i);
                    self.movff(&d, &post);
                }
            }
            return;
        }
        let m = self.place_mem(p, false);
        if let Some(b) = p.bit {
            self.ins("movlw 0");
            let a = self.acc_flag(&m);
            self.ins(format!("btfsc {}, {b}, {a}", m.sym));
            self.ins("movlw 1");
            return;
        }
        if n == 1 {
            self.fop("movf", &m, "w");
        } else {
            for i in 0..n {
                let d = self.a(i);
                self.movff(&d, &m.at(i));
            }
        }
    }

    fn gen_conv(&mut self, inner: &Ex, w: u8, signed: bool) {
        let (n, ni) = (w as u32 / 8, Self::nb(inner));
        if n == ni {
            self.gen_val(inner);
            return;
        }
        // Reading fewer bytes of a plain variable is just a narrower load.
        if n < ni
            && let ExK::Load(p) = &inner.k
            && p.bit.is_none()
        {
            self.load_place(p, n);
            return;
        }
        self.gen_val(inner);
        if n < ni {
            if n == 1 {
                let m = self.a(0);
                self.fop("movf", &m, "w");
            }
            return;
        }
        // Widening.
        if ni == 1 {
            let m = self.a(0);
            self.fo("movwf", &m);
        }
        if inner.signed {
            self.ins("movlw 0");
            let top = self.a(ni - 1);
            self.fbit("btfsc", &top, 7);
            self.ins("movlw 0xFF");
            for i in ni..n {
                let m = self.a(i);
                self.fo("movwf", &m);
            }
        } else {
            for i in ni..n {
                let m = self.a(i);
                self.fo("clrf", &m);
            }
        }
        let _ = signed;
    }

    /// Loads a simple operand into `__A`.
    fn src_to_acc(&mut self, s: &Src, n: u32) {
        let a = self.a(0);
        self.store_src(&a, n, s);
    }

    fn src_to_reg(&mut self, r: usize, s: &Src, n: u32) {
        let m = self.scr(r, 0);
        self.store_src(&m, n, s);
    }

    /// Leaves `e` in `__A` (any width), copying from W when it is 8 bits.
    fn gen_to_acc(&mut self, e: &Ex) {
        if let Some(s) = self.simple(e) {
            self.src_to_acc(&s, Self::nb(e));
            return;
        }
        self.gen_val(e);
        if Self::nb(e) == 1 {
            let m = self.a(0);
            self.fo("movwf", &m);
        }
    }

    /// Evaluates `e` and saves it in a new temporary.
    fn spill(&mut self, e: &Ex) -> Mem {
        let n = Self::nb(e);
        self.gen_val(e);
        let t = self.temp(n);
        if n == 1 {
            self.fo("movwf", &t);
        } else {
            for i in 0..n {
                let a = self.a(i);
                self.movff(&t.at(i), &a);
            }
        }
        t
    }

    // ---- arithmetic -------------------------------------------------------------------

    fn gen_bin(&mut self, op: BinKind, l: &Ex, r: &Ex, e: &Ex) {
        let n = Self::nb(e);
        match op {
            BinKind::Add | BinKind::Sub | BinKind::And | BinKind::Or | BinKind::Xor => {
                if n == 1 {
                    self.bin_byte(op, l, r)
                } else {
                    self.bin_multi(op, l, r, n)
                }
            }
            BinKind::Mul => self.gen_mul(l, r, e),
            BinKind::Div | BinKind::Mod => self.gen_div(op, l, r, e),
            BinKind::Shl | BinKind::Shr => self.gen_shift(op, l, r, e),
        }
    }

    /// `W = W op src` where W holds the left operand.
    fn w_op(&mut self, op: BinKind, s: &Bs) {
        match (op, s) {
            (BinKind::Add, Bs::Imm(k)) => {
                if *k != 0 {
                    self.ins(format!("addlw 0x{k:02X}"))
                }
            }
            (BinKind::Add, Bs::Mem(m)) => self.fop("addwf", m, "w"),
            (BinKind::Sub, Bs::Imm(k)) => {
                if *k != 0 {
                    self.ins(format!("addlw 0x{:02X}", (256 - *k as u32) & 0xFF))
                }
            }
            (BinKind::Sub, Bs::Mem(m)) => {
                self.fop("subwf", m, "w");
                self.ins("sublw 0");
            }
            (BinKind::And, Bs::Imm(k)) => self.ins(format!("andlw 0x{k:02X}")),
            (BinKind::Or, Bs::Imm(k)) => {
                if *k != 0 {
                    self.ins(format!("iorlw 0x{k:02X}"))
                }
            }
            (BinKind::Xor, Bs::Imm(k)) => {
                if *k != 0 {
                    self.ins(format!("xorlw 0x{k:02X}"))
                }
            }
            (BinKind::And, Bs::Mem(m)) => self.fop("andwf", m, "w"),
            (BinKind::Or, Bs::Mem(m)) => self.fop("iorwf", m, "w"),
            (BinKind::Xor, Bs::Mem(m)) => self.fop("xorwf", m, "w"),
            _ => unreachable!(),
        }
    }

    /// `W = src op W` where W holds the right operand.
    fn w_op_rev(&mut self, op: BinKind, s: &Bs) {
        match (op, s) {
            (BinKind::Sub, Bs::Imm(k)) => self.ins(format!("sublw 0x{k:02X}")),
            (BinKind::Sub, Bs::Mem(m)) => self.fop("subwf", m, "w"),
            _ => self.w_op(op, s),
        }
    }

    fn bin_byte(&mut self, op: BinKind, l: &Ex, r: &Ex) {
        let comm = op != BinKind::Sub;
        let mut ls = self.simple(l);
        let rs = self.simple(r);
        if r.has_call() && matches!(ls, Some(Src::Mem(..))) {
            ls = None;
        }
        if let Some(rs) = rs {
            let rb = rs.byte(0);
            match (&ls, &rb) {
                // `k op mem` with a commutative operator: start from the memory operand.
                (Some(Src::Imm(k)), Bs::Mem(_)) if comm => {
                    self.src_to_w(&rb);
                    self.w_op(op, &Bs::Imm(*k as u8));
                    return;
                }
                (Some(s), _) => {
                    let b = s.byte(0);
                    self.src_to_w(&b);
                }
                (None, _) => self.gen_val(l),
            }
            self.w_op(op, &rb);
        } else if let Some(ls) = ls {
            self.gen_val(r);
            self.w_op_rev(op, &ls.byte(0));
        } else {
            let t = self.spill(l);
            self.gen_val(r);
            self.w_op_rev(op, &Bs::Mem(t));
            self.free(1);
        }
    }

    /// `dst op= src` over `n` bytes, with carry between bytes for add and subtract.
    fn chain(&mut self, op: BinKind, dst: &dyn Fn(&mut Self, u32) -> Mem, s: &Src, n: u32) {
        // One byte plus or minus one is a single increment or decrement.
        if n == 1 && let Src::Imm(k) = s {
            let step = match (op, *k & 0xFF) {
                (BinKind::Add, 1) | (BinKind::Sub, 0xFF) => Some("incf"),
                (BinKind::Add, 0xFF) | (BinKind::Sub, 1) => Some("decf"),
                _ => None,
            };
            if let Some(name) = step {
                let d = dst(self, 0);
                self.fop(name, &d, "f");
                return;
            }
        }
        for i in 0..n {
            let b = s.byte(i);
            let d = dst(self, i);
            let (name, skip0) = match op {
                BinKind::Add => (if i == 0 { "addwf" } else { "addwfc" }, i == 0 && matches!(b, Bs::Imm(0))),
                BinKind::Sub => (if i == 0 { "subwf" } else { "subwfb" }, i == 0 && matches!(b, Bs::Imm(0))),
                BinKind::And => ("andwf", false),
                BinKind::Or => ("iorwf", matches!(b, Bs::Imm(0))),
                BinKind::Xor => ("xorwf", matches!(b, Bs::Imm(0))),
                _ => unreachable!(),
            };
            if skip0 {
                // Adding or subtracting zero changes nothing, but the next byte consumes the
                // carry: make it "no carry" (add) / "no borrow" (subtract).
                if n > 1 {
                    self.ins(if op == BinKind::Add { "bcf STATUS, 0, c" } else { "bsf STATUS, 0, c" });
                }
                continue;
            }
            match (op, &b) {
                (BinKind::And, Bs::Imm(0)) => self.fo("clrf", &d),
                (BinKind::And, Bs::Imm(0xFF)) => {}
                (BinKind::Or, Bs::Imm(0xFF)) => self.fo("setf", &d),
                _ => {
                    self.src_to_w(&b);
                    self.fop(name, &d, "f");
                }
            }
        }
    }

    fn bin_multi(&mut self, op: BinKind, l: &Ex, r: &Ex, n: u32) {
        let comm = op != BinKind::Sub;
        let a_of = |g: &mut Self, i: u32| g.a(i);
        let mut ls = self.simple(l);
        let rs = self.simple(r);
        if r.has_call() && matches!(ls, Some(Src::Mem(..))) {
            ls = None;
        }
        if let Some(rs) = rs {
            self.gen_to_acc(l);
            self.chain(op, &a_of, &rs, n);
        } else if let Some(ls) = ls {
            self.gen_to_acc(r);
            if comm {
                self.chain(op, &a_of, &ls, n);
            } else {
                // A = L - A
                let lm = match &ls {
                    Src::Mem(m, real) if *real == n => m.clone(),
                    other => {
                        self.src_to_reg(1, other, n);
                        self.b(0)
                    }
                };
                self.rsub(&lm, n);
            }
        } else {
            let t = self.spill(l);
            self.gen_to_acc(r);
            if comm {
                self.chain(op, &a_of, &Src::Mem(t.clone(), n), n);
            } else {
                self.rsub(&t, n);
            }
            self.free(n);
        }
    }

    /// `A = M - A` over `n` bytes.
    fn rsub(&mut self, m: &Mem, n: u32) {
        for i in 0..n {
            let a = self.a(i);
            self.fop("movf", &a, "w");
            self.fop(if i == 0 { "subwf" } else { "subwfb" }, &m.at(i), "w");
            self.fo("movwf", &a);
        }
    }

    // ---- multiply, divide, shift ----------------------------------------------------------

    /// Puts `l` in `__A` and `r` in `__B` (n bytes each).
    fn prep_ab(&mut self, l: &Ex, r: &Ex, n: u32) {
        let mut ls = self.simple(l);
        let rs = self.simple(r);
        if r.has_call() && matches!(ls, Some(Src::Mem(..))) {
            ls = None;
        }
        if let Some(rs) = rs {
            self.gen_to_acc(l);
            self.src_to_reg(1, &rs, n);
        } else if let Some(ls) = ls {
            self.gen_to_acc(r);
            self.a_to_b(n);
            self.src_to_acc(&ls, n);
        } else {
            let t = self.spill(l);
            self.gen_to_acc(r);
            self.a_to_b(n);
            let a = self.a(0);
            self.store_src(&a, n, &Src::Mem(t, n));
            self.free(n);
        }
    }

    fn a_to_b(&mut self, n: u32) {
        for i in 0..n {
            let (b, a) = (self.b(i), self.a(i));
            self.movff(&b, &a);
        }
    }

    fn call_helper(&mut self, name: String) {
        self.items.push(Item::Call(format!("__{name}")));
        self.helpers.insert(name);
        self.bsr = None;
    }

    /// An 8-bit multiply into PRODH:PRODL.
    fn mul8(&mut self, x: &Ex, y: &Ex) {
        let mut xs = self.simple(x);
        let ys = self.simple(y);
        if y.has_call() && matches!(xs, Some(Src::Mem(..))) {
            xs = None;
        }
        let mulw = |g: &mut Self, s: &Bs| match s {
            Bs::Imm(k) => g.ins(format!("mullw 0x{k:02X}")),
            Bs::Mem(m) => g.fo("mulwf", m),
        };
        if let Some(ys) = ys {
            match &xs {
                Some(s) => {
                    let b = s.byte(0);
                    self.src_to_w(&b)
                }
                None => self.gen_val(x),
            }
            mulw(self, &ys.byte(0));
        } else if let Some(xs) = xs {
            self.gen_val(y);
            mulw(self, &xs.byte(0));
        } else {
            let t = self.spill(x);
            self.gen_val(y);
            mulw(self, &Bs::Mem(t));
            self.free(1);
        }
    }

    fn gen_mul(&mut self, l: &Ex, r: &Ex, e: &Ex) {
        let n = Self::nb(e);
        if n == 1 {
            self.mul8(l, r);
            self.ins("movf PRODL, w, c");
            return;
        }
        // Two zero-extended bytes: one hardware multiply.
        let narrow = |x: &Ex| -> Option<Ex> {
            match &x.k {
                ExK::Conv(i) if i.w == 8 && !i.signed => Some((**i).clone()),
                ExK::Const(v) if *v <= 0xFF => Some(Ex::konst(*v, 8, false)),
                _ => None,
            }
        };
        if let (Some(x), Some(y)) = (narrow(l), narrow(r)) {
            self.mul8(&x, &y);
            let a0 = self.a(0);
            self.movff_sfr(&a0, "PRODL");
            let a1 = self.a(1);
            self.movff_sfr(&a1, "PRODH");
            for i in 2..n {
                let m = self.a(i);
                self.fo("clrf", &m);
            }
            return;
        }
        self.prep_ab(l, r, n);
        self.call_helper(format!("mul{n}"));
    }

    fn movff_sfr(&mut self, dst: &Mem, sfr: &str) {
        if let Some(o) = dst.obj {
            self.uses[o] += weight(self.depth);
        }
        self.ins(format!("movff {sfr}, {}", dst.sym));
    }

    fn gen_div(&mut self, op: BinKind, l: &Ex, r: &Ex, e: &Ex) {
        let n = Self::nb(e);
        self.prep_ab(l, r, n);
        let s = if e.signed { "s" } else { "" };
        self.call_helper(format!("{s}div{n}"));
        if op == BinKind::Mod {
            for i in 0..n {
                let (a, c) = (self.a(i), self.c(i));
                self.movff(&a, &c);
            }
        }
        if n == 1 {
            let m = self.a(0);
            self.fop("movf", &m, "w");
        }
    }

    fn gen_shift(&mut self, op: BinKind, l: &Ex, r: &Ex, e: &Ex) {
        let n = Self::nb(e);
        let left = op == BinKind::Shl;
        if let Some(k) = r.as_const() {
            let k = k as u32;
            if k == 0 {
                self.gen_val(l);
                return;
            }
            if k >= e.w as u32 && (left || !e.signed) {
                // Everything shifted out.
                self.gen_val(&Ex::konst(0, e.w, e.signed));
                return;
            }
            if n == 1 {
                self.shift_byte(left, e.signed, k, l);
                return;
            }
            self.gen_to_acc(l);
            self.shift_acc(left, e.signed, k.min(e.w as u32), n);
            return;
        }
        // Variable count.
        let ls = self.simple(l);
        if let Some(s) = ls
            && !r.has_call()
        {
            self.gen_val(r);
            let d = self.d(1);
            self.fo("movwf", &d);
            self.src_to_acc(&s, n);
        } else {
            let t = self.spill(l);
            self.gen_val(r);
            let d = self.d(1);
            self.fo("movwf", &d);
            let a = self.a(0);
            self.store_src(&a, n, &Src::Mem(t, n));
            self.free(n);
        }
        let kind = if left {
            "shl"
        } else if e.signed {
            "sar"
        } else {
            "shr"
        };
        self.call_helper(format!("{kind}{n}"));
        if n == 1 {
            let m = self.a(0);
            self.fop("movf", &m, "w");
        }
    }

    fn shift_byte(&mut self, left: bool, signed: bool, k: u32, l: &Ex) {
        if let Some(s) = self.simple(l) {
            let b = s.byte(0);
            self.src_to_w(&b);
        } else {
            self.gen_val(l);
        }
        if left {
            if k <= 3 {
                for _ in 0..k {
                    self.ins("addwf WREG, w, c");
                }
            } else {
                self.ins(format!("mullw {}", 1u32 << k));
                self.ins("movf PRODL, w, c");
            }
        } else if !signed {
            if k == 4 {
                self.ins("swapf WREG, w, c");
                self.ins("andlw 0x0F");
            } else {
                for _ in 0..k {
                    self.ins("rrncf WREG, w, c");
                }
                self.ins(format!("andlw 0x{:02X}", 0xFFu32 >> k));
            }
        } else {
            let a0 = self.a(0);
            self.fo("movwf", &a0);
            self.shift_acc(false, true, k, 1);
            self.fop("movf", &a0, "w");
        }
    }

    /// Shifts `__A` (n bytes) by the constant `k`.
    fn shift_acc(&mut self, left: bool, signed: bool, k: u32, n: u32) {
        let (q, r) = (k / 8, k % 8);
        let total = n * 8;
        if k >= total {
            // Only reachable for a signed right shift: fill with the sign.
            self.ins("movlw 0");
            let top = self.a(n - 1);
            self.fbit("btfsc", &top, 7);
            self.ins("movlw 0xFF");
            for i in 0..n {
                let m = self.a(i);
                self.fo("movwf", &m);
            }
            return;
        }
        if q > 0 {
            if left {
                for i in (q..n).rev() {
                    let (d, s) = (self.a(i), self.a(i - q));
                    self.movff(&d, &s);
                }
                for i in 0..q {
                    let m = self.a(i);
                    self.fo("clrf", &m);
                }
            } else {
                if signed {
                    self.ins("movlw 0");
                    let top = self.a(n - 1);
                    self.fbit("btfsc", &top, 7);
                    self.ins("movlw 0xFF");
                }
                for i in 0..n - q {
                    let (d, s) = (self.a(i), self.a(i + q));
                    self.movff(&d, &s);
                }
                for i in n - q..n {
                    let m = self.a(i);
                    if signed {
                        self.fo("movwf", &m);
                    } else {
                        self.fo("clrf", &m);
                    }
                }
            }
        }
        if r == 0 {
            return;
        }
        let one = |g: &mut Self| {
            if left {
                g.ins("bcf STATUS, 0, c");
                for i in q..n {
                    let m = g.a(i);
                    g.fop("rlcf", &m, "f");
                }
            } else {
                if signed {
                    let top = g.a(n - 1);
                    g.fop("movf", &top, "w");
                    g.ins("rlcf WREG, w, c");
                } else {
                    g.ins("bcf STATUS, 0, c");
                }
                for i in (0..n - q).rev() {
                    let m = g.a(i);
                    g.fop("rrcf", &m, "f");
                }
            }
        };
        if r <= 2 {
            for _ in 0..r {
                one(self);
            }
        } else {
            let d = self.d(0);
            self.ins(format!("movlw {r}"));
            self.fo("movwf", &d);
            let l = self.fresh();
            self.label(&l);
            one(self);
            self.fop("decfsz", &d, "f");
            self.br(Cc::Always, &l);
        }
    }

    // ---- conditions -----------------------------------------------------------------------

    /// Jumps to `target` when `e` evaluates to `when`; falls through otherwise.
    fn cond_jump(&mut self, e: &Ex, when: bool, target: &str) {
        match &e.k {
            ExK::Const(v) => {
                if (*v != 0) == when {
                    self.br(Cc::Always, target);
                }
            }
            ExK::NotB(x) => self.cond_jump(x, !when, target),
            ExK::AndAlso(a, b) => {
                if !when {
                    self.cond_jump(a, false, target);
                    self.cond_jump(b, false, target);
                } else {
                    let skip = self.fresh();
                    self.cond_jump(a, false, &skip);
                    self.cond_jump(b, true, target);
                    self.label(&skip);
                }
            }
            ExK::OrElse(a, b) => {
                if when {
                    self.cond_jump(a, true, target);
                    self.cond_jump(b, true, target);
                } else {
                    let skip = self.fresh();
                    self.cond_jump(a, true, &skip);
                    self.cond_jump(b, false, target);
                    self.label(&skip);
                }
            }
            ExK::Cmp(k, l, r) => {
                let kind = if when { *k } else { k.negate() };
                self.cmp_jump(kind, l, r, target);
            }
            ExK::Load(p) if p.bit.is_some() => {
                let m = self.place_mem(p, false);
                // btfsc skips the branch when the bit is clear.
                self.fbit(if when { "btfsc" } else { "btfss" }, &m, p.bit.unwrap());
                self.br(Cc::Always, target);
            }
            ExK::Load(p) if p.bytes() == 1 && !p.indirect() => {
                let m = self.place_mem(p, false);
                self.fop("movf", &m, "f");
                self.br(if when { Cc::Nz } else { Cc::Z }, target);
            }
            _ => {
                // Any other Boolean value: evaluate it and test W.
                self.gen_val(e);
                if Self::nb(e) > 1 {
                    self.err("internal: a truth value wider than one byte");
                    return;
                }
                self.ins("iorlw 0");
                self.br(if when { Cc::Nz } else { Cc::Z }, target);
            }
        }
    }

    fn cmp_jump(&mut self, kind: CmpKind, l: &Ex, r: &Ex, target: &str) {
        let n = Self::nb(l);
        let signed = l.signed;
        match kind {
            CmpKind::Eq | CmpKind::Ne => self.eq_jump(kind == CmpKind::Eq, l, r, n, target),
            _ => self.ord_jump(kind, l, r, n, signed, target),
        }
    }

    fn eq_jump(&mut self, eq: bool, l: &Ex, r: &Ex, n: u32, target: &str) {
        let mut ls = self.simple(l);
        let mut rs = self.simple(r);
        if r.has_call() && matches!(ls, Some(Src::Mem(..))) {
            ls = None;
        }
        let mut held = 0;
        if n == 1 {
            // `x = 0` and `x <> 0` need no W: movf sets Z.
            for (a, b) in [(&ls, &rs), (&rs, &ls)] {
                if let (Some(Src::Mem(m, _)), Some(Src::Imm(0))) = (a, b) {
                    let m = m.clone();
                    self.fop("movf", &m, "f");
                    self.br(if eq { Cc::Z } else { Cc::Nz }, target);
                    return;
                }
            }
            let other = match (&ls, &rs) {
                (Some(a), Some(b)) => {
                    // Start from a memory operand so a constant folds into the xor.
                    let (first, second) = if matches!(a, Src::Imm(_)) && matches!(b, Src::Mem(..)) { (b, a) } else { (a, b) };
                    let fb = first.byte(0);
                    self.src_to_w(&fb);
                    second.byte(0)
                }
                (None, Some(b)) => {
                    self.gen_val(l);
                    b.byte(0)
                }
                (Some(a), None) => {
                    self.gen_val(r);
                    a.byte(0)
                }
                (None, None) => {
                    let t = self.spill(l);
                    held = 1;
                    self.gen_val(r);
                    Bs::Mem(t)
                }
            };
            match other {
                Bs::Imm(k) => self.ins(format!("xorlw 0x{k:02X}")),
                Bs::Mem(m) => self.fop("xorwf", &m, "w"),
            }
            self.br(if eq { Cc::Z } else { Cc::Nz }, target);
            if held > 0 {
                self.free(held);
            }
            return;
        }
        // Wide: both operands as byte sources.
        if ls.is_none() && rs.is_none() {
            let t = self.spill(l);
            held += n;
            ls = Some(Src::Mem(t, n));
        }
        if rs.is_none() {
            self.gen_val(r);
            rs = Some(Src::Mem(self.a(0), n));
        }
        if ls.is_none() {
            self.gen_val(l);
            ls = Some(Src::Mem(self.a(0), n));
        }
        let (ls, rs) = (ls.unwrap(), rs.unwrap());
        let skip = self.fresh();
        for i in 0..n {
            let (lb, rb) = (ls.byte(i), rs.byte(i));
            match (&lb, &rb) {
                (Bs::Imm(_), Bs::Mem(_)) => {
                    self.src_to_w(&rb);
                    if let Bs::Imm(k) = lb {
                        self.ins(format!("xorlw 0x{k:02X}"));
                    }
                }
                _ => {
                    self.src_to_w(&lb);
                    match rb {
                        Bs::Imm(k) => self.ins(format!("xorlw 0x{k:02X}")),
                        Bs::Mem(m) => self.fop("xorwf", &m, "w"),
                    }
                }
            }
            if eq {
                // Any differing byte means not equal; only the last byte can take the branch.
                if i + 1 < n {
                    self.br(Cc::Nz, &skip);
                } else {
                    self.br(Cc::Z, target);
                }
            } else {
                self.br(Cc::Nz, target);
            }
        }
        if eq {
            self.label(&skip);
        }
        if held > 0 {
            self.free(held);
        }
    }

    /// Branches on the flags of `X - Y` (already computed) for `X < Y` / `X >= Y`.
    fn flag_branch(&mut self, lt: bool, signed: bool, target: &str) {
        if !signed {
            self.br(if lt { Cc::Nc } else { Cc::C }, target);
            return;
        }
        // Signed order is N xor OV.
        let (lov, fall) = (self.fresh(), self.fresh());
        self.br(Cc::Ov, &lov);
        self.br(if lt { Cc::N } else { Cc::Nn }, target);
        self.br(Cc::Always, &fall);
        self.label(&lov);
        self.br(if lt { Cc::Nn } else { Cc::N }, target);
        self.label(&fall);
    }

    fn ord_jump(&mut self, kind: CmpKind, l: &Ex, r: &Ex, n: u32, signed: bool, target: &str) {
        // Reduce to `X < Y` or `X >= Y`, swapping the operands for > and <=.
        let swapped = matches!(kind, CmpKind::Gt | CmpKind::Le);
        let lt = matches!(kind, CmpKind::Lt | CmpKind::Gt);
        let mut ls = self.simple(l);
        let mut rs = self.simple(r);
        if r.has_call() && matches!(ls, Some(Src::Mem(..))) {
            ls = None;
        }
        let mut held = 0;
        if ls.is_none() && rs.is_none() {
            // Both need code: evaluate `l` first and keep it.
            let t = self.spill(l);
            held += n;
            ls = Some(Src::Mem(t, n));
        }
        let (xe, ye, mut xs, mut ys) = if swapped { (r, l, rs.take(), ls.take()) } else { (l, r, ls.take(), rs.take()) };
        // X must be constant or memory.
        if xs.is_none() {
            let t = self.spill(xe);
            held += n;
            xs = Some(Src::Mem(t, n));
        }
        let xs = xs.unwrap();
        if n == 1 {
            match ys.take() {
                Some(s) => {
                    let b = s.byte(0);
                    self.src_to_w(&b);
                }
                None => self.gen_val(ye),
            }
            match xs.byte(0) {
                Bs::Imm(k) => self.ins(format!("sublw 0x{k:02X}")),
                Bs::Mem(m) => self.fop("subwf", &m, "w"),
            }
        } else {
            // Y first when it needs code (it may use __B), then X as memory.
            if ys.is_none() {
                self.gen_val(ye);
                ys = Some(Src::Mem(self.a(0), n));
            }
            let ys = ys.unwrap();
            let xm = match xs {
                Src::Mem(m, real) if real == n => m,
                other => {
                    self.src_to_reg(1, &other, n);
                    self.b(0)
                }
            };
            // Signed: add 0x80 to both top bytes and compare unsigned, so only the carry chain
            // matters (the overflow flag of a multi-byte subtract is not relied on).
            if signed {
                let (d2, d3) = (self.d(2), self.d(3));
                self.fop("movf", &xm.at(n - 1), "w");
                self.ins("xorlw 0x80");
                self.fo("movwf", &d2);
                let yb = ys.byte(n - 1);
                self.src_to_w(&yb);
                self.ins("xorlw 0x80");
                self.fo("movwf", &d3);
            }
            for i in 0..n {
                if signed && i + 1 == n {
                    let (d2, d3) = (self.d(2), self.d(3));
                    self.fop("movf", &d3, "w");
                    self.fop("subwfb", &d2, "w");
                } else {
                    let yb = ys.byte(i);
                    self.src_to_w(&yb);
                    self.fop(if i == 0 { "subwf" } else { "subwfb" }, &xm.at(i), "w");
                }
            }
        }
        self.flag_branch(lt, signed && n == 1, target);
        if held > 0 {
            self.free(held);
        }
    }

    // ---- statements -----------------------------------------------------------------------

    fn store(&mut self, p: &Place, e: &Ex) {
        if p.indirect() {
            // The value is settled before FSR0 is loaded, since computing either can use FSR0.
            let n = p.bytes();
            let post = self.sfr_mem("POSTINC0");
            if let Some(s) = self.simple(e) {
                self.point_fsr0(p);
                for i in 0..n {
                    self.put_byte(&post, &s.byte(i));
                }
            } else {
                let t = self.spill(e);
                self.point_fsr0(p);
                for i in 0..n {
                    self.movff(&post, &t.at(i));
                }
                self.free(n);
            }
            return;
        }
        if let Some(b) = p.bit {
            self.store_bit(p, b, e);
            return;
        }
        let n = p.bytes();
        let dst = self.place_mem(p, true);
        if let Some(s) = self.simple(e) {
            self.store_src(&dst, n, &s);
            return;
        }
        // In-place read-modify-write: `x = x op operand`.
        if let ExK::Bin(op, l, r) = &e.k
            && matches!(op, BinKind::Add | BinKind::Sub | BinKind::And | BinKind::Or | BinKind::Xor)
            && let ExK::Load(lp) = &l.k
            && lp.bit.is_none()
            && !lp.indirect()
            && lp.base == p.base
            && lp.off == p.off
            && self.place_mem(lp, false).sym == dst.sym
            && l.w == e.w
            && let Some(rs) = self.simple(r)
        {
            let d2 = dst.clone();
            self.chain(*op, &move |_g: &mut Self, i| d2.at(i), &rs, n);
            return;
        }
        self.gen_val(e);
        if n == 1 {
            self.fo("movwf", &dst);
        } else {
            for i in 0..n {
                let a = self.a(i);
                self.put_byte(&dst.at(i), &Bs::Mem(a));
            }
        }
    }

    fn store_bit(&mut self, p: &Place, b: u8, e: &Ex) {
        let dst = self.place_mem(p, true);
        if let Some(v) = e.as_const() {
            self.fbit(if v & 1 != 0 { "bsf" } else { "bcf" }, &dst, b);
            return;
        }
        // Copy of another bit.
        if let ExK::Load(sp) = &e.k
            && let Some(sb) = sp.bit
        {
            let src = self.place_mem(sp, false);
            if src.sym == dst.sym && sb == b {
                return;
            }
            let (sa, da) = (is_access(self.tgt, src.addr), is_access(self.tgt, dst.addr));
            let same_bank = src.addr.zip(dst.addr).is_some_and(|(x, y)| x >> 8 == y >> 8);
            if (sa && da) || same_bank || (self.layout.is_none()) {
                self.fbit("bcf", &dst, b);
                self.fbit("btfsc", &src, sb);
                self.fbit("bsf", &dst, b);
                return;
            }
        }
        let (lf, le) = (self.fresh(), self.fresh());
        self.cond_jump(e, false, &lf);
        self.fbit("bsf", &dst, b);
        self.br(Cc::Always, &le);
        self.label(&lf);
        self.fbit("bcf", &dst, b);
        self.label(&le);
    }

    fn add_const(&mut self, p: &Place, delta: u32) {
        let n = p.bytes();
        let dst = self.place_mem(p, true);
        let k = delta & mask((n * 8) as u8);
        if n == 1 && k == 1 {
            self.fop("incf", &dst, "f");
        } else if n == 1 && k == 0xFF {
            self.fop("decf", &dst, "f");
        } else {
            let d2 = dst.clone();
            self.chain(BinKind::Add, &move |_g: &mut Self, i| d2.at(i), &Src::Imm(k), n);
        }
    }

    fn do_call(&mut self, f: FuncId, args: &[(Place, Ex)]) {
        self.called.insert(f);
        // Arguments that contain calls are evaluated first, so a nested call cannot overwrite
        // a parameter that was already stored.
        let nested = args.len() > 1 && args.iter().any(|(_, e)| e.has_call());
        if nested {
            let mut temps = Vec::new();
            for (_, e) in args {
                let t = self.spill(e);
                temps.push((t, Self::nb(e)));
            }
            for ((pl, _), (t, n)) in args.iter().zip(&temps) {
                let dst = self.place_mem(pl, true);
                self.store_src(&dst, *n, &Src::Mem(t.clone(), *n));
            }
            let total: u32 = temps.iter().map(|t| t.1).sum();
            self.free(total);
        } else {
            for (pl, e) in args {
                self.store(pl, e);
            }
        }
        self.items.push(Item::Call(self.p.funcs[f].asm.clone()));
        self.bsr = None;
    }

    fn block(&mut self, ss: &[S]) {
        for s in ss {
            self.stmt(s);
        }
    }

    fn stmt(&mut self, s: &S) {
        self.span = s.span;
        match &s.st {
            St::Assign(p, e) => self.store(p, e),
            St::Add(p, d) => self.add_const(p, *d),
            St::StrSet { dst, cap, parts, keep } => self.str_set(dst, *cap, parts, *keep),
            St::SetBit(p, v) => {
                let m = self.place_mem(p, true);
                self.fbit(if *v { "bsf" } else { "bcf" }, &m, p.bit.unwrap());
            }
            St::ToggleBit(p) => {
                let m = self.place_mem(p, true);
                self.fbit("btg", &m, p.bit.unwrap());
            }
            St::Clear(p) => {
                let m = self.place_mem(p, true);
                if let Some(b) = p.bit {
                    self.fbit("bcf", &m, b);
                } else {
                    for i in 0..p.bytes() {
                        self.fo("clrf", &m.at(i));
                    }
                }
            }
            St::Direction { place, output } => self.direction(place, *output),
            St::Call(f, args) => self.do_call(*f, args),
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
                        self.br(Cc::Always, &end);
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
                self.depth += 1;
                if c.as_const().is_some_and(|v| v != 0) {
                    self.label(&top);
                    self.loops.push((top.clone(), end.clone()));
                    self.block(body);
                    self.loops.pop();
                    self.br(Cc::Always, &top);
                } else {
                    self.br(Cc::Always, &cond);
                    self.label(&top);
                    self.loops.push((cond.clone(), end.clone()));
                    self.block(body);
                    self.loops.pop();
                    self.label(&cond);
                    self.cond_jump(c, true, &top);
                }
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
                self.cond_jump(c, false, &top);
                self.depth -= 1;
                self.label(&end);
            }
            St::For { var, from, limit, step, body } => self.for_loop(var, from, limit, *step, body),
            St::Break => {
                if let Some((_, end)) = self.loops.last().cloned() {
                    self.br(Cc::Always, &end);
                }
            }
            St::Continue => {
                if let Some((cont, _)) = self.loops.last().cloned() {
                    self.br(Cc::Always, &cont);
                }
            }
            St::Return => self.ins("return"),
            St::Goto(l) => {
                let name = self.p.label_names[*l].clone();
                self.br(Cc::Always, &name);
            }
            St::Label(l) => {
                let name = self.p.label_names[*l].clone();
                self.label(&name);
            }
            St::Asm(lines) => {
                // Variables named in the block need storage.
                for l in lines {
                    for tok in l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')) {
                        if let Some(i) = self.p.vars.iter().position(|v| v.asm == tok) {
                            self.uses[i] += weight(self.depth);
                        }
                    }
                }
                for l in lines {
                    self.items.push(Item::Raw(l.clone()));
                }
                self.bsr = None;
            }
            St::DelayUs(e) => self.delay(e, false),
            St::DelayMs(e) => self.delay(e, true),
            St::Halt => {
                let l = self.fresh();
                self.label(&l);
                self.br(Cc::Always, &l);
            }
        }
    }

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
        let m = Mem { sym: t, addr: Some(ta), obj: None, reg: true }.at(p.off);
        match p.bit {
            Some(b) => self.fbit(if output { "bcf" } else { "bsf" }, &m, b),
            None => {
                for i in 0..p.bytes() {
                    self.fo(if output { "clrf" } else { "setf" }, &m.at(i));
                }
            }
        }
    }

    fn for_loop(&mut self, var: &Place, from: &Ex, limit: &Ex, step: i64, body: &[S]) {
        let (w, sg) = (var.width(), var.signed());
        let load = |p: &Place| Ex::new(ExK::Load(p.clone()), w, sg);
        self.store(var, from);
        let (top, cont, end) = (self.fresh(), self.fresh(), self.fresh());
        // Skip the entry test when both ends are constants that make the loop run.
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
            self.cmp_jump(kind, &load(var), limit, &end);
        }
        self.label(&top);
        self.loops.push((cont.clone(), end.clone()));
        self.block(body);
        self.loops.pop();
        self.label(&cont);
        if step == 1 || step == -1 {
            self.cmp_jump(CmpKind::Eq, &load(var), limit, &end);
        } else {
            // Exit when fewer than |step| remain, so the counter never wraps past the limit.
            let (a, b) = if step > 0 { (limit.clone(), load(var)) } else { (load(var), limit.clone()) };
            let rem = Ex::new(ExK::Bin(BinKind::Sub, Box::new(Ex { signed: false, ..a }), Box::new(Ex { signed: false, ..b })), w, false);
            let k = Ex::konst(step.unsigned_abs() as u32, w, false);
            self.cmp_jump(CmpKind::Lt, &rem, &k, &end);
        }
        self.add_const(var, step as u32);
        self.br(Cc::Always, &top);
        self.depth -= 1;
        self.label(&end);
    }

    // ---- delays ---------------------------------------------------------------------------

    fn fcy_per_us(&self) -> f64 {
        self.p.clock_mhz / 4.0
    }

    fn delay(&mut self, e: &Ex, ms: bool) {
        if self.p.clock_mhz <= 0.0 {
            self.err("DelayMS/DelayUS need a `Clock = <MHz>` line");
            return;
        }
        if let Some(n) = e.as_const() {
            let per = if ms { self.fcy_per_us() * 1000.0 } else { self.fcy_per_us() };
            let cycles = (n as f64 * per).round() as u64;
            self.emit_cycles(cycles, 0);
            return;
        }
        if e.w > 16 {
            self.err("a variable delay takes a Byte or Word");
            return;
        }
        let exact = if ms { self.fcy_per_us() * 1000.0 } else { self.fcy_per_us() };
        if (exact - exact.round()).abs() > 1e-9 {
            self.err(format!("at Clock = {} MHz one {} is {exact} cycles; a variable delay needs a whole number (use a constant)", self.p.clock_mhz, if ms { "millisecond" } else { "microsecond" }));
            return;
        }
        let per = exact.round() as i64;
        // The loop adds six cycles of its own per pass.
        let body = per - 6;
        if body < 0 {
            self.err("a variable DelayUS needs a Clock of at least 24 MHz; use a constant");
            return;
        }
        // 16-bit counter in D0:D1, zero-guarded, counting down to a borrow.
        self.gen_to_acc_16(e);
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
        self.movff(&d0, &a0);
        self.movff(&d1, &a1);
        let lp = self.fresh();
        self.label(&lp);
        self.emit_cycles(body as u64, 2);
        self.ins("movlw 1");
        self.fop("subwf", &d0, "f");
        self.ins("movlw 0");
        self.fop("subwfb", &d1, "f");
        self.br(Cc::C, &lp);
        self.label(&skip);
    }

    fn gen_to_acc_16(&mut self, e: &Ex) {
        if e.w == 8 {
            self.gen_to_acc(e);
            let a1 = self.a(1);
            self.fo("clrf", &a1);
        } else {
            self.gen_to_acc(e);
        }
    }

    /// Emits code that takes exactly `n` cycles, using counter registers from `D<first>` up.
    fn emit_cycles(&mut self, n: u64, first: u32) {
        if n == 0 {
            return;
        }
        if n <= 12 {
            for _ in 0..n / 2 {
                let l = self.fresh();
                self.br(Cc::Always, &l);
                self.items.push(Item::Label(l));
            }
            if n % 2 == 1 {
                self.ins("nop");
            }
            return;
        }
        if n <= 769 {
            // setup 2 + 3c + (-1) ... one counter loop costs 3c + 1 cycles for c in 1..=256
            let c = ((n - 1) / 3).clamp(1, 256);
            let used = 3 * c + 1;
            let ctr = self.d(first);
            self.ins(format!("movlw {}", c & 0xFF));
            self.fo("movwf", &ctr);
            let l = self.fresh();
            self.label(&l);
            self.fop("decfsz", &ctr, "f");
            self.br(Cc::Always, &l);
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
        self.label(&l);
        self.emit_cycles(p, first + 1);
        self.fop("decfsz", &ctr, "f");
        self.br(Cc::Always, &l);
        self.emit_cycles(n - used, first);
    }

    // ---- helper routines ------------------------------------------------------------------

    fn emit_helper(&mut self, name: &str) {
        let num: u32 = name.chars().last().and_then(|c| c.to_digit(10)).unwrap_or(1);
        let n = num;
        let kind = &name[..name.len() - 1];
        self.cur = self.p.funcs.len();
        self.cur_asm = format!("__{name}");
        self.label(&format!("__{name}"));
        self.bsr = None;
        match kind {
            "mul" => {
                for i in 0..n {
                    let c = self.c(i);
                    self.fo("clrf", &c);
                }
                let d0 = self.d(0);
                self.ins(format!("movlw {}", 8 * n));
                self.fo("movwf", &d0);
                let (lp, sk) = (self.fresh(), self.fresh());
                self.label(&lp);
                self.ins("bcf STATUS, 0, c");
                for i in (0..n).rev() {
                    let b = self.b(i);
                    self.fop("rrcf", &b, "f");
                }
                self.br(Cc::Nc, &sk);
                for i in 0..n {
                    let (a, c) = (self.a(i), self.c(i));
                    self.fop("movf", &a, "w");
                    self.fop(if i == 0 { "addwf" } else { "addwfc" }, &c, "f");
                }
                self.label(&sk);
                self.ins("bcf STATUS, 0, c");
                for i in 0..n {
                    let a = self.a(i);
                    self.fop("rlcf", &a, "f");
                }
                self.fop("decfsz", &d0, "f");
                self.br(Cc::Always, &lp);
                for i in 0..n {
                    let (a, c) = (self.a(i), self.c(i));
                    self.movff(&a, &c);
                }
                self.ins("return");
            }
            "div" => {
                for i in 0..n {
                    let c = self.c(i);
                    self.fo("clrf", &c);
                }
                let d0 = self.d(0);
                self.ins(format!("movlw {}", 8 * n));
                self.fo("movwf", &d0);
                let (lp, dosub, setq, next) = (self.fresh(), self.fresh(), self.fresh(), self.fresh());
                self.label(&lp);
                self.ins("bcf STATUS, 0, c");
                for i in 0..n {
                    let a = self.a(i);
                    self.fop("rlcf", &a, "f");
                }
                for i in 0..n {
                    let c = self.c(i);
                    self.fop("rlcf", &c, "f");
                }
                self.br(Cc::C, &dosub);
                self.sub_cb(n);
                self.br(Cc::C, &setq);
                for i in 0..n {
                    let (b, c) = (self.b(i), self.c(i));
                    self.fop("movf", &b, "w");
                    self.fop(if i == 0 { "addwf" } else { "addwfc" }, &c, "f");
                }
                self.br(Cc::Always, &next);
                self.label(&dosub);
                self.sub_cb(n);
                self.label(&setq);
                let a0 = self.a(0);
                self.fbit("bsf", &a0, 0);
                self.label(&next);
                self.fop("decfsz", &d0, "f");
                self.br(Cc::Always, &lp);
                self.ins("return");
            }
            "sdiv" => {
                // Signs: D1 bit 0 = dividend negative, bit 1 = divisor negative.
                let d1 = self.d(1);
                self.fo("clrf", &d1);
                let (pa, pb) = (self.fresh(), self.fresh());
                let top = self.a(n - 1);
                self.fbit("btfss", &top, 7);
                self.br(Cc::Always, &pa);
                self.fbit("bsf", &d1, 0);
                self.neg_reg(0, n);
                self.label(&pa);
                let topb = self.b(n - 1);
                self.fbit("btfss", &topb, 7);
                self.br(Cc::Always, &pb);
                self.fbit("bsf", &d1, 1);
                self.neg_reg(1, n);
                self.label(&pb);
                self.call_helper(format!("div{n}"));
                let (qd, rd) = (self.fresh(), self.fresh());
                // quotient negative when exactly one operand was
                self.fop("movf", &d1, "w");
                self.ins("andlw 3");
                self.ins("xorlw 1");
                self.br(Cc::Z, &qd);
                self.fop("movf", &d1, "w");
                self.ins("andlw 3");
                self.ins("xorlw 2");
                self.br(Cc::Z, &qd);
                self.br(Cc::Always, &rd);
                self.label(&qd);
                self.neg_reg(0, n);
                self.label(&rd);
                // remainder takes the dividend's sign
                let end = self.fresh();
                self.fbit("btfss", &d1, 0);
                self.br(Cc::Always, &end);
                self.neg_reg(2, n);
                self.label(&end);
                self.ins("return");
            }
            "shl" | "shr" | "sar" => {
                let d1 = self.d(1);
                let (lp, done) = (self.fresh(), self.fresh());
                self.fop("movf", &d1, "f");
                self.br(Cc::Z, &done);
                self.label(&lp);
                match kind {
                    "shl" => {
                        self.ins("bcf STATUS, 0, c");
                        for i in 0..n {
                            let a = self.a(i);
                            self.fop("rlcf", &a, "f");
                        }
                    }
                    "shr" => {
                        self.ins("bcf STATUS, 0, c");
                        for i in (0..n).rev() {
                            let a = self.a(i);
                            self.fop("rrcf", &a, "f");
                        }
                    }
                    _ => {
                        let top = self.a(n - 1);
                        self.fop("movf", &top, "w");
                        self.ins("rlcf WREG, w, c");
                        for i in (0..n).rev() {
                            let a = self.a(i);
                            self.fop("rrcf", &a, "f");
                        }
                    }
                }
                self.fop("decfsz", &d1, "f");
                self.br(Cc::Always, &lp);
                self.label(&done);
                self.ins("return");
            }
            // String helpers. FSR0 is the destination (or the left string), FSR1 a RAM source,
            // TBLPTR a source in program memory, `__D0` the room left in the destination.
            "strr" | "strf" => {
                let (lp, done) = (self.fresh(), self.fresh());
                let d0 = self.d(0);
                self.label(&lp);
                self.fop("movf", &d0, "f");
                self.br(Cc::Z, &done);
                if kind == "strr" {
                    self.ins("movf POSTINC1, w, c");
                } else {
                    self.ins("tblrd*+");
                    self.ins("movf TABLAT, w, c");
                }
                self.br(Cc::Z, &done);
                self.ins("movwf POSTINC0, c");
                self.fop("decf", &d0, "f");
                self.br(Cc::Always, &lp);
                self.label(&done);
                self.ins("clrf INDF0, c");
                self.ins("return");
            }
            "strc" => {
                let done = self.fresh();
                let d0 = self.d(0);
                self.ins("iorlw 0");
                self.br(Cc::Z, &done);
                self.fop("movf", &d0, "f");
                self.br(Cc::Z, &done);
                self.ins("movwf POSTINC0, c");
                self.fop("decf", &d0, "f");
                self.label(&done);
                self.ins("clrf INDF0, c");
                self.ins("return");
            }
            "stre" => {
                let (lp, done) = (self.fresh(), self.fresh());
                let d0 = self.d(0);
                self.label(&lp);
                self.ins("movf INDF0, f, c");
                self.br(Cc::Z, &done);
                self.fop("movf", &d0, "f");
                self.br(Cc::Z, &done);
                self.ins("movf POSTINC0, w, c");
                self.fop("decf", &d0, "f");
                self.br(Cc::Always, &lp);
                self.label(&done);
                self.ins("return");
            }
            "strqr" | "strqf" => {
                let (lp, ne) = (self.fresh(), self.fresh());
                let d0 = self.d(0);
                self.label(&lp);
                if kind == "strqr" {
                    self.ins("movf POSTINC1, w, c");
                } else {
                    self.ins("tblrd*+");
                    self.ins("movf TABLAT, w, c");
                }
                self.fo("movwf", &d0);
                self.ins("movf POSTINC0, w, c");
                self.fop("xorwf", &d0, "w");
                self.br(Cc::Nz, &ne);
                self.fop("movf", &d0, "f");
                self.br(Cc::Nz, &lp);
                self.ins("retlw 1");
                self.label(&ne);
                self.ins("retlw 0");
            }
            _ => self.err(format!("unknown helper {name}")),
        }
    }

    /// `C -= B` over `n` bytes (borrow ends in the carry flag).
    fn sub_cb(&mut self, n: u32) {
        for i in 0..n {
            let (b, c) = (self.b(i), self.c(i));
            self.fop("movf", &b, "w");
            self.fop(if i == 0 { "subwf" } else { "subwfb" }, &c, "f");
        }
    }

    /// Negates scratch register `r` in place.
    fn neg_reg(&mut self, r: usize, n: u32) {
        for i in (1..n).rev() {
            let m = self.scr(r, i);
            self.fop("comf", &m, "f");
        }
        let m0 = self.scr(r, 0);
        self.fo("negf", &m0);
        self.ins("movlw 0");
        for i in 1..n {
            let m = self.scr(r, i);
            self.fop("addwfc", &m, "f");
        }
    }
}

fn sign_ext(v: u32, w: u8) -> i64 {
    if w >= 32 {
        v as i32 as i64
    } else if v & (1 << (w - 1)) != 0 {
        (v | !mask(w)) as i32 as i64
    } else {
        v as i64
    }
}

// ---- driver -----------------------------------------------------------------------------

pub struct Generated {
    pub out: Output,
    pub objs: Vec<Obj>,
    pub layout: Layout,
    pub errors: Vec<(Span, String)>,
}

/// Runs one generation pass over the whole program.
fn run_pass<'p>(p: &'p Program, tgt: &'p Target, layout: Option<&'p Layout>) -> (Gen<'p>, Vec<Item>) {
    // Safety: the generator borrows `p`, `tgt` and `layout` for the same lifetime.
    let mut g = Gen::new(p, tgt, layout);
    // Start-up.
    g.cur = p.funcs.len();
    g.cur_asm = p.main.asm.clone();
    g.items.push(Item::Label("__reset".into()));
    g.startup();
    g.block(&p.main.body);
    let halt = "__halt".to_string();
    g.label(&halt);
    g.br(Cc::Always, &halt);
    // Reachable routines, in call order.
    let mut done: BTreeSet<FuncId> = BTreeSet::new();
    let mut order = Vec::new();
    loop {
        let next = g.called.iter().find(|f| !done.contains(f)).copied();
        let Some(f) = next else { break };
        done.insert(f);
        order.push(f);
        let func = &p.funcs[f];
        g.cur = f;
        g.cur_asm = func.asm.clone();
        g.temp_cur = 0;
        g.depth = 0;
        g.bsr = None;
        g.items.push(Item::Comment(format!("Sub/Function {}", func.name)));
        g.label(&func.asm);
        g.block(&func.body);
    }
    // Helpers (which may call others).
    let mut emitted: BTreeSet<String> = BTreeSet::new();
    loop {
        let next = g.helpers.iter().find(|h| !emitted.contains(*h)).cloned();
        let Some(h) = next else { break };
        emitted.insert(h.clone());
        g.items.push(Item::Comment(format!("helper {h}")));
        g.emit_helper(&h);
    }
    // String literals follow the code, each Null-terminated and padded to a whole word.
    for (n, lit) in std::mem::take(&mut g.lits).into_iter().enumerate() {
        let mut bytes = lit.clone();
        bytes.push(0);
        if bytes.len() % 2 == 1 {
            bytes.push(0);
        }
        g.items.push(Item::Label(format!("__STR{n}")));
        g.items.push(Item::Data(bytes));
        g.lits.push(lit);
    }
    let items = std::mem::take(&mut g.items);
    (g, items)
}

impl<'p> Gen<'p> {
    /// Zeroing of variables and initial values, then the body.
    fn startup(&mut self) {
        let Some(layout) = self.layout else { return };
        // Zero ranges: all allocated user variables, merged.
        let mut ranges: Vec<(u32, u32)> = Vec::new();
        for (i, v) in self.p.vars.iter().enumerate() {
            if let Some(a) = layout.addr[i] {
                ranges.push((a, a + v.bytes));
            }
        }
        ranges.sort();
        let mut merged: Vec<(u32, u32)> = Vec::new();
        for r in ranges {
            match merged.last_mut() {
                Some(l) if l.1 == r.0 => l.1 = r.1,
                _ => merged.push(r),
            }
        }
        // Variables that are about to be given a value need no clearing.
        let inits: Vec<(usize, u32)> = self.p.vars.iter().enumerate().filter(|(i, v)| v.init.is_some() && layout.addr[*i].is_some() && v.kind == VarKind::Global).map(|(i, v)| (i, v.init.unwrap())).collect();
        let mut covered: BTreeSet<u32> = BTreeSet::new();
        for (i, _) in &inits {
            let a = layout.addr[*i].unwrap();
            for b in 0..self.p.vars[*i].bytes {
                covered.insert(a + b);
            }
        }
        for (s, e) in merged {
            let mut run: Option<u32> = None;
            let mut spans: Vec<(u32, u32)> = Vec::new();
            for a in s..=e {
                let need = a < e && !covered.contains(&a);
                match (need, run) {
                    (true, None) => run = Some(a),
                    (false, Some(r)) => {
                        spans.push((r, a));
                        run = None;
                    }
                    _ => {}
                }
            }
            for (a, b) in spans {
                self.zero_range(a, b - a);
            }
        }
        for (i, v) in inits {
            let ty = &self.p.vars[i].ty;
            let _ = ty;
            let m = self.mem_obj(i, self.p.vars[i].asm.clone());
            let n = self.p.vars[i].bytes;
            self.store_src(&m, n, &Src::Imm(v));
        }
    }

    fn zero_range(&mut self, addr: u32, len: u32) {
        let mem = |a: u32| Mem { sym: format!("0x{a:03X}"), addr: Some(a), obj: None, reg: false };
        if len <= 4 {
            for i in 0..len {
                self.fo("clrf", &mem(addr + i));
            }
            return;
        }
        let mut a = addr;
        let mut left = len;
        while left > 0 {
            let chunk = left.min(255);
            self.ins(format!("lfsr 0, 0x{a:03X}"));
            self.ins(format!("movlw {chunk}"));
            let l = self.fresh();
            self.label(&l);
            self.ins("clrf POSTINC0, c");
            self.ins("decfsz WREG, f, c");
            self.br(Cc::Always, &l);
            a += chunk;
            left -= chunk;
        }
    }
}

pub fn generate(p: &Program, tgt: &Target) -> Generated {
    // Pass 1 sizes the objects; later passes emit code against the layout and repeat with the
    // sizes they actually needed until the two agree.
    let (g1, _) = run_pass(p, tgt, None);
    let mut uses = g1.uses.clone();
    let mut scratch = g1.scratch_max;
    let mut temps = g1.temp_max.clone();
    let mut errors: Vec<(Span, String)> = Vec::new();
    let pass1_errors = g1.errors.clone();
    let nvars = p.vars.len();
    drop(g1);
    let mut result = None;
    for _round in 0..4 {
        let mut objs: Vec<Obj> = Vec::new();
        for (i, v) in p.vars.iter().enumerate() {
            objs.push(Obj { name: v.asm.clone(), bytes: if uses[i] > 0 { v.bytes } else { 0 }, weight: uses[i], force_access: false, zero: true });
        }
        for r in 0..4 {
            objs.push(Obj { name: format!("__{}", SCRATCH[r]), bytes: scratch[r], weight: u64::MAX, force_access: true, zero: false });
        }
        for f in 0..=p.funcs.len() {
            let asm = if f < p.funcs.len() { p.funcs[f].asm.clone() } else { p.main.asm.clone() };
            objs.push(Obj { name: format!("{asm}__TMP"), bytes: temps[f], weight: uses[nvars + 4 + f], force_access: false, zero: false });
        }
        let layout = match plan_layout(&objs, tgt) {
            Ok(l) => l,
            Err(e) => {
                errors.push((Span::default(), e));
                Layout { addr: vec![None; objs.len()] }
            }
        };
        let (g2, items) = run_pass(p, tgt, Some(&layout));
        let grew = (0..4).any(|r| g2.scratch_max[r] > scratch[r]) || (0..temps.len()).any(|f| g2.temp_max[f] > temps[f]) || (0..nvars).any(|i| g2.uses[i] > 0 && uses[i] == 0);
        if grew {
            for r in 0..4 {
                scratch[r] = scratch[r].max(g2.scratch_max[r]);
            }
            for f in 0..temps.len() {
                temps[f] = temps[f].max(g2.temp_max[f]);
            }
            for i in 0..uses.len() {
                uses[i] = uses[i].max(g2.uses[i]);
            }
            continue;
        }
        errors.extend(g2.errors.iter().cloned());
        let helpers: Vec<String> = g2.helpers.iter().cloned().collect();
        result = Some((objs, layout, items, helpers));
        break;
    }
    if errors.is_empty() && result.is_none() {
        errors = pass1_errors;
    }
    let Some((objs, layout, items, helpers)) = result else {
        errors.push((Span::default(), "internal: data layout did not settle".into()));
        return Generated { out: Output { text: String::new(), words: 0, labels: HashMap::new(), func_words: vec![] }, objs: vec![], layout: Layout::default(), errors };
    };
    let asmd: Assembled = assemble(&items, 0);
    let mut text = String::new();
    text.push_str(&format!("; basicc output for {}\n", p.device));
    text.push_str("#include <xc.inc>\n\n");
    for (name, _, v) in &p.config {
        text.push_str(&format!("CONFIG {name} = 0x{v:02X}\n"));
    }
    text.push_str("\n; ---- data (addresses chosen by the compiler)\n");
    for (i, o) in objs.iter().enumerate() {
        if let Some(a) = layout.addr[i] {
            if i >= nvars && i < nvars + 4 {
                let r = i - nvars;
                for k in 0..o.bytes {
                    text.push_str(&format!("__{}{} equ 0x{:03X}\n", SCRATCH[r], k, a + k));
                }
                continue;
            }
            let note = if i < nvars { format!("  ; {} ({} byte{})", p.vars[i].name, o.bytes, if o.bytes == 1 { "" } else { "s" }) } else { String::new() };
            text.push_str(&format!("{} equ 0x{:03X}{}\n", o.name, a, note));
        }
    }
    text.push_str("\nPSECT code,class=CODE,abs,delta=1\n    ORG 0x0000\n");
    for l in &asmd.lines {
        text.push_str(l);
        text.push('\n');
    }
    // Label table for tools (simulator harness): byte addresses of the non-local labels.
    let mut syms: Vec<(&String, &u32)> = asmd.labels.iter().filter(|(k, _)| !k.starts_with("_L")).collect();
    syms.sort();
    for (k, v) in syms {
        text.push_str(&format!(";SYM {k} 0x{:04X}\n", v * 2));
    }
    text.push_str("    END __reset\n");
    // Function sizes from label positions.
    let mut starts: Vec<(String, u32)> = vec![("(start-up and program body)".into(), 0)];
    for f in &p.funcs {
        if let Some(&a) = asmd.labels.get(&f.asm) {
            starts.push((f.asm.clone(), a));
        }
    }
    for h in &helpers {
        if let Some(&a) = asmd.labels.get(&format!("__{h}")) {
            starts.push((format!("__{h}"), a));
        }
    }
    if let Some(&a) = asmd.labels.get("__STR0") {
        starts.push(("(string literals)".into(), a));
    }
    starts.sort_by_key(|s| s.1);
    let mut func_words = Vec::new();
    for (i, (n, a)) in starts.iter().enumerate() {
        let end = starts.get(i + 1).map(|s| s.1).unwrap_or(asmd.words);
        func_words.push((n.clone(), end - a));
    }
    Generated { out: Output { text, words: asmd.words, labels: asmd.labels, func_words }, objs, layout, errors }
}
