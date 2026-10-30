//! Enhanced mid-range (PIC16F1xxxx) code generator: IR in, pic-as assembly out.
//!
//! The same IR as the PIC18 generator, a simpler strategy. Facts are in `docs/FACTS-16F1714x.md`.
//!
//! Value model. An expression of 8 bits is evaluated into `WREG`, a wider one into the accumulator
//! `__A0..__A3` (little endian). `__B`, `__C` and `__D` are the second operand, the remainder or
//! product and the counter of the multiply, divide and shift helpers. All four sit in common RAM
//! (visible from every bank, so they never need a bank select). Every routine owns a temporary area
//! in its static frame for the partial results that must survive the evaluation of another operand.
//!
//! Memory. RAM is 80-byte blocks, one per bank (offsets 20h..6Fh), plus 16 bytes of common RAM. Direct
//! operands carry 7 address bits, so `movlb` selects the bank first; the generator remembers the bank it
//! selected (`bsr`) and forgets it at every label and call. Objects over 80 bytes are laid out across
//! consecutive banks, which the linear data memory (FSR 2000h up) shows as one run of bytes; they are
//! reached through an FSR. Indirect access uses `moviw`/`movwi` with FSR0 (and FSR1 for copies).
//!
//! Code. `call` and `goto` carry 11 address bits; a program over 2K words sets PCLATH before each (see
//! `assemble16`). The core has no conditional branches, only flag tests that skip, and no `N`/`OV`
//! flags: a signed comparison flips the sign bit of both operands and compares unsigned.

use crate::asm::{Assembled, Cc, Item, assemble16};
use crate::codegen::{Generated, Layout, Obj, Output, Target, independent};
use crate::diag::Span;
use crate::ir::*;
use std::collections::{BTreeSet, HashMap};

const SCRATCH: [&str; 4] = ["A", "B", "C", "D"];

mod emit;
mod expr;
mod helpers;
mod layout;
mod opt;
mod stmt;

pub use layout::plan_layout16;

/// A run of data memory starting at byte `off` of a symbol: the symbol written to the assembly and the data address of
/// the symbol itself (known once the layout is).
#[derive(Clone, Debug)]
pub(crate) struct Mem {
    pub sym: String,
    pub base: Option<u32>,
    pub off: u32,
    /// The bytes are program data in banked RAM, which a large object lays across banks (see `layout`); a fixed
    /// register or common RAM is plain `base + off`.
    pub lin: bool,
}

impl Mem {
    /// Data address of this byte (an object that crosses banks is not contiguous in data addresses).
    pub fn addr(&self) -> Option<u32> {
        self.base.map(|a| if self.lin { layout::phys_off(a, self.off) } else { a + self.off })
    }
    pub fn at(&self, k: u32) -> Mem {
        Mem { off: self.off + k, ..self.clone() }
    }
    /// The operand text: the symbol plus offset, or the plain address when the bytes are not contiguous.
    pub fn text(&self) -> String {
        match (self.base, self.addr()) {
            (Some(b), Some(a)) if self.lin && a != b + self.off => format!("0x{a:03X}"),
            _ if self.off == 0 => self.sym.clone(),
            _ => format!("{}+{}", self.sym, self.off),
        }
    }
}

/// A source byte of an operation.
#[derive(Clone, Debug)]
pub(crate) enum Sb {
    K(u8),
    M(Mem),
}

/// A whole operand of the byte-wise operations: a constant, memory, or memory zero-extended.
#[derive(Clone, Debug)]
pub(crate) enum Opd {
    K(u32),
    M(Mem),
    /// A memory operand of the given number of bytes, zero-extended.
    Z(Mem, u32),
}

pub(crate) struct G<'p> {
    pub p: &'p Program,
    pub tgt: &'p Target,
    pub layout: Option<&'p Layout>,
    pub items: Vec<Item>,
    pub bsr: Option<u32>,
    pub lbl: u32,
    pub uses: Vec<u64>,
    pub depth: u32,
    pub cur: usize,
    pub cur_asm: String,
    pub temp_cur: u32,
    pub temp_max: Vec<u32>,
    pub scratch_max: [u32; 4],
    pub loops: Vec<(String, String)>,
    pub called: BTreeSet<FuncId>,
    pub calls: Vec<BTreeSet<FuncId>>,
    pub helpers: BTreeSet<String>,
    pub errors: Vec<(Span, String)>,
    pub span: Span,
    pub nvars: usize,
    pub ranges: Vec<(FuncId, usize, usize)>,
    pub hranges: Vec<(String, usize, usize)>,
    pub save_max: Vec<u32>,
    pub isr_end: Option<String>,
    pub flash_used: BTreeSet<usize>,
    /// Scratch bytes in use in the previous round: the size of the registers a handler saves.
    pub isr_scratch: [u32; 4],
    /// Routines each routine calls, as the previous round found out (a `Save` copies the frames of everything its
    /// body can reach).
    pub prev_calls: Vec<BTreeSet<FuncId>>,
    /// `Save` blocks being generated: loop depth at entry and the restore copies.
    pub save_stack: Vec<(usize, Vec<(Mem, Mem)>)>,
    /// `reach[f]`: the routines `f` can reach through one or more calls (from the previous round's call graph).
    pub reach: Vec<BTreeSet<FuncId>>,
    /// The most bytes any recursive call site pushed on the software stack.
    pub soft_max: u32,
    /// String literals held in program memory, in first-use order (label `__STR<n>`).
    pub lits: Vec<Vec<u8>>,
}

fn reachability(calls: &[BTreeSet<FuncId>]) -> Vec<BTreeSet<FuncId>> {
    (0..calls.len())
        .map(|f| {
            let mut seen: BTreeSet<FuncId> = BTreeSet::new();
            let mut stack: Vec<FuncId> = calls[f].iter().copied().collect();
            while let Some(g) = stack.pop() {
                if seen.insert(g) {
                    stack.extend(calls[g].iter().copied());
                }
            }
            seen
        })
        .collect()
}

pub(crate) fn weight(depth: u32) -> u64 {
    1u64 << (3 * depth.min(6))
}

impl<'p> G<'p> {
    fn new(p: &'p Program, tgt: &'p Target, layout: Option<&'p Layout>, isr_scratch: [u32; 4], prev_calls: Vec<BTreeSet<FuncId>>) -> G<'p> {
        let nf = p.funcs.len();
        G {
            p,
            tgt,
            layout,
            items: Vec::new(),
            bsr: None,
            lbl: 0,
            uses: vec![0; p.vars.len() + 4 + nf + 1],
            depth: 0,
            cur: nf,
            cur_asm: p.main.asm.clone(),
            temp_cur: 0,
            temp_max: vec![0; nf + 1],
            scratch_max: [0; 4],
            loops: Vec::new(),
            called: BTreeSet::new(),
            calls: vec![BTreeSet::new(); nf + 1],
            helpers: BTreeSet::new(),
            errors: Vec::new(),
            span: Span::default(),
            nvars: p.vars.len(),
            ranges: Vec::new(),
            hranges: Vec::new(),
            save_max: vec![0; p.n_saves + p.isrs.len()],
            isr_end: None,
            flash_used: BTreeSet::new(),
            isr_scratch,
            reach: reachability(&prev_calls),
            prev_calls,
            save_stack: Vec::new(),
            soft_max: 0,
            lits: Vec::new(),
        }
    }

    pub fn err(&mut self, msg: impl Into<String>) {
        let m = msg.into();
        if !self.errors.iter().any(|e| e.1 == m) {
            self.errors.push((self.span, m));
        }
    }

    pub fn unsupported(&mut self, what: &str) {
        self.err(format!("{what} is not supported on the enhanced mid-range core yet"));
    }
}

/// Runs one generation pass over the whole program.
fn run_pass<'p>(p: &'p Program, tgt: &'p Target, layout: Option<&'p Layout>, isr_scratch: [u32; 4], prev_calls: Vec<BTreeSet<FuncId>>) -> (G<'p>, Vec<Item>) {
    let mut g = G::new(p, tgt, layout, isr_scratch, prev_calls);
    // PIC16F13145 family, erratum 1.3.1 (DS80001115F p.3): above 16 MHz the first instruction fetched after a Reset, a wake-up or
    // an interrupt can fail on silicon A2 and A3. The work around is a NOP where that fetch happens: at 0000h (the code starts at
    // 0001h) and, as the same fetch happens on entering the handler, at 0004h. `#option FetchNop = false` removes them (silicon A4).
    let fetch_nop = p.fetch_nop && p.clock_mhz > 16.0 && p.device.starts_with("PIC16F131");
    // Vectors: reset at 0, the single interrupt vector at 4 (hardware saves WREG, STATUS, BSR, FSRs and PCLATH).
    if fetch_nop {
        g.ins("nop");
    }
    if !p.isrs.is_empty() {
        g.items.push(Item::Br(Cc::Always, "__reset".into()));
        g.items.push(Item::Org(4));
        if fetch_nop {
            g.ins("nop");
        }
        g.gen_isr(0);
    }
    g.cur = p.funcs.len();
    g.cur_asm = p.main.asm.clone();
    g.temp_cur = 0;
    g.depth = 0;
    g.bsr = None;
    g.label("__reset");
    g.startup();
    g.block(&p.main.body);
    g.label("__halt");
    g.br(Cc::Always, "__halt");
    let mut done: BTreeSet<FuncId> = BTreeSet::new();
    loop {
        let next = g.called.iter().find(|f| !done.contains(f)).copied();
        let Some(f) = next else { break };
        done.insert(f);
        let func = &p.funcs[f];
        g.cur = f;
        g.cur_asm = func.asm.clone();
        g.temp_cur = 0;
        g.depth = 0;
        g.bsr = None;
        g.items.push(Item::Comment(format!("Sub/Function {}", func.name)));
        let start = g.items.len();
        g.label(&func.asm);
        g.block(&func.body);
        g.ranges.push((f, start, g.items.len()));
    }
    let mut emitted: BTreeSet<String> = BTreeSet::new();
    loop {
        let next = g.helpers.iter().find(|h| !emitted.contains(*h)).cloned();
        let Some(h) = next else { break };
        emitted.insert(h.clone());
        g.items.push(Item::Comment(format!("helper {h}")));
        let start = g.items.len();
        g.emit_helper(&h);
        g.hranges.push((format!("__{h}"), start, g.items.len()));
    }
    // String literals, each Null-terminated, one `retlw` per byte like the constant tables.
    let lits = g.lits.clone();
    for (n, lit) in lits.iter().enumerate() {
        let mut bytes = lit.clone();
        bytes.push(0);
        g.items.push(Item::Label(format!("__STR{n}")));
        g.items.push(Item::Data(bytes));
    }
    // Constant tables: one `retlw` per byte, so FSR reads see the byte in the low 8 bits of the word.
    for (i, f) in p.flash.iter().enumerate() {
        g.items.push(Item::Label(f.asm.clone()));
        g.items.push(Item::Data(f.bytes.clone()));
        let _ = i;
    }
    let items = std::mem::take(&mut g.items);
    (g, items)
}

/// Levels of the hardware return stack the program can use at once: the deepest chain of calls from the
/// main program or the interrupt handler (which adds one level on top of the main chain).
fn stack_depth(g: &G, items: &[Item]) -> u32 {
    fn callees(items: &[Item], s: usize, e: usize) -> Vec<String> {
        items[s..e]
            .iter()
            .filter_map(|it| match it {
                Item::Call(t) => Some(t.clone()),
                Item::Raw(t) | Item::Ins(t) => {
                    let t = t.split(';').next().unwrap_or("").trim();
                    let mut w = t.split_whitespace();
                    let m = w.next()?.to_ascii_lowercase();
                    (m == "call" || m == "fcall").then(|| w.next().map(|x| x.to_string())).flatten()
                }
                _ => None,
            })
            .collect()
    }
    let mut bodies: HashMap<String, (usize, usize)> = HashMap::new();
    for (f, s, e) in &g.ranges {
        bodies.insert(g.p.funcs[*f].asm.clone(), (*s, *e));
    }
    for (h, s, e) in &g.hranges {
        bodies.insert(h.clone(), (*s, *e));
    }
    fn depth(name: &str, items: &[Item], bodies: &HashMap<String, (usize, usize)>, memo: &mut HashMap<String, u32>, active: &mut Vec<String>) -> u32 {
        if let Some(&d) = memo.get(name) {
            return d;
        }
        let Some(&(s, e)) = bodies.get(name) else { return 0 };
        if active.iter().any(|a| a == name) {
            return 0;
        }
        active.push(name.to_string());
        let d = callees(items, s, e).iter().map(|c| 1 + depth(c, items, bodies, memo, active)).max().unwrap_or(0);
        active.pop();
        memo.insert(name.to_string(), d);
        d
    }
    let mut memo = HashMap::new();
    let pos = |l: &str| items.iter().position(|i| matches!(i, Item::Label(x) if x == l));
    let main = match (pos("__reset"), pos("__halt")) {
        (Some(s), Some(e)) if s < e => callees(items, s, e).iter().map(|c| 1 + depth(c, items, &bodies, &mut memo, &mut Vec::new())).max().unwrap_or(0),
        _ => 0,
    };
    let mut isr = 0;
    for (f, s, e) in &g.ranges {
        if g.p.isrs.iter().any(|x| x.0 == *f) {
            isr = isr.max(1 + callees(items, *s, *e).iter().map(|c| 1 + depth(c, items, &bodies, &mut memo, &mut Vec::new())).max().unwrap_or(0));
        }
    }
    main + isr
}

pub fn generate(p: &Program, tgt: &Target) -> Generated {
    let mem = tgt.pic16.as_ref().expect("the PIC16 generator needs the enhanced mid-range memory description");
    let nvars = p.vars.len();
    let nf = p.funcs.len();
    // What this core does not have: C interop (the link goes through xc8-cc and the PIC18 ABI), and priorities (one vector).
    let unsupported = if p.c_link() {
        Some("calling C (CFile, Extern, Export) is not supported on the enhanced mid-range core yet")
    } else if p.isrs.len() > 1 {
        Some("the enhanced mid-range core has a single interrupt vector, so a program can have one Interrupt handler")
    } else if p.isrs.iter().any(|x| x.1 != Level::Single) {
        Some("the enhanced mid-range core has no interrupt priorities; leave out ipLow/ipHigh")
    } else {
        None
    };
    if let Some(msg) = unsupported {
        return Generated { out: Output { text: String::new(), words: 0, labels: HashMap::new(), func_words: vec![] }, stack_levels: 0, objs: vec![], layout: Layout::default(), errors: vec![(Span::default(), msg.to_string())], debug: Default::default() };
    }
    let (g1, _items1) = run_pass(p, tgt, None, [0; 4], vec![BTreeSet::new(); nf + 1]);
    let mut calls = g1.calls.clone();
    let mut soft = g1.soft_max;
    let mut uses = g1.uses.clone();
    let mut scratch = g1.scratch_max;
    let mut temps = g1.temp_max.clone();
    let mut save_bytes = vec![0u32; p.n_saves + p.isrs.len()];
    let mut isr_mask = vec![false; nf + 1];
    for &(f, _) in &p.isrs {
        isr_mask[f] = true;
    }
    let indep = independent(&g1.calls, &isr_mask);
    let pass1_errors = g1.errors.clone();
    drop(g1);
    let mut errors: Vec<(Span, String)> = Vec::new();
    let mut result = None;
    for _round in 0..6 {
        let mut objs: Vec<Obj> = Vec::new();
        for (i, v) in p.vars.iter().enumerate() {
            objs.push(Obj { name: v.asm.clone(), bytes: if uses[i] > 0 { v.bytes } else { 0 }, weight: uses[i], force_access: false, zero: true, owner: v.owner });
        }
        for r in 0..4 {
            objs.push(Obj { name: format!("__{}", SCRATCH[r]), bytes: scratch[r], weight: u64::MAX, force_access: true, zero: false, owner: None });
        }
        for f in 0..=nf {
            let asm = if f < nf { p.funcs[f].asm.clone() } else { p.main.asm.clone() };
            objs.push(Obj { name: format!("{asm}__TMP"), bytes: temps[f], weight: uses[nvars + 4 + f], force_access: false, zero: false, owner: if f < nf { Some(f) } else { None } });
        }
        for (k, &n) in save_bytes.iter().enumerate() {
            let name = if k < p.n_saves { format!("__SAV{k}") } else { format!("__ISV{}", k - p.n_saves) };
            objs.push(Obj { name, bytes: n, weight: 0, force_access: false, zero: false, owner: None });
        }
        // The software stack for the frames of recursive calls, and its pointer (common RAM).
        objs.push(Obj { name: "__SWSTK".into(), bytes: soft * 16, weight: 0, force_access: false, zero: false, owner: None });
        objs.push(Obj { name: "__SSP".into(), bytes: if soft > 0 { 2 } else { 0 }, weight: u64::MAX, force_access: true, zero: false, owner: None });
        let layout = match plan_layout16(&objs, mem, &indep) {
            Ok(l) => l,
            Err(e) => {
                errors.push((Span::default(), e));
                Layout { addr: vec![None; objs.len()], size: vec![0; objs.len()] }
            }
        };
        let (g2, items) = run_pass(p, tgt, Some(&layout), scratch, calls.clone());
        let grew = (0..4).any(|r| g2.scratch_max[r] > scratch[r]) || (0..temps.len()).any(|f| g2.temp_max[f] > temps[f]) || (0..nvars).any(|i| g2.uses[i] > 0 && uses[i] == 0) || (0..save_bytes.len()).any(|k| g2.save_max[k] > save_bytes[k]) || g2.soft_max > soft;
        let calls_changed = g2.calls != calls;
        if calls_changed {
            calls = g2.calls.clone();
        }
        soft = soft.max(g2.soft_max);
        if grew || calls_changed {
            for k in 0..save_bytes.len() {
                save_bytes[k] = save_bytes[k].max(g2.save_max[k]);
            }
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
        let levels = stack_depth(&g2, &items);
        let helpers: Vec<String> = g2.helpers.iter().cloned().collect();
        let mut ranges: Vec<(String, usize, usize)> = g2.ranges.iter().filter(|(f, _, _)| !isr_mask[*f]).map(|(f, s, e)| (p.funcs[*f].asm.clone(), *s, *e)).collect();
        ranges.extend(g2.hranges.iter().cloned());
        result = Some((objs, layout, items, helpers, levels, ranges));
        break;
    }
    if errors.is_empty() && result.is_none() {
        errors = pass1_errors;
    }
    let Some((objs, layout, items, helpers, stack_levels, ranges)) = result else {
        errors.push((Span::default(), "internal: data layout did not settle".into()));
        return Generated { out: Output { text: String::new(), words: 0, labels: HashMap::new(), func_words: vec![] }, stack_levels: 0, objs: vec![], layout: Layout::default(), errors, debug: Default::default() };
    };
    let items = if tgt.opt {
        let items = crate::codegen::inline_single_calls(items, ranges);
        let mut plain: HashMap<String, (u32, u32)> = HashMap::new();
        for (i, o) in objs.iter().enumerate() {
            if let Some(a) = layout.addr[i] && !(i < nvars && p.vars[i].volatile) {
                let name = if i >= nvars && i < nvars + 4 { format!("__{}0", SCRATCH[i - nvars]) } else { o.name.clone() };
                plain.insert(name, (a, o.bytes));
            }
        }
        let items = crate::peephole::optimise16(items, &crate::peephole::Env { plain, access: (0, 0), access_sfr: (0, 0), keep_writes: tgt.keep_vars, reg_calls: p.funcs.iter().filter(|f| f.reg).map(|f| f.asm.clone()).collect() });
        opt::drop_redundant_movlb(items)
    } else {
        items
    };
    let mut asmd: Assembled = assemble16(&items, 0, false);
    let multipage = asmd.words > 2048;
    if multipage {
        asmd = assemble16(&items, 0, true);
    }
    let mut text = String::new();
    text.push_str(&format!("; basil output for {}\n", p.device));
    text.push_str("#include <xc.inc>\n\n");
    for (name, _, v) in &p.config {
        text.push_str(&format!("CONFIG {name} = 0x{v:04X}\n"));
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
    text.push_str("\nPSECT code,class=CODE,abs,delta=2\n    ORG 0x0000\n");
    for l in &asmd.lines {
        text.push_str(l);
        text.push('\n');
    }
    // Label table for tools (simulator harness): word addresses of the non-local labels.
    let mut syms: Vec<(&String, &u32)> = asmd.labels.iter().filter(|(k, _)| !k.starts_with("_L")).collect();
    syms.sort();
    for (k, v) in syms {
        text.push_str(&format!(";SYM {k} 0x{:04X}\n", v));
    }
    text.push_str("    END __reset\n");
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
    starts.sort_by_key(|s| s.1);
    let mut func_words = Vec::new();
    for (i, (n, a)) in starts.iter().enumerate() {
        let end = starts.get(i + 1).map(|s| s.1).unwrap_or(asmd.words);
        func_words.push((n.clone(), end - a));
    }
    if asmd.words > mem.prog_words {
        errors.push((Span::default(), format!("the program needs {} words of program memory but the device has {}", asmd.words, mem.prog_words)));
    }
    Generated { out: Output { text, words: asmd.words, labels: asmd.labels, func_words }, stack_levels, objs, layout, errors, debug: Default::default() }
}
