//! Peephole pass over the generated item list (PLAN §7A.3 priority 8).
//!
//! The code generator is deliberately simple-minded: every expression travels through `WREG` or
//! the accumulator `__A`, and every statement starts from scratch. This pass cleans up what that
//! leaves behind, using only facts it can read off the instruction stream:
//!
//! * **Branch to the next instruction** is deleted.
//! * **Bit test into a Boolean, then compared** becomes the bit-skip branch (`btfsc R,b` / `bra L`).
//! * **`xorlw 0`** (the generator's "is it zero" test) after an instruction that already set Z
//!   and N from `WREG` is deleted.
//! * **Redundant `WREG` loads**: `movlw k` when `WREG` already holds `k`, and `movf m, w` when
//!   `WREG` already holds `m` (right after `movwf m`, say).
//! * **Copy forwarding**: a read of a scratch register that was just loaded by `movff s, __X`
//!   reads `s` instead.
//! * **Dead stores** to `WREG` and the scratch registers `__A`..`__D`. They are dead when
//!   overwritten before being read in the same straight line, or when the statement ends
//!   ([`Item::Fence`]): no value is carried across statements.
//!
//! Everything is local to a straight run of instructions. A label, a branch, a call, a skip
//! instruction, raw `Asm` text or an instruction it does not know ends the run and makes every
//! fact unknown, which is always safe. The status flags are tracked separately: an instruction
//! that sets flags is only deleted when nothing can read them before they are overwritten.
//!
//! Registers whose reads may have side effects (device registers) are never reasoned about: only
//! symbols in [`Env::plain`] (compiler-placed RAM) are. A variable an interrupt handler writes may
//! change between two instructions of a run, so a value kept in `WREG` can be one load stale; that
//! is a legal ordering of the handler and the main program (nothing here is `volatile`), and every
//! loop that polls such a variable starts with a label, which ends the run. The scratch registers
//! the pass deletes stores to are saved by every handler that uses them.

use crate::asm::{Cc, Item};
use std::collections::HashMap;

/// What the pass may assume about symbols.
pub struct Env {
    /// Compiler-placed RAM objects: name to `(address, bytes)`.
    pub plain: HashMap<String, (u32, u32)>,
    /// Access Bank RAM `[start, end)` and the Access Bank's SFR half `[start, end)`.
    pub access: (u32, u32),
    pub access_sfr: (u32, u32),
    /// Do not delete stores to variables nothing reads.
    pub keep_writes: bool,
    /// Labels of the register-call routines, which read `__A` and `__B` (`ir::Func::reg`).
    pub reg_calls: Vec<String>,
    /// Routines with a one-byte `Result`: (label, the result's symbol).
    pub byte_results: Vec<(String, String)>,
    /// Variables an interrupt handler (or a routine C calls) can see: no pass may park a half-computed value in one.
    pub shared: std::collections::HashSet<String>,
}

impl Env {
    fn addr(&self, sym: &str) -> Option<u32> {
        if let Some(i) = scratch(sym) {
            // Scratch registers are placed by the caller under their own names.
            let (reg, byte) = (i / 4, i % 4);
            let base = format!("__{}0", ['A', 'B', 'C', 'D'][reg as usize]);
            return self.plain.get(&base).map(|b| b.0 + byte as u32);
        }
        let (name, off) = split_off(sym)?;
        let &(a, n) = self.plain.get(name)?;
        (off < n).then_some(a + off)
    }
    /// A compiler-placed RAM byte: reading it has no side effect.
    fn is_plain(&self, sym: &str) -> bool {
        self.addr(sym).is_some()
    }
    /// A plain byte reachable with the access bit set.
    fn is_access(&self, sym: &str) -> bool {
        self.addr(sym).is_some_and(|a| crate::codegen::in_access(self.access, self.access_sfr, a))
    }
}

fn split_off(sym: &str) -> Option<(&str, u32)> {
    match sym.split_once('+') {
        None => Some((sym, 0)),
        Some((n, o)) => Some((n.trim(), o.trim().parse().ok()?)),
    }
}

/// A scratch register byte `__A0`..`__D3` (also spelled `__A0+1`), as an index 0..16.
fn scratch(sym: &str) -> Option<u8> {
    let rest = sym.trim().strip_prefix("__")?;
    let mut ch = rest.chars();
    let reg = match ch.next()? {
        'A' => 0,
        'B' => 1,
        'C' => 2,
        'D' => 3,
        _ => return None,
    };
    let (d, off) = split_off(ch.as_str())?;
    let byte = d.parse::<u32>().ok()? + off;
    (byte < 4 && d.chars().all(|c| c.is_ascii_digit()) && !d.is_empty()).then_some(reg * 4 + byte as u8)
}

/// Spelled like a scratch register (`__A` to `__D` and a digit).
fn looks_scratch(o: &str) -> bool {
    let b = o.as_bytes();
    b.len() >= 4 && b.starts_with(b"__") && matches!(b[2], b'A'..=b'D') && b[3].is_ascii_digit()
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Loc {
    W,
    S(u8),
}

const Z: u8 = 1;
const N: u8 = 2;
const C: u8 = 4;
const OV: u8 = 8;
const ALL: u8 = Z | N | C | OV;

/// What one instruction does, as far as this pass cares.
#[derive(Default, Debug)]
struct Eff {
    /// Tracked locations read.
    reads: Vec<Loc>,
    /// Tracked locations written without being read first.
    writes: Vec<Loc>,
    /// Written without a read of itself, but into memory the pass does not track.
    wmem: Vec<Mem>,
    /// Untracked memory read.
    rmem: Vec<String>,
    flags_r: u8,
    flags_w: u8,
    /// `WREG` is set to this literal / copy of this byte.
    w_imm: Option<u8>,
    w_mem: Option<String>,
    /// `WREG` and this scratch register hold the same byte after the instruction (`movwf __A0`, `movf __A0, w`).
    w_scr: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Mem {
    Sym(String),
    /// Indirect or absolute: could be anywhere.
    Unknown,
}

fn is_indirect(op: &str) -> bool {
    let o = op.to_ascii_uppercase();
    ["INDF", "POSTINC", "POSTDEC", "PREINC", "PLUSW"].iter().any(|p| o.starts_with(p))
}

/// The location a file-register operand names, if tracked.
fn loc(op: &str) -> Option<Loc> {
    if op.eq_ignore_ascii_case("WREG") {
        return Some(Loc::W);
    }
    scratch(op).map(Loc::S)
}

fn mem_of(op: &str) -> Mem {
    if is_indirect(op) || op.chars().next().is_some_and(|c| c.is_ascii_digit()) {
        Mem::Unknown
    } else {
        Mem::Sym(op.trim().to_string())
    }
}

enum Dest {
    W,
    F,
}

fn dest(d: &str) -> Option<Dest> {
    match d.trim().to_ascii_lowercase().as_str() {
        "w" | "0" => Some(Dest::W),
        "f" | "1" => Some(Dest::F),
        _ => None,
    }
}

/// Splits `mnemonic op, op, ...`.
fn parse(t: &str) -> Option<(String, Vec<&str>)> {
    let t = t.trim();
    if t.is_empty() || t.starts_with(';') || t.ends_with(':') {
        return None;
    }
    let (mn, rest) = match t.split_once(char::is_whitespace) {
        Some((m, r)) => (m, r.trim()),
        None => (t, ""),
    };
    let ops = if rest.is_empty() { Vec::new() } else { rest.split(',').map(str::trim).collect() };
    Some((mn.to_ascii_lowercase(), ops))
}

thread_local! {
    /// Set while [`optimise16`] runs: the instruction set is the enhanced mid-range one.
    static CORE16: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

fn core16() -> bool {
    CORE16.with(|c| c.get())
}

/// The flags an instruction that sets Z from its result sets (N too on the PIC18).
fn zflags() -> u8 {
    if core16() { Z } else { Z | N }
}

/// The effect of an instruction, or `None` when it is control flow or unknown: the caller then
/// forgets everything it knew.
fn effect(t: &str) -> Option<Eff> {
    if core16() {
        return effect16(t);
    }
    let (mn, ops) = parse(t)?;
    // An operand that looks like a scratch register but does not parse is not understood.
    if ops.iter().any(|o| looks_scratch(o) && scratch(o).is_none()) {
        return None;
    }
    let mut e = Eff::default();
    // `f` as a source read.
    let read = |e: &mut Eff, op: &str| match loc(op) {
        Some(l) => e.reads.push(l),
        None => e.rmem.push(op.to_string()),
    };
    // `f` as a pure destination.
    let write = |e: &mut Eff, op: &str| match loc(op) {
        Some(l) => e.writes.push(l),
        None => e.wmem.push(mem_of(op)),
    };
    // `f` read and written.
    let modify = |e: &mut Eff, op: &str| match loc(op) {
        Some(l) => {
            e.reads.push(l);
            e.writes.push(l);
        }
        None => {
            e.rmem.push(op.to_string());
            e.wmem.push(mem_of(op));
        }
    };
    match mn.as_str() {
        "movlw" if ops.len() == 1 => {
            e.writes.push(Loc::W);
            e.w_imm = parse_lit(ops[0]);
        }
        "addlw" | "sublw" if ops.len() == 1 => {
            e.reads.push(Loc::W);
            e.writes.push(Loc::W);
            e.flags_w = ALL;
        }
        "andlw" | "iorlw" | "xorlw" if ops.len() == 1 => {
            e.reads.push(Loc::W);
            e.writes.push(Loc::W);
            e.flags_w = Z | N;
        }
        "mullw" if ops.len() == 1 => {
            e.reads.push(Loc::W);
            e.wmem.push(Mem::Sym("PRODL".into()));
            e.wmem.push(Mem::Sym("PRODH".into()));
        }
        "mulwf" if (1..=2).contains(&ops.len()) => {
            e.reads.push(Loc::W);
            read(&mut e, ops[0]);
            e.wmem.push(Mem::Sym("PRODL".into()));
            e.wmem.push(Mem::Sym("PRODH".into()));
        }
        "movwf" if (1..=2).contains(&ops.len()) => {
            e.reads.push(Loc::W);
            write(&mut e, ops[0]);
            if loc(ops[0]).is_none() && !is_indirect(ops[0]) {
                e.w_mem = Some(ops[0].to_string());
            } else if scratch(ops[0]).is_some() {
                e.w_scr = Some(ops[0].trim().to_string());
            }
        }
        "clrf" | "setf" if (1..=2).contains(&ops.len()) => {
            write(&mut e, ops[0]);
            if mn == "clrf" {
                e.flags_w = Z;
            }
        }
        "movff" if ops.len() == 2 => {
            read(&mut e, ops[0]);
            write(&mut e, ops[1]);
        }
        "movf" if (2..=3).contains(&ops.len()) => {
            let d = dest(ops[1])?;
            read(&mut e, ops[0]);
            e.flags_w = Z | N;
            match d {
                Dest::W => {
                    e.writes.push(Loc::W);
                    if loc(ops[0]).is_none() && !is_indirect(ops[0]) {
                        e.w_mem = Some(ops[0].to_string());
                    } else if scratch(ops[0]).is_some() {
                        e.w_scr = Some(ops[0].trim().to_string());
                    }
                }
                Dest::F => write(&mut e, ops[0]),
            }
        }
        "addwf" | "addwfc" | "subwf" | "subwfb" | "subfwb" | "andwf" | "iorwf" | "xorwf" if (2..=3).contains(&ops.len()) => {
            let d = dest(ops[1])?;
            e.reads.push(Loc::W);
            read(&mut e, ops[0]);
            e.flags_w = if matches!(mn.as_str(), "andwf" | "iorwf" | "xorwf") { Z | N } else { ALL };
            if matches!(mn.as_str(), "addwfc" | "subwfb" | "subfwb") {
                e.flags_r = C;
            }
            match d {
                Dest::W => e.writes.push(Loc::W),
                Dest::F => write(&mut e, ops[0]),
            }
        }
        "incf" | "decf" | "comf" | "swapf" | "rlcf" | "rrcf" | "rlncf" | "rrncf" if (2..=3).contains(&ops.len()) => {
            let d = dest(ops[1])?;
            read(&mut e, ops[0]);
            e.flags_w = match mn.as_str() {
                "incf" | "decf" => ALL,
                "comf" | "rlncf" | "rrncf" => Z | N,
                "swapf" => 0,
                _ => C | Z | N,
            };
            if matches!(mn.as_str(), "rlcf" | "rrcf") {
                e.flags_r = C;
            }
            match d {
                Dest::W => e.writes.push(Loc::W),
                Dest::F => write(&mut e, ops[0]),
            }
        }
        "negf" if (1..=2).contains(&ops.len()) => {
            modify(&mut e, ops[0]);
            e.flags_w = ALL;
        }
        "bsf" | "bcf" | "btg" if (2..=3).contains(&ops.len()) => {
            // A bit of STATUS is a flag: be conservative about which one.
            if ops[0].eq_ignore_ascii_case("STATUS") {
                return None;
            }
            modify(&mut e, ops[0]);
        }
        "nop" | "lfsr" | "movlb" | "tblrd*" | "tblrd*+" | "tblrd*-" | "tblrd+*" => {}
        _ => return None,
    }
    // Any mention of the status register or a flag consumer was rejected above; indirect
    // operands that are read can read anything.
    for o in &ops {
        if o.eq_ignore_ascii_case("STATUS") {
            return None;
        }
    }
    // `PLUSWn` adds WREG to the pointer, so any access through it reads W.
    if ops.iter().any(|o| o.to_ascii_uppercase().starts_with("PLUSW")) && !e.reads.contains(&Loc::W) {
        e.reads.push(Loc::W);
    }
    Some(e)
}

/// [`effect`] for the enhanced mid-range core: no access bit, no N or OV, and the flags each instruction really
/// sets (a flag claimed written that is not would let a pass delete the instruction that does set it).
fn effect16(t: &str) -> Option<Eff> {
    let (mn, ops) = parse(t)?;
    if ops.iter().any(|o| looks_scratch(o) && scratch(o).is_none()) {
        return None;
    }
    let mut e = Eff::default();
    let read = |e: &mut Eff, op: &str| match loc(op) {
        Some(l) => e.reads.push(l),
        None => e.rmem.push(op.to_string()),
    };
    let write = |e: &mut Eff, op: &str| match loc(op) {
        Some(l) => e.writes.push(l),
        None => e.wmem.push(mem_of(op)),
    };
    match mn.as_str() {
        "movlw" if ops.len() == 1 => {
            e.writes.push(Loc::W);
            e.w_imm = parse_lit(ops[0]);
        }
        "addlw" | "sublw" if ops.len() == 1 => {
            e.reads.push(Loc::W);
            e.writes.push(Loc::W);
            e.flags_w = Z | C;
        }
        "andlw" | "iorlw" | "xorlw" if ops.len() == 1 => {
            e.reads.push(Loc::W);
            e.writes.push(Loc::W);
            e.flags_w = Z;
        }
        "clrw" if ops.is_empty() => {
            e.writes.push(Loc::W);
            e.flags_w = Z;
        }
        "movwf" if ops.len() == 1 => {
            e.reads.push(Loc::W);
            write(&mut e, ops[0]);
            if loc(ops[0]).is_none() && !is_indirect(ops[0]) {
                e.w_mem = Some(ops[0].to_string());
            }
        }
        "clrf" if ops.len() == 1 => {
            write(&mut e, ops[0]);
            e.flags_w = Z;
        }
        "movf" if ops.len() == 2 => {
            let d = dest(ops[1])?;
            read(&mut e, ops[0]);
            e.flags_w = Z;
            match d {
                Dest::W => {
                    e.writes.push(Loc::W);
                    if loc(ops[0]).is_none() && !is_indirect(ops[0]) {
                        e.w_mem = Some(ops[0].to_string());
                    }
                }
                Dest::F => write(&mut e, ops[0]),
            }
        }
        "addwf" | "addwfc" | "subwf" | "subwfb" | "andwf" | "iorwf" | "xorwf" | "incf" | "decf" | "comf" | "swapf" | "rlf" | "rrf" | "lslf" | "lsrf" | "asrf" if ops.len() == 2 => {
            let d = dest(ops[1])?;
            let two = matches!(mn.as_str(), "addwf" | "addwfc" | "subwf" | "subwfb" | "andwf" | "iorwf" | "xorwf");
            if two {
                e.reads.push(Loc::W);
            }
            read(&mut e, ops[0]);
            e.flags_w = match mn.as_str() {
                "addwf" | "addwfc" | "subwf" | "subwfb" | "lslf" | "lsrf" | "asrf" => Z | C,
                "andwf" | "iorwf" | "xorwf" | "incf" | "decf" | "comf" => Z,
                "rlf" | "rrf" => C,
                _ => 0,
            };
            if matches!(mn.as_str(), "addwfc" | "subwfb" | "rlf" | "rrf") {
                e.flags_r = C;
            }
            match d {
                Dest::W => e.writes.push(Loc::W),
                Dest::F => write(&mut e, ops[0]),
            }
        }
        // Reads through an FSR with a fixed offset; the `++` and `--` forms change the FSR and are left alone.
        "moviw" if ops.len() == 1 && ops[0].contains('[') => {
            e.writes.push(Loc::W);
            e.rmem.push("INDF".into());
            e.flags_w = Z;
        }
        "movwi" if ops.len() == 1 && ops[0].contains('[') => {
            e.reads.push(Loc::W);
            e.wmem.push(Mem::Unknown);
        }
        "bsf" | "bcf" if ops.len() == 2 => {
            if ops[0].eq_ignore_ascii_case("STATUS") {
                return None;
            }
            e.rmem.push(ops[0].to_string());
            e.wmem.push(mem_of(ops[0]));
            if let Some(l) = loc(ops[0]) {
                e.reads.push(l);
                e.writes.push(l);
            }
        }
        "nop" | "movlb" | "movlp" => {}
        _ => return None,
    }
    if ops.iter().any(|o| o.eq_ignore_ascii_case("STATUS")) {
        return None;
    }
    Some(e)
}

fn parse_lit(s: &str) -> Option<u8> {
    let s = s.trim();
    let v = if let Some(h) = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")) { u32::from_str_radix(h, 16).ok()? } else { s.parse::<u32>().ok()? };
    (v <= 0xFF).then_some(v as u8)
}

/// Like [`flags_live`], for code inside a user routine: its `return` hands no flags back.
fn flags_live_in_routine(items: &[Item], i: usize, mut needed: u8) -> bool {
    for it in &items[i + 1..] {
        match it {
            Item::Comment(_) => {}
            Item::Fence => return false,
            Item::Ins(t) if t.trim() == "return" => return false,
            Item::Ins(t) => match effect(t) {
                None => return true,
                Some(e) => {
                    if e.flags_r & needed != 0 {
                        return true;
                    }
                    needed &= !e.flags_w;
                    if needed == 0 {
                        return false;
                    }
                }
            },
            _ => return true,
        }
    }
    true
}

/// The flags a conditional branch reads.
fn cc_flags(cc: Cc) -> u8 {
    match cc {
        Cc::Z | Cc::Nz => Z,
        Cc::C | Cc::Nc => C,
        Cc::N | Cc::Nn => N,
        Cc::Ov | Cc::Nov => OV,
        Cc::Always => 0,
    }
}

/// Whether neither `WREG` (when `w`) nor any of the `need` flags can be read from item `from` on, following both
/// sides of every branch and skip (a statement end ends the search; a call may take its argument in `WREG`, so a
/// live `WREG` is read there; a return hands on no flags). Anything it cannot follow, or a search longer than a small
/// budget, counts as a read.
fn dead_paths(items: &[Item], from: usize, w: bool, need: u8) -> bool {
    let label_at = |target: &str| items.iter().position(|x| matches!(x, Item::Label(l) if l == target));
    let mut work = vec![(from, w, need)];
    let mut seen = std::collections::HashSet::new();
    let mut budget = 200usize;
    while let Some((mut k, mut w, mut need)) = work.pop() {
        if !seen.insert((k, w, need)) {
            continue;
        }
        loop {
            if !w && need == 0 {
                break;
            }
            if budget == 0 {
                return false;
            }
            budget -= 1;
            let Some(it) = items.get(k) else { return false };
            match it {
                Item::Comment(_) | Item::Label(_) => {}
                // See `loc_live`: `WREG` may be carried across a statement end.
                Item::Fence if w => {}
                Item::Fence => break,
                Item::Call(_) => {
                    if w {
                        return false;
                    }
                    break;
                }
                Item::Br(cc, target) => {
                    if cc_flags(*cc) & need != 0 {
                        return false;
                    }
                    let Some(p) = label_at(target) else { return false };
                    if *cc == Cc::Always {
                        k = p;
                        continue;
                    }
                    work.push((p, w, need));
                }
                Item::Ins(t) => {
                    if matches!(parse(t), Some((m, _)) if m == "return" || m == "retlw") {
                        if w {
                            return false;
                        }
                        break;
                    }
                    if is_skip(t) {
                        // A skip passes over the next instruction. Anything but an instruction or a branch there
                        // (a label would be a way in) is not followed.
                        let mut n = k + 1;
                        while matches!(items.get(n), Some(Item::Comment(_) | Item::Fence)) {
                            n += 1;
                        }
                        if !matches!(items.get(n), Some(Item::Ins(_) | Item::Br(..))) {
                            return false;
                        }
                        work.push((n + 1, w, need));
                    }
                    // A bit test reads one byte and changes neither `WREG` nor a flag (unless it tests `WREG`).
                    if matches!(parse(t), Some((m, o)) if (m == "btfsc" || m == "btfss") && !o.is_empty() && !o[0].eq_ignore_ascii_case("WREG") && !o[0].to_ascii_uppercase().contains("STATUS")) {
                        k += 1;
                        continue;
                    }
                    match effect(t) {
                        None => return false,
                        Some(e) => {
                            if (w && e.reads.contains(&Loc::W)) || e.flags_r & need != 0 {
                                return false;
                            }
                            if e.writes.contains(&Loc::W) {
                                w = false;
                            }
                            need &= !e.flags_w;
                        }
                    }
                }
                _ => return false,
            }
            k += 1;
        }
    }
    true
}

/// Whether any of the `needed` flags may be read after item `i` (before being overwritten).
fn flags_live(items: &[Item], i: usize, mut needed: u8) -> bool {
    for it in &items[i + 1..] {
        match it {
            Item::Comment(_) => {}
            Item::Fence => return false,
            // Both paths of a branch are not followed: assume the flags are read. A callee gets
            // none from its caller.
            Item::Br(..) | Item::SkipBr(..) => return true,
            Item::Call(_) => return false,
            Item::Ins(t) => match effect(t) {
                None => return true,
                Some(e) => {
                    if e.flags_r & needed != 0 {
                        return true;
                    }
                    needed &= !e.flags_w;
                    if needed == 0 {
                        return false;
                    }
                }
            },
            Item::Label(_) | Item::Raw(_) | Item::Data(_) | Item::Keep(_) | Item::Org(_) => return true,
        }
    }
    true
}

enum Live {
    Dead,
    Live,
}

/// Whether the value of `l` written by item `i` can be read later in the same straight run.
fn loc_live(items: &[Item], i: usize, l: Loc, env: &Env) -> Live {
    for it in &items[i + 1..] {
        match it {
            Item::Comment(_) => {}
            // The code generator carries nothing past a statement end, but `pass_wreg` reuses what `WREG` holds across
            // one (it emits nothing), so a read of `WREG` after a fence may belong to a value loaded before it.
            Item::Fence if matches!(l, Loc::W) => {}
            Item::Fence => return Live::Dead,
            // A routine takes its arguments from its own frame; only the `__` helpers and the
            // register-call routines read the scratch registers, and a routine is free to overwrite them.
            Item::Call(t) if matches!(l, Loc::S(_)) && !t.starts_with("__") && !env.reg_calls.contains(t) => return Live::Dead,
            Item::Ins(t) => match effect(t) {
                None => return Live::Live,
                Some(e) => {
                    if e.reads.contains(&l) {
                        return Live::Live;
                    }
                    if e.writes.contains(&l) {
                        return Live::Dead;
                    }
                }
            },
            _ => return Live::Live,
        }
    }
    Live::Live
}

/// An instruction that does nothing but move a value into tracked locations.
fn deletable(e: &Eff, env: &Env) -> bool {
    e.wmem.is_empty() && !e.writes.is_empty() && e.rmem.iter().all(|m| env.is_plain(m))
}

fn pass_dead_stores(items: &mut Vec<Item>, env: &Env) -> bool {
    let mut dead = vec![false; items.len()];
    let keep = protected(items);
    for i in 0..items.len() {
        if keep[i] {
            continue;
        }
        let Item::Ins(t) = &items[i] else { continue };
        let Some(e) = effect(t) else { continue };
        // Only moves: an instruction that also reads what it writes is part of a computation
        // whose flags and value the next instruction uses.
        let pure_move = e.writes.iter().all(|w| !e.reads.contains(w));
        if !pure_move || !deletable(&e, env) {
            continue;
        }
        if e.writes.iter().any(|&w| matches!(loc_live(items, i, w, env), Live::Live)) {
            continue;
        }
        if e.flags_w != 0 && flags_live(items, i, e.flags_w) {
            continue;
        }
        dead[i] = true;
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// `clrf __R` followed by `movf __R, w` (nothing between them touches `__R` or leaves the straight line) loads a
/// zero into `WREG`: `movlw 0` does that without reading the register, and the `clrf` goes when nothing else reads
/// it (`pass_dead_stores`). Only when the flags the `movf` would set are dead.
fn pass_zero_load(items: &mut [Item]) -> bool {
    let keep = protected(items);
    let mut changed = false;
    for i in 0..items.len() {
        if keep[i] {
            continue;
        }
        let Item::Ins(t) = &items[i] else { continue };
        let Some((m, ops)) = parse(t) else { continue };
        if m != "clrf" || ops.is_empty() {
            continue;
        }
        let Some(Loc::S(r)) = loc(ops[0]) else { continue };
        let mut j = i + 1;
        while j < items.len() && !keep[j] {
            match &items[j] {
                Item::Comment(_) => {}
                Item::Ins(u) => {
                    let Some(e) = effect(u) else { break };
                    if let Some((m2, o2)) = parse(u)
                        && m2 == "movf"
                        && o2.len() == 3
                        && matches!(dest(o2[1]), Some(Dest::W))
                        && loc(o2[0]) == Some(Loc::S(r))
                    {
                        if !flags_live(items, j, e.flags_w) {
                            items[j] = Item::Ins("movlw 0".to_string());
                            changed = true;
                        }
                        break;
                    }
                    if e.reads.contains(&Loc::S(r)) || e.writes.contains(&Loc::S(r)) || e.wmem.iter().any(|m| matches!(m, Mem::Unknown)) {
                        break;
                    }
                }
                _ => break,
            }
            j += 1;
        }
    }
    changed
}

/// What `WREG` is known to hold.
#[derive(Clone, PartialEq, Debug)]
enum W {
    Unknown,
    Imm(u8),
    /// A copy of this compiler-placed byte.
    Mem(String),
    /// The constant, and also a copy of this compiler-placed byte (after `movlw k` / `movwf m`).
    Both(u8, String),
}

fn pass_wreg(items: &mut Vec<Item>, env: &Env) -> bool {
    let mut dead = vec![false; items.len()];
    let keep = protected(items);
    let mut w = W::Unknown;
    for i in 0..items.len() {
        if keep[i] {
            w = W::Unknown;
            continue;
        }
        match &items[i] {
            Item::Comment(_) => continue,
            Item::Ins(t) => {
                let Some(e) = effect(t) else {
                    w = W::Unknown;
                    continue;
                };
                // `movf __A0, w` when W already holds __A0 (it was just stored there or loaded from there).
                if let (Some(m), W::Mem(h)) = (&e.w_scr, &w)
                    && e.writes == [Loc::W]
                    && m == h
                    && t.trim_start().starts_with("movf ")
                    && !flags_live(items, i, e.flags_w)
                {
                    dead[i] = true;
                    continue;
                }
                // Redundant load?
                if e.writes == [Loc::W] && e.reads.is_empty() {
                    if let (Some(k), W::Imm(h) | W::Both(h, _)) = (e.w_imm, &w)
                        && k == *h
                        && e.flags_w == 0
                    {
                        dead[i] = true;
                        continue;
                    }
                    if let (Some(m), W::Mem(h) | W::Both(_, h)) = (&e.w_mem, &w)
                        && m == h
                        && env.is_plain(m)
                        && (e.flags_w == 0 || !flags_live(items, i, e.flags_w))
                    {
                        dead[i] = true;
                        continue;
                    }
                }
                // New state.
                let wrote_w = e.writes.contains(&Loc::W);
                let mut next = if wrote_w {
                    match (&e.w_imm, &e.w_mem) {
                        (Some(k), _) => W::Imm(*k),
                        (None, Some(m)) if env.is_plain(m) && e.reads.is_empty() => W::Mem(m.clone()),
                        _ => W::Unknown,
                    }
                } else {
                    w.clone()
                };
                if let W::Mem(h) | W::Both(_, h) = &next {
                    let clobbered = e.wmem.iter().any(|m| match m {
                        Mem::Unknown => true,
                        Mem::Sym(s) => s == h,
                    });
                    if clobbered {
                        next = if let W::Both(k, _) = next { W::Imm(k) } else { W::Unknown };
                    }
                }
                // `movwf m` leaves a copy of W in m.
                if !wrote_w && let Some(m) = &e.w_mem && e.reads == [Loc::W] && env.is_plain(m) && e.wmem == [Mem::Sym(m.clone())] {
                    next = match &next {
                        W::Imm(k) | W::Both(k, _) => W::Both(*k, m.clone()),
                        _ => W::Mem(m.clone()),
                    };
                }
                // A scratch register written by this instruction no longer matches W.
                if let W::Mem(h) | W::Both(_, h) = &next
                    && let Some(n) = scratch(h)
                    && e.writes.contains(&Loc::S(n))
                {
                    next = if let W::Both(k, _) = next { W::Imm(k) } else { W::Unknown };
                }
                // `movwf __A0` and `movf __A0, w` leave W and the scratch byte equal.
                if let Some(m) = &e.w_scr {
                    next = match &next {
                        W::Imm(k) | W::Both(k, _) if !wrote_w => W::Both(*k, m.clone()),
                        _ if wrote_w => W::Mem(m.clone()),
                        _ => W::Mem(m.clone()),
                    };
                }
                w = next;
            }
            // A fence emits nothing, so what `WREG` holds is still true after it. A conditional
            // branch that is not taken leaves `WREG` alone; the target is a label, which forgets it.
            Item::Fence => {}
            Item::Br(cc, _) if *cc != Cc::Always => {}
            _ => w = W::Unknown,
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// Deletes `movwf v` when `v` is a compiler-placed byte that nothing in the program reads, takes
/// the address of or names any other way (typically a copy of `WREG` that `pass_wreg` made
/// redundant to reload).
fn pass_write_only(items: &mut Vec<Item>, env: &Env) -> bool {
    fn idents(t: &str) -> impl Iterator<Item = &str> {
        t.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).filter(|s| !s.is_empty())
    }
    let keep = protected(items);
    let mut stores: HashMap<&str, Vec<usize>> = HashMap::new();
    let mut used: std::collections::HashSet<&str> = std::collections::HashSet::new();
    for (i, it) in items.iter().enumerate() {
        match it {
            Item::Ins(t) => {
                if let Some((m, ops)) = parse(t)
                    && m == "movwf"
                    && !keep[i]
                    && let Some(&sym) = ops.first()
                    && env.is_plain(sym)
                    && idents(sym).count() == 1
                    && !sym.starts_with("__")
                    && !sym.starts_with("PROD")
                {
                    stores.entry(sym).or_default().push(i);
                    for o in &ops[1..] {
                        used.extend(idents(o));
                    }
                    continue;
                }
                used.extend(idents(t));
            }
            Item::Raw(t) | Item::Label(t) | Item::Call(t) | Item::Br(_, t) | Item::Comment(t) => {
                used.extend(idents(t));
            }
            // The skip instruction reads or counts a variable.
            Item::SkipBr(ins, t) => {
                used.extend(idents(ins));
                used.extend(idents(t));
            }
            _ => {}
        }
    }
    let mut dead = vec![false; items.len()];
    for (sym, at) in &stores {
        if !used.contains(sym) {
            for &i in at {
                dead[i] = true;
            }
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

fn pass_xorlw_zero(items: &mut Vec<Item>) -> bool {
    let mut changed = false;
    let mut i = 1;
    let mut keep = protected(items);
    while i < items.len() {
        if keep[i] {
            i += 1;
            continue;
        }
        let is_zero_test = matches!(&items[i], Item::Ins(t) if matches!(parse(t), Some((m, o)) if (m == "xorlw" || m == "iorlw") && o.len() == 1 && parse_lit(o[0]) == Some(0)));
        if is_zero_test {
            // The previous instruction must have set Z and N from the value now in WREG.
            let mut j = i - 1;
            while j > 0 && matches!(items[j], Item::Comment(_)) {
                j -= 1;
            }
            let ok = matches!(&items[j], Item::Ins(t) if matches!(effect(t), Some(e) if e.writes == [Loc::W] && e.flags_w & zflags() == zflags()));
            // `movf m, w` also qualifies (checked through its effect); `movlw` does not set flags.
            if ok {
                items.remove(i);
                keep = protected(items);
                changed = true;
                continue;
            }
        }
        i += 1;
    }
    changed
}

/// Whether `WREG` and every flag are dead from item `from` on: each path overwrites them, or ends
/// the statement, before anything could read them. Anything it cannot follow counts as a read.
fn w_and_flags_dead(items: &[Item], from: usize, depth: u8) -> bool {
    dead_from(items, from, depth, true, ALL)
}

fn dead_from(items: &[Item], from: usize, depth: u8, mut w: bool, mut needed: u8) -> bool {
    let label_at = |target: &str| items.iter().position(|x| matches!(x, Item::Label(l) if l == target));
    for (k, it) in items.iter().enumerate().skip(from) {
        match it {
            Item::Comment(_) | Item::Label(_) => {}
            Item::Fence => return true,
            Item::Br(Cc::Always, target) if depth > 0 => {
                return label_at(target).is_some_and(|p| dead_from(items, p + 1, depth - 1, w, needed));
            }
            // A bit skip over a branch: the branch target and the code after it must both be dead.
            Item::Ins(t) if depth > 0 && matches!(parse(t), Some((m, _)) if m == "btfsc" || m == "btfss") => {
                let Some(Item::Br(Cc::Always, target)) = items.get(k + 1) else { return false };
                return label_at(target).is_some_and(|p| dead_from(items, p + 1, depth - 1, w, needed))
                    && dead_from(items, k + 2, depth - 1, w, needed);
            }
            // The flags are clobbered across a return (docs/ABI.md); `WREG` may carry the result.
            Item::Ins(t) if matches!(parse(t), Some((m, _)) if m == "return" || m == "retlw") => return !w,
            Item::Ins(t) => match effect(t) {
                None => return false,
                Some(e) => {
                    if (w && e.reads.contains(&Loc::W)) || e.flags_r & needed != 0 {
                        return false;
                    }
                    if e.writes.contains(&Loc::W) {
                        w = false;
                    }
                    needed &= !e.flags_w;
                    if !w && needed == 0 {
                        return true;
                    }
                }
            },
            _ => return false,
        }
    }
    false
}

/// A bit test turned into a Boolean and compared (`movlw 0 ; btfsc R,b ; movlw 1 ; xorlw K ; bnz L`)
/// becomes the bit-skip branch itself (`btfsc R,b ; bra L`), when nothing reads `WREG` or the flags
/// on either path.
fn pass_bit_branch(items: &mut Vec<Item>) -> bool {
    let mut changed = false;
    let mut i = 0;
    // Computed once and again after each rewrite (it parses every item, so per item it made the pass quadratic).
    let mut keep = protected(items);
    while i < items.len() {
        if let Some((n, new)) = match_bit_branch(items, i, &keep) {
            // `n` items from `i`, minus an optional `movlb` between them that is kept.
            items.splice(i..i + n, new);
            keep = protected(items);
            changed = true;
        }
        i += 1;
    }
    changed
}

fn match_bit_branch(items: &[Item], i: usize, keep: &[bool]) -> Option<(usize, Vec<Item>)> {
    let ins = |k: usize| -> Option<(String, Vec<&str>)> {
        match items.get(k)? {
            Item::Ins(t) if !keep[k] => parse(t),
            _ => None,
        }
    };
    let (m, o) = ins(i)?;
    if m != "movlw" || o.len() != 1 || parse_lit(o[0]) != Some(0) {
        return None;
    }
    let mut k = i + 1;
    let mut bank = None;
    if let Some((m, _)) = ins(k) {
        if m == "movlb" {
            bank = Some(items[k].clone());
            k += 1;
        }
    }
    let (skip, bit) = ins(k)?;
    if skip != "btfsc" && skip != "btfss" {
        return None;
    }
    let bit_text = match &items[k] {
        Item::Ins(t) => t.clone(),
        _ => return None,
    };
    let _ = bit;
    // The instruction after a skip is flagged protected; look at it directly.
    let (m, o) = match items.get(k + 1)? {
        Item::Ins(t) => parse(t)?,
        _ => return None,
    };
    if m != "movlw" || o.len() != 1 || parse_lit(o[0]) != Some(1) {
        return None;
    }
    let (m, o) = match items.get(k + 2)? {
        Item::Ins(t) => parse(t)?,
        _ => return None,
    };
    if m != "xorlw" || o.len() != 1 {
        return None;
    }
    let kv = parse_lit(o[0])?;
    if kv > 1 || keep[i] || keep[k] || keep[k + 2] {
        return None;
    }
    let Item::Br(cc, target) = items.get(k + 3)? else { return None };
    let taken_when_equal = match cc {
        Cc::Z => true,
        Cc::Nz => false,
        _ => return None,
    };
    if keep[k + 3] {
        return None;
    }
    // W is the bit (btfsc) or its complement (btfss); the branch is taken when W == K is `taken_when_equal`.
    let w_is_bit = skip == "btfsc";
    // Bit value at which the branch is taken.
    let bit_when_taken = (kv == 1) == (w_is_bit == taken_when_equal);
    if !w_and_flags_dead(items, k + 4, 4) {
        return None;
    }
    let target_at = items.iter().position(|x| matches!(x, Item::Label(l) if l == target))?;
    if !w_and_flags_dead(items, target_at + 1, 4) {
        return None;
    }
    // `btfsc` runs the branch when the bit is set.
    let mn = if bit_when_taken { "btfsc" } else { "btfss" };
    let rest = bit_text.trim().split_once(char::is_whitespace)?.1.to_string();
    let mut new = Vec::new();
    if let Some(b) = bank {
        new.push(b);
    }
    new.push(Item::Ins(format!("{mn} {rest}")));
    new.push(Item::Br(Cc::Always, target.clone()));
    Some((k + 4 - i, new))
}

/// Whether anything but the item at `skip` names the label `name`.
fn label_referenced(items: &[Item], name: &str, skip: usize) -> bool {
    items.iter().enumerate().any(|(k, it)| {
        k != skip
            && match it {
                Item::Br(_, t) | Item::Call(t) => t == name,
                Item::SkipBr(ins, t) => t == name || ins.contains(name),
                Item::Ins(t) | Item::Raw(t) => t.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).any(|w| w == name),
                _ => false,
            }
    })
}

/// A Boolean made on two paths and tested at once becomes a jump on each path:
///
/// ```text
///     movlw A ; bra J ; X: movlw B ; J: movwf R ; movf R, w ; bz T      (A, B = 0, 1 in either order)
/// ```
/// is `movlw A ; movwf R ; bra T-or-next ; X: movlw B ; movwf R ; ...`. Each path keeps its own store to `R` (the
/// write-only pass drops them when nothing reads `R`) and the value in `WREG`; only the flags `movf` set are lost,
/// so none may be read at either destination. `J` must be reached only by the first path.
fn pass_bool_thread(items: &mut Vec<Item>, env: &Env) -> bool {
    let mut changed = false;
    let mut i = 0;
    // Computed once and again after each rewrite (it parses every item, so per item it made the pass quadratic).
    let mut keep = protected(items);
    while i < items.len() {
        if let Some((n, new)) = match_bool_thread(items, i, &keep, env) {
            items.splice(i..i + n, new);
            keep = protected(items);
            changed = true;
        }
        i += 1;
    }
    changed
}

fn match_bool_thread(items: &[Item], i: usize, keep: &[bool], env: &Env) -> Option<(usize, Vec<Item>)> {
    let lit = |k: usize| -> Option<u8> {
        match items.get(k)? {
            Item::Ins(t) if !keep[k] => {
                let (m, o) = parse(t)?;
                if m == "movlw" && o.len() == 1 { parse_lit(o[0]).filter(|v| *v <= 1) } else { None }
            }
            _ => None,
        }
    };
    // The index of the next instruction-like item at or after `k`, passing statement ends and comments.
    let skip_marks = |mut k: usize| {
        while matches!(items.get(k), Some(Item::Fence | Item::Comment(_))) {
            k += 1;
        }
        k
    };
    let a = lit(i)?;
    let Item::Br(Cc::Always, join) = items.get(i + 1)? else { return None };
    if keep[i + 1] {
        return None;
    }
    let mut k = i + 2;
    let mut entry = Vec::new();
    while let Some(Item::Label(l)) = items.get(k) {
        entry.push(Item::Label(l.clone()));
        k += 1;
    }
    if entry.is_empty() {
        return None;
    }
    let b = lit(k)?;
    if b == a {
        return None;
    }
    k += 1;
    // Only the join label may sit here: any other entry would arrive with an unknown `WREG`.
    match items.get(k)? {
        Item::Label(l) if l == join => {}
        _ => return None,
    }
    if label_referenced(items, join, i + 1) {
        return None;
    }
    k += 1;
    let (m, o) = match items.get(k)? {
        Item::Ins(t) if !keep[k] => parse(t)?,
        _ => return None,
    };
    if m != "movwf" || o.is_empty() {
        return None;
    }
    let sym = o[0];
    let store = items[k].clone();
    k = skip_marks(k + 1);
    let (m, o) = match items.get(k)? {
        Item::Ins(t) if !keep[k] => parse(t)?,
        _ => return None,
    };
    if m != "movf" || o.len() < 2 || o[0] != sym || o[1] != "w" {
        return None;
    }
    k += 1;
    // The generator's zero test of `WREG`, when it is still there.
    if let Some(Item::Ins(t)) = items.get(k) {
        if matches!(parse(t), Some((m, o)) if (m == "iorlw" || m == "xorlw") && o.len() == 1 && parse_lit(o[0]) == Some(0)) && !keep[k] {
            k += 1;
        }
    }
    let Item::Br(cc, target) = items.get(k)? else { return None };
    if keep[k] || !matches!(cc, Cc::Z | Cc::Nz) {
        return None;
    }
    let end = k + 1;
    // Taken when the Boolean is zero (`bz`) or non-zero (`bnz`).
    let taken = |v: u8| (*cc == Cc::Z) == (v == 0);
    // Both destinations must not read the flags `movf` set.
    let target_at = items.iter().position(|x| matches!(x, Item::Label(l) if l == target))?;
    if !dead_paths(items, end, false, Z | N) || !dead_paths(items, target_at + 1, false, Z | N) {
        return None;
    }
    // Nothing else reads `R` (writes elsewhere do not count): then neither the store nor the value in `WREG`
    // is needed, provided `WREG` is dead at both destinations.
    let ident = |t: &str, name: &str| t.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).any(|w| w == name);
    let used = items.iter().enumerate().any(|(n, it)| {
        if (i..end).contains(&n) {
            return false;
        }
        match it {
            Item::Ins(t) => {
                if matches!(parse(t), Some((m, o)) if m == "movwf" && o.first() == Some(&sym)) {
                    return false;
                }
                ident(t, sym)
            }
            Item::Raw(t) | Item::Label(t) | Item::Call(t) | Item::Br(_, t) | Item::Comment(t) => ident(t, sym),
            Item::SkipBr(ins, t) => ident(ins, sym) || ident(t, sym),
            _ => false,
        }
    });
    let droppable = !env.keep_writes
        && sym.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).filter(|w| !w.is_empty()).count() == 1
        && env.is_plain(sym)
        && !sym.starts_with("__")
        && !used
        && dead_paths(items, end, true, 0)
        && dead_paths(items, target_at + 1, true, 0);
    let first = |v: u8| -> Vec<Item> {
        if droppable { vec![] } else { vec![Item::Ins(format!("movlw {v}")), store.clone()] }
    };
    let mut new = first(a);
    if taken(a) {
        new.push(Item::Br(Cc::Always, target.clone()));
        new.extend(entry);
        new.extend(first(b));
    } else {
        let rest = format!("{join}f");
        new.push(Item::Br(Cc::Always, rest.clone()));
        new.extend(entry);
        new.extend(first(b));
        new.push(Item::Br(Cc::Always, target.clone()));
        new.push(Item::Label(rest));
    }
    Some((end - i, new))
}

/// A branch to a label that is followed by an unconditional branch goes straight to that branch's target.
fn pass_jump_thread(items: &mut Vec<Item>) -> bool {
    let mut inside = false;
    let in_keep: Vec<bool> = items
        .iter()
        .map(|it| {
            if let Item::Keep(on) = it {
                inside = *on;
            }
            inside
        })
        .collect();
    let mut label_at: HashMap<&str, usize> = HashMap::new();
    for (k, it) in items.iter().enumerate() {
        if let Item::Label(l) = it {
            label_at.insert(l.as_str(), k);
        }
    }
    let mut updates = Vec::new();
    for (i, it) in items.iter().enumerate() {
        let Item::Br(cc, t) = it else { continue };
        if in_keep[i] {
            continue;
        }
        let Some(&p) = label_at.get(t.as_str()) else { continue };
        let mut k = p + 1;
        while matches!(items.get(k), Some(Item::Label(_) | Item::Comment(_) | Item::Fence)) {
            k += 1;
        }
        if let Some(Item::Br(Cc::Always, m)) = items.get(k)
            && m != t
            && !in_keep[k]
        {
            updates.push((i, *cc, m.clone()));
        }
    }
    let changed = !updates.is_empty();
    for (i, cc, m) in updates {
        items[i] = Item::Br(cc, m);
    }
    changed
}

/// `btfsc X ; bra L1 ; bra L2 ; L1:` is `btfss X ; bra L2 ; L1:` (and the other way round): the skip does the work of
/// the first branch. Every match is rewritten.
fn pass_skip_over_branch(items: &mut Vec<Item>) -> bool {
    let mut changed = false;
    while skip_over_branch_once(items) {
        changed = true;
    }
    changed
}

fn skip_over_branch_once(items: &mut Vec<Item>) -> bool {
    let mut inside = false;
    let in_keep: Vec<bool> = items
        .iter()
        .map(|it| {
            if let Item::Keep(on) = it {
                inside = *on;
            }
            inside
        })
        .collect();
    // The test must not be the instruction another skip passes over: then the rewrite would land elsewhere.
    let keep = protected(items);
    for i in 0..items.len().saturating_sub(3) {
        if in_keep[i] || in_keep[i + 3] || keep[i] {
            continue;
        }
        let (Item::Ins(t), Item::Br(Cc::Always, l1), Item::Br(Cc::Always, l2), Item::Label(l)) = (&items[i], &items[i + 1], &items[i + 2], &items[i + 3]) else { continue };
        if l1 != l || l2 == l1 {
            continue;
        }
        let Some((m, o)) = parse(t) else { continue };
        let inverted = match m.as_str() {
            "btfsc" => "btfss",
            "btfss" => "btfsc",
            _ => continue,
        };
        let new = Item::Ins(format!("{inverted} {}", o.join(", ")));
        let l2 = l2.clone();
        items.splice(i..i + 3, [new, Item::Br(Cc::Always, l2)]);
        return true;
    }
    false
}

/// Enhanced mid-range: a bit skip that branches over an unconditional branch (`btfss f,b` + `bra L1`, `bra L2`, `L1:`, the
/// empty `While bit` loop) becomes the opposite skip branching to `L2` (`btfsc f,b` + `bra L2`, `L1:`).
fn pass_skipbr_over_branch(items: &mut Vec<Item>) -> bool {
    let keep = protected(items);
    let mut out = Vec::with_capacity(items.len());
    let mut inside = false;
    let mut changed = false;
    let mut i = 0;
    while i < items.len() {
        if let Item::Keep(on) = &items[i] {
            inside = *on;
        }
        if i + 2 < items.len()
            && !keep[i]
            && !inside
            && let (Item::SkipBr(t, l1), Item::Br(Cc::Always, l2), Item::Label(l)) = (&items[i], &items[i + 1], &items[i + 2])
            && l1 == l
            && l2 != l1
            && let Some((m, o)) = parse(t)
            && let Some(inv) = match m.as_str() {
                "btfsc" => Some("btfss"),
                "btfss" => Some("btfsc"),
                _ => None,
            }
        {
            out.push(Item::SkipBr(format!("{inv} {}", o.join(", ")), l2.clone()));
            changed = true;
            i += 2; // the label stays
            continue;
        }
        out.push(items[i].clone());
        i += 1;
    }
    if changed {
        *items = out;
    }
    changed
}

fn pass_branch_to_next(items: &mut Vec<Item>) -> bool {
    let mut dead = vec![false; items.len()];
    let keep = protected(items);
    for i in 0..items.len() {
        if keep[i] {
            continue;
        }
        let Item::Br(_, target) = &items[i] else { continue };
        let mut j = i + 1;
        while j < items.len() {
            match &items[j] {
                Item::Comment(_) | Item::Fence => j += 1,
                Item::Label(l) if l == target => {
                    dead[i] = true;
                    // The branch carried `WREG` (a routine that takes its argument there) into the target; once it is
                    // gone the code falls into the label, so a statement end between the two must go as well: it would
                    // tell the dead-store passes that nothing in `WREG` is read after it.
                    if matches!(&items[i], Item::Br(Cc::Always, _)) {
                        for (k, it) in items.iter().enumerate().take(j).skip(i + 1) {
                            if matches!(it, Item::Fence) {
                                dead[k] = true;
                            }
                        }
                    }
                    break;
                }
                Item::Label(_) => j += 1,
                _ => break,
            }
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// `rcall f` right before `return` is a jump: the callee's own `return` goes back to our caller.
fn pass_tail_call(items: &mut [Item]) -> bool {
    let keep = protected(items);
    let mut changed = false;
    for i in 0..items.len() {
        if keep[i] {
            continue;
        }
        let Item::Call(target) = &items[i] else { continue };
        let mut j = i + 1;
        while matches!(items.get(j), Some(Item::Comment(_) | Item::Fence)) {
            j += 1;
        }
        if matches!(items.get(j), Some(Item::Ins(t)) if t.trim() == "return") && !keep[j] {
            items[i] = Item::Br(Cc::Always, target.clone());
            changed = true;
        }
    }
    changed
}

/// Instructions that follow a `return`, `retfie` or unconditional branch and carry no label can
/// never run.
fn pass_unreachable(items: &mut Vec<Item>) -> bool {
    let keep = protected(items);
    let mut dead = vec![false; items.len()];
    let mut live = true;
    for (i, it) in items.iter().enumerate() {
        match it {
            Item::Label(_) | Item::Raw(_) | Item::Org(_) | Item::Data(_) | Item::Keep(_) => live = true,
            Item::Comment(_) | Item::Fence => {}
            Item::Ins(_) | Item::Br(..) | Item::Call(_) if !live && !keep[i] => dead[i] = true,
            Item::Ins(t) => {
                let m = t.split_whitespace().next().unwrap_or("").to_ascii_lowercase();
                live = !(matches!(m.as_str(), "return" | "retfie" | "goto" | "retlw") || m == "bra") || keep[i];
            }
            Item::Br(Cc::Always, _) => live = keep[i],
            _ => live = true,
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// The `__halt: bra __halt` that ends the main program is dropped when the code before it never
/// falls through (an endless `Do … Loop`). The label stays: the stack-depth count reads it.
fn pass_halt_loop(items: &mut Vec<Item>) -> bool {
    let Some(h) = items.iter().position(|i| matches!(i, Item::Label(l) if l == "__halt")) else { return false };
    if !matches!(items.get(h + 1), Some(Item::Br(Cc::Always, t)) if t == "__halt") {
        return false;
    }
    let named = items.iter().enumerate().any(|(k, i)| k != h + 1 && matches!(i, Item::Br(_, t) | Item::Call(t) if t == "__halt"));
    let mut j = h;
    while j > 0 && matches!(items[j - 1], Item::Comment(_) | Item::Fence) {
        j -= 1;
    }
    let ends = j > 0
        && match &items[j - 1] {
            // A `bra` that follows a skip instruction (`decfsz` / `bra` loop) is passed over when the skip is taken.
            Item::Br(Cc::Always, _) => !matches!(j.checked_sub(2).map(|k| &items[k]), Some(Item::Ins(t)) if is_skip(t)),
            Item::Ins(t) => matches!(t.split_whitespace().next(), Some("return" | "retfie" | "goto" | "retlw")),
            _ => false,
        };
    if named || !ends {
        return false;
    }
    items.remove(h + 1);
    true
}

/// Drops the compiler's own `_L` labels that nothing names. They only split straight runs of
/// code, which stops the other passes at them.
fn pass_unused_labels(items: &mut Vec<Item>) -> bool {
    let mut used: std::collections::HashSet<&str> = std::collections::HashSet::new();
    for it in items.iter() {
        match it {
            Item::Br(_, t) | Item::SkipBr(_, t) | Item::Call(t) => {
                used.insert(t.as_str());
            }
            Item::Ins(t) | Item::Raw(t) => {
                for tok in t.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')) {
                    if tok.starts_with("_L") {
                        used.insert(tok);
                    }
                }
            }
            _ => {}
        }
    }
    let before = items.len();
    let used: std::collections::HashSet<String> = used.into_iter().map(String::from).collect();
    items.retain(|it| !matches!(it, Item::Label(l) if l.starts_with("_L") && !used.contains(l)));
    items.len() != before
}

/// A polling loop `L: movlb k / … / bra L` that never changes the bank selects it once, before
/// the loop.
fn pass_hoist_movlb(items: &mut Vec<Item>) -> bool {
    let keep = protected(items);
    for i in 0..items.len() {
        let Item::Label(l) = &items[i] else { continue };
        if !l.starts_with("_L") {
            continue;
        }
        let mut m = i + 1;
        while matches!(items.get(m), Some(Item::Comment(_) | Item::Fence)) {
            m += 1;
        }
        let Some(Item::Ins(first)) = items.get(m) else { continue };
        if !first.starts_with("movlb ") || keep[m] {
            continue;
        }
        // The only other mention of the label is the branch that closes the loop.
        let refs: Vec<usize> = (0..items.len())
            .filter(|&k| match &items[k] {
                Item::Br(_, t) | Item::Call(t) => t == l,
                Item::Ins(t) | Item::Raw(t) => t.contains(l.as_str()),
                _ => false,
            })
            .collect();
        let [back] = refs[..] else { continue };
        if back < m || !matches!(&items[back], Item::Br(Cc::Always, _)) {
            continue;
        }
        let clean = (m + 1..back).all(|k| match &items[k] {
            Item::Ins(t) => !t.trim_start().starts_with("movlb"),
            Item::Br(..) | Item::Comment(_) | Item::Fence => true,
            _ => false,
        });
        if !clean {
            continue;
        }
        let mv = items.remove(m);
        items.insert(i, mv);
        return true;
    }
    false
}

/// `movf s,w` / `movwf x` / `movf x,f`: the flags the first load set still describe `x`, so the
/// test of `x` repeats them. Likewise `decf x,f` / `movf x,f` (`s = s - 1 : If s = 0`): an arithmetic or logic
/// instruction that writes `x` has set Z (and on the PIC18 N) from the value `movf` would test, and leaves C alone
/// no differently. Only for compiler-placed RAM, whose read has no side effect.
fn pass_repeat_test(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let real: Vec<usize> = (0..items.len()).filter(|&i| !matches!(items[i], Item::Fence | Item::Comment(_))).collect();
    let mut dead = vec![false; items.len()];
    for w in real.windows(2) {
        let (i, j) = (w[0], w[1]);
        let (Item::Ins(a), Item::Ins(b)) = (&items[i], &items[j]) else { continue };
        if keep[i] || keep[j] {
            continue;
        }
        let (Some((ma, oa)), Some((mb, ob))) = (parse(a), parse(b)) else { continue };
        let sets_zn = matches!(
            ma.as_str(),
            "incf" | "decf" | "addwf" | "addwfc" | "subwf" | "subwfb" | "subfwb" | "andwf" | "iorwf" | "xorwf" | "comf" | "movf"
        );
        if sets_zn
            && oa.len() >= 2
            && matches!(oa[1], "f" | "1")
            && mb == "movf"
            && ob.len() >= 2
            && matches!(ob[1], "f" | "1")
            && oa[0] == ob[0]
            && oa.get(2) == ob.get(2)
            && env.is_plain(ob[0])
        {
            dead[j] = true;
        }
    }
    for w in real.windows(3) {
        let (i, j, k) = (w[0], w[1], w[2]);
        let (Item::Ins(a), Item::Ins(b), Item::Ins(c)) = (&items[i], &items[j], &items[k]) else { continue };
        if keep[j] || keep[k] {
            continue;
        }
        let (Some((ma, oa)), Some((mb, ob)), Some((mc, oc))) = (parse(a), parse(b), parse(c)) else { continue };
        let is_w = |o: &str| matches!(o, "w" | "0");
        let is_f = |o: &str| matches!(o, "f" | "1");
        if ma == "movf" && oa.len() >= 2 && is_w(oa[1]) && mb == "movwf" && !ob.is_empty() && mc == "movf" && oc.len() >= 2 && oc[0] == ob[0] && is_f(oc[1]) && env.is_plain(ob[0]) {
            dead[k] = true;
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// `movf x, w` / `xorlw 1` (or `0xFF`) / `bz` or `bnz`: `decf x, w` (or `incf`) sets Z exactly when `x` is 1 (or 255),
/// one word fewer, when nothing reads `WREG` (now `x - 1` instead of `x ^ 1`), N (now from `x - 1`) or the carry and
/// overflow flags the `decf` also writes, on either side of the branch. Not in a chain of compares that goes on with `xorlw` on `WREG`.
fn pass_incdec_test(items: &mut Vec<Item>) -> bool {
    let keep = protected(items);
    let real: Vec<usize> = (0..items.len()).filter(|&i| !matches!(items[i], Item::Comment(_))).collect();
    let mut edits: Vec<(usize, usize, String)> = Vec::new();
    for w in real.windows(3) {
        let (i, j, k) = (w[0], w[1], w[2]);
        let (Item::Ins(a), Item::Ins(b), Item::Br(Cc::Z | Cc::Nz, _)) = (&items[i], &items[j], &items[k]) else { continue };
        if keep[i] || keep[j] || keep[k] {
            continue;
        }
        let (Some((ma, oa)), Some((mb, ob))) = (parse(a), parse(b)) else { continue };
        if ma != "movf" || oa.len() < 2 || !matches!(oa[1], "w" | "0") || mb != "xorlw" || ob.len() != 1 {
            continue;
        }
        let op = match parse_lit(ob[0]) {
            Some(1) => "decf",
            Some(0xFF) => "incf",
            _ => continue,
        };
        if oa[0].eq_ignore_ascii_case("WREG") || !dead_paths(items, k, true, C | OV | N) {
            continue;
        }
        edits.push((i, j, format!("{op} {}", oa.join(", "))));
    }
    let changed = !edits.is_empty();
    for (i, j, t) in edits.into_iter().rev() {
        items[i] = Item::Ins(t);
        items.remove(j);
    }
    changed
}

/// `movwf x` / `incf x, w` (or `decf`): W already holds `x`, so `addlw 1` (or `addlw 0xFF`) gives the same W and the
/// same Z, N, C and OV without reading `x` again, and the store may then go (`pass_write_only`, `pass_dead_stores`).
fn pass_incdec_w(items: &mut [Item], env: &Env) -> bool {
    let keep = protected(items);
    let real: Vec<usize> = (0..items.len()).filter(|&i| !matches!(items[i], Item::Comment(_))).collect();
    let mut changed = false;
    for w in real.windows(2) {
        let (i, j) = (w[0], w[1]);
        let (Item::Ins(a), Item::Ins(b)) = (&items[i], &items[j]) else { continue };
        if keep[i] || keep[j] {
            continue;
        }
        let (Some((ma, oa)), Some((mb, ob))) = (parse(a), parse(b)) else { continue };
        if ma != "movwf" || oa.is_empty() || !matches!(mb.as_str(), "incf" | "decf") || ob.len() < 2 || !matches!(ob[1], "w" | "0") {
            continue;
        }
        if oa[0] != ob[0] || oa.get(1) != ob.get(2) || !env.is_plain(oa[0]) {
            continue;
        }
        let k = if mb == "incf" { "0x01" } else { "0xFF" };
        items[j] = Item::Ins(format!("addlw {k}"));
        changed = true;
    }
    changed
}

/// `bcc L1 / bra L2 / L1:` is `b!cc L2`.
fn pass_branch_over_branch(items: &mut Vec<Item>) -> bool {
    let keep = protected(items);
    let real: Vec<usize> = (0..items.len()).filter(|&i| !matches!(items[i], Item::Fence | Item::Comment(_))).collect();
    let mut changed = false;
    for w in real.windows(3) {
        let (i, j, k) = (w[0], w[1], w[2]);
        if keep[i] || keep[j] {
            continue;
        }
        if let (Item::Br(cc, l1), Item::Br(Cc::Always, l2), Item::Label(l)) = (&items[i], &items[j], &items[k])
            && *cc != Cc::Always
            && l1 == l
            && l2 != l1
        {
            let (cc, l2) = (cc.invert(), l2.clone());
            items[i] = Item::Br(cc, l2);
            // Emptied rather than removed so the indices stay valid until the next round.
            items[j] = Item::Comment(String::new());
            changed = true;
            break;
        }
    }
    if changed {
        items.retain(|it| !matches!(it, Item::Comment(t) if t.is_empty()));
    }
    changed
}

/// A port-configuration register whose value is only what the program last wrote to it: `ANSELx`,
/// `TRISx`, `LATx`, `WPUx`, `ODCONx`, `SLRCONx`, `INLVLx`. Setting a bit of one to the value it is known to
/// hold changes nothing.
fn quiet_sfr(sym: &str, env: &Env) -> bool {
    if env.is_plain(sym) {
        return false;
    }
    ["ANSEL", "TRIS", "LAT", "WPU", "ODCON", "SLRCON", "INLVL"].iter().any(|p| sym.strip_prefix(p).is_some_and(|r| r.len() == 1 && r.bytes().all(|b| b.is_ascii_uppercase())))
}

/// `clrf ANSELC / bcf ANSELC,5`: a bit set or cleared in a port-configuration register that a `clrf`, `setf`
/// or `movlw k / movwf` in the same straight run already gave that value is not touched again.
fn pass_known_sfr_bits(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let mut known: HashMap<String, u8> = HashMap::new();
    let mut w: Option<u8> = None;
    let mut dead = vec![false; items.len()];
    for (i, it) in items.iter().enumerate() {
        match it {
            Item::Comment(_) | Item::Fence => {}
            // A conditional branch falls through with everything as it was.
            Item::Br(cc, _) if *cc != Cc::Always => {}
            Item::Ins(t) => {
                let Some((mn, ops)) = parse(t) else {
                    known.clear();
                    w = None;
                    continue;
                };
                if keep[i] || matches!(mn.as_str(), "return" | "retfie" | "goto" | "bra" | "call" | "rcall" | "reset") {
                    known.clear();
                    w = None;
                    continue;
                }
                // A write through a pointer could land on any register.
                if ops.iter().any(|o| ["INDF", "POSTINC", "POSTDEC", "PREINC", "PLUSW"].iter().any(|p| o.starts_with(p))) {
                    known.clear();
                }
                let sym = ops.first().copied().unwrap_or("");
                let tracked = quiet_sfr(sym, env);
                match (mn.as_str(), tracked) {
                    ("clrf", true) => {
                        known.insert(sym.to_string(), 0);
                    }
                    ("setf", true) => {
                        known.insert(sym.to_string(), 0xFF);
                    }
                    ("movwf", true) => match w {
                        Some(v) => {
                            known.insert(sym.to_string(), v);
                        }
                        None => {
                            known.remove(sym);
                        }
                    },
                    ("bcf" | "bsf", true) => {
                        let set = mn == "bsf";
                        match (ops.get(1).and_then(|b| b.parse::<u8>().ok()).filter(|b| *b < 8), known.get_mut(sym)) {
                            (Some(b), Some(v)) => {
                                if (*v >> b) & 1 == set as u8 {
                                    dead[i] = true;
                                } else if set {
                                    *v |= 1 << b;
                                } else {
                                    *v &= !(1 << b);
                                }
                            }
                            _ => {
                                known.remove(sym);
                            }
                        }
                        continue;
                    }
                    _ => {
                        // Any other mention of a tracked register may change it.
                        known.retain(|k, _| !ops.iter().any(|o| o == k) && !(mn == "movff" && ops.get(1) == Some(&k.as_str())));
                    }
                }
                w = match (mn.as_str(), ops.as_slice()) {
                    ("movlw", [v]) => parse_lit(v),
                    _ if keeps_w(t) => w,
                    _ => None,
                };
            }
            _ => {
                known.clear();
                w = None;
            }
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// What is known about BSR at a point of the code.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Bank {
    /// No path reaches the point yet.
    Top,
    Is(u8),
    Unknown,
}

impl Bank {
    fn meet(self, o: Bank) -> Bank {
        match (self, o) {
            (Bank::Top, x) | (x, Bank::Top) => x,
            (Bank::Is(a), Bank::Is(b)) if a == b => Bank::Is(a),
            _ => Bank::Unknown,
        }
    }
}

/// A label the program wrote (`L_<number>_<name>`), as opposed to a routine's or a compiler-made one.
fn user_label(l: &str) -> bool {
    l.strip_prefix("L_").is_some_and(|r| r.starts_with(|c: char| c.is_ascii_digit()))
}

/// A label the code generator made for the inside of one routine (loops, `If`, the shared return).
fn local_label(l: &str) -> bool {
    l.starts_with("_L")
}

/// `movlb k` when BSR is already `k` on every path that reaches it.
///
/// A forward data-flow analysis over the whole item list, not just the straight run before the
/// instruction: it follows branches, loops (a polling loop that selects its bank once), skips and
/// joins, takes what a called routine leaves in BSR (the meet of the bank at its `return`s, computed
/// together with everything else) and treats a branch to another routine as a call. The start of a
/// routine, a label some raw assembly mentions and anything the analysis cannot follow have an
/// unknown bank. Gives up without a change when the code has a branch it cannot place.
fn pass_redundant_movlb_flow(items: &mut Vec<Item>) -> bool {
    let n = items.len();
    let keep = protected(items);
    let mut label_at: HashMap<&str, usize> = HashMap::new();
    for (i, it) in items.iter().enumerate() {
        if let Item::Label(l) = it {
            label_at.insert(l.as_str(), i);
        }
    }
    // Labels that raw assembly (or an instruction written as text) names can be entered from anywhere.
    let mut named: std::collections::HashSet<&str> = std::collections::HashSet::new();
    for it in items.iter() {
        if let Item::Raw(t) = it {
            for tok in t.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')) {
                if let Some((&l, _)) = label_at.get_key_value(tok) {
                    named.insert(l);
                }
            }
        }
    }
    // The routine each instruction belongs to: the last label that is not local.
    let mut routine = vec![usize::MAX; n];
    let mut cur = usize::MAX;
    for (i, it) in items.iter().enumerate() {
        // A label the program wrote (a `GoSub` target) is inside a routine, not the start of one.
        if let Item::Label(l) = it && !local_label(l) && !user_label(l) {
            cur = i;
        }
        routine[i] = cur;
    }
    let next_real = |mut i: usize| {
        while i < n && matches!(items[i], Item::Comment(_) | Item::Fence | Item::Keep(_)) {
            i += 1;
        }
        i
    };
    let mut inb = vec![Bank::Top; n + 1];
    let mut exit: HashMap<usize, Bank> = HashMap::new();
    for (i, it) in items.iter().enumerate() {
        if let Item::Label(l) = it && (!local_label(l) || named.contains(l.as_str())) {
            inb[i] = Bank::Unknown;
        }
    }
    if n > 0 {
        inb[0] = Bank::Unknown;
    }
    for sweep in 0.. {
        if sweep > 200 {
            return false;
        }
        let mut changed = false;
        let push = |inb: &mut Vec<Bank>, to: usize, b: Bank, changed: &mut bool| {
            let m = inb[to].meet(b);
            if m != inb[to] {
                inb[to] = m;
                *changed = true;
            }
        };
        for i in 0..n {
            let s = inb[i];
            if s == Bank::Top {
                continue;
            }
            // (state after this item, whether control continues to the next item, extra edges)
            let mut out = s;
            let mut falls = true;
            let mut edges: Vec<(usize, Bank)> = Vec::new();
            let exit_in = |routine: usize, b: Bank, exit: &mut HashMap<usize, Bank>, changed: &mut bool| {
                let e = exit.entry(routine).or_insert(Bank::Top);
                let m = e.meet(b);
                if m != *e {
                    *e = m;
                    *changed = true;
                }
            };
            let callee = |l: &str, exit: &HashMap<usize, Bank>| match label_at.get(l) {
                // A `GoSub` target is a label inside a routine, not a routine: its `return`s are not found by the
                // label, so nothing is known about the bank when it comes back.
                _ if user_label(l) => Bank::Unknown,
                Some(&k) => exit.get(&k).copied().unwrap_or(Bank::Top),
                None => Bank::Unknown,
            };
            match &items[i] {
                Item::Comment(_) | Item::Fence | Item::Keep(_) | Item::Label(_) => {}
                Item::Call(l) => out = callee(l, &exit),
                Item::Br(cc, l) => {
                    match label_at.get(l.as_str()) {
                        Some(&k) if local_label(l) => edges.push((k, s)),
                        Some(&k) if routine[i] != usize::MAX => {
                            // A branch to another routine is a call that does not come back here.
                            let b = exit.get(&k).copied().unwrap_or(Bank::Top);
                            exit_in(routine[i], b, &mut exit, &mut changed);
                            // ... and what it passes on must not be thought known at its start.
                        }
                        Some(_) => {}
                        None => {
                            exit_in(routine[i], Bank::Unknown, &mut exit, &mut changed);
                        }
                    }
                    if *cc == Cc::Always {
                        falls = false;
                    }
                }
                Item::Ins(t) => {
                    let Some((mn, ops)) = parse(t) else { continue };
                    let mentions_bsr = ops.iter().any(|o| o.eq_ignore_ascii_case("BSR"));
                    match mn.as_str() {
                        "movlb" => out = ops.first().and_then(|o| parse_lit(o)).filter(|k| *k < 16).map_or(Bank::Unknown, Bank::Is),
                        "return" | "retlw" => {
                            if routine[i] != usize::MAX {
                                exit_in(routine[i], s, &mut exit, &mut changed);
                            }
                            falls = false;
                        }
                        "retfie" | "reset" | "sleep" => falls = false,
                        "bra" | "goto" => {
                            match ops.first().and_then(|o| label_at.get(*o)) {
                                Some(&k) if local_label(ops[0]) => edges.push((k, s)),
                                Some(&k) if routine[i] != usize::MAX => {
                                    let b = exit.get(&k).copied().unwrap_or(Bank::Top);
                                    exit_in(routine[i], b, &mut exit, &mut changed);
                                }
                                Some(_) => {}
                                None => {
                                    // `bra $+4` and the like land somewhere in this routine.
                                    if ops.first().is_none_or(|o| !o.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')) {
                                        return false;
                                    }
                                    if routine[i] != usize::MAX {
                                        exit_in(routine[i], Bank::Unknown, &mut exit, &mut changed);
                                    }
                                }
                            }
                            falls = false;
                        }
                        "call" | "rcall" => out = ops.first().map_or(Bank::Unknown, |o| callee(o, &exit)),
                        "bz" | "bnz" | "bc" | "bnc" | "bn" | "bnn" | "bov" | "bnov" => match ops.first().and_then(|o| label_at.get(*o)) {
                            Some(&k) => edges.push((k, s)),
                            None => return false,
                        },
                        _ if is_skip(t) => {
                            let j = next_real(i + 1);
                            // A label between the skip and the skipped instruction is not something to model.
                            if matches!(items.get(j), Some(Item::Label(_)) | None) {
                                return false;
                            }
                            edges.push((next_real(j + 1), s));
                        }
                        _ if mentions_bsr => out = Bank::Unknown,
                        _ => {}
                    }
                    if mentions_bsr && mn != "movlb" {
                        out = Bank::Unknown;
                    }
                }
                Item::Raw(_) | Item::SkipBr(..) => out = Bank::Unknown,
                Item::Data(_) => falls = false,
                Item::Org(_) => {
                    out = Bank::Unknown;
                }
            }
            for (k, b) in edges {
                push(&mut inb, k, b, &mut changed);
            }
            if falls && i + 1 <= n {
                push(&mut inb, i + 1, out, &mut changed);
                // Running on into the next routine (a tail call placed right before its target) leaves by that
                // routine's exits.
                let nx = next_real(i + 1);
                if let Some(Item::Label(l)) = items.get(nx)
                    && !local_label(l)
                    && routine[i] != usize::MAX
                    && routine[i] != nx
                {
                    let b = exit.get(&nx).copied().unwrap_or(Bank::Top);
                    exit_in(routine[i], b, &mut exit, &mut changed);
                }
            }
        }
        if !changed {
            break;
        }
    }
    let mut dead = vec![false; n];
    for i in 0..n {
        if let Item::Ins(t) = &items[i]
            && !keep[i]
            && let Some(("movlb", ops)) = parse(t).as_ref().map(|(m, o)| (m.as_str(), o))
            && let Some(k) = ops.first().and_then(|o| parse_lit(o))
            && inb[i] == Bank::Is(k)
        {
            dead[i] = true;
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

fn count_movlb(items: &[Item]) -> usize {
    items.iter().filter(|it| matches!(it, Item::Ins(t) if t.trim_start().starts_with("movlb "))).count()
}

/// A routine that selects the same bank at several places gets one `movlb k` at its start when that
/// lets the flow analysis drop more than it adds (`I2C_WAIT` selects bank 2 in each arm of its polling
/// loop; with the bank selected once on entry the loop body has none). Each routine is tried on a copy.
fn pass_bank_prologue(items: &mut Vec<Item>) -> bool {
    let mut changed = false;
    let mut r = 0;
    while r < items.len() {
        let Item::Label(l) = &items[r] else {
            r += 1;
            continue;
        };
        if local_label(l) {
            r += 1;
            continue;
        }
        let end = (r + 1..items.len()).find(|&k| matches!(&items[k], Item::Label(l) if !local_label(l))).unwrap_or(items.len());
        let mut tally: HashMap<String, usize> = HashMap::new();
        for it in &items[r..end] {
            if let Item::Ins(t) = it && let Some(("movlb", ops)) = parse(t).as_ref().map(|(m, o)| (m.as_str(), o)) && let Some(k) = ops.first() {
                *tally.entry(k.to_string()).or_default() += 1;
            }
        }
        let best = tally.into_iter().filter(|(_, c)| *c >= 2).max_by_key(|(k, c)| (*c, std::cmp::Reverse(k.clone())));
        let Some((k, _)) = best else {
            r = end;
            continue;
        };
        let mut trial = items.clone();
        trial.insert(r + 1, Item::Ins(format!("movlb {k}")));
        let mut guard = 0;
        while pass_redundant_movlb_flow(&mut trial) && guard < 4 {
            guard += 1;
        }
        if count_movlb(&trial) < count_movlb(items) {
            *items = trial;
            changed = true;
            // The region shrank: look at the same label again from the top of the next routine.
            r = (r + 1..items.len()).find(|&k| matches!(&items[k], Item::Label(l) if !local_label(l))).unwrap_or(items.len());
        } else {
            r = end;
        }
    }
    changed
}

/// Whether an instruction sets Z and N before anything reads them, with no statement end, label, branch or call
/// in between. (A statement end is not enough: an earlier pass lets the next statement reuse the flags a load set.)
fn flags_overwritten_first(items: &[Item], from: usize) -> bool {
    let mut need = Z | N;
    for it in &items[from..] {
        match it {
            Item::Comment(_) | Item::Fence => {}
            Item::Ins(t) if t.trim() == "return" => return true,
            Item::Ins(t) => match effect(t) {
                None => return false,
                Some(e) => {
                    if e.flags_r & need != 0 {
                        return false;
                    }
                    need &= !e.flags_w;
                    if need == 0 {
                        return true;
                    }
                }
            },
            _ => return false,
        }
    }
    false
}

/// Whether `WREG` certainly holds `sym` at item `at`, from the instructions just before it (no label, no
/// call, nothing that writes `WREG` or `sym` in between).
fn w_holds(items: &[Item], at: usize, sym: &str) -> bool {
    let mut j = at;
    while j > 0 {
        j -= 1;
        match &items[j] {
            Item::Comment(_) | Item::Fence => {}
            // Not taken, a conditional branch changes nothing.
            Item::Br(cc, _) if *cc != Cc::Always => {}
            Item::Ins(t) => {
                let Some((mn, ops)) = parse(t) else { return false };
                // The instruction before is a skip: this one runs on one path only.
                if j > 0 && matches!(&items[j - 1], Item::Ins(p) if is_skip(p)) {
                    return false;
                }
                let first = ops.first().copied().unwrap_or("");
                if mn == "movwf" && first == sym {
                    return true;
                }
                if mn == "movf" && first == sym && ops.get(1).is_some_and(|d| matches!(*d, "w" | "0")) {
                    return true;
                }
                if !keeps_w(t) || ops.iter().any(|o| *o == sym) || is_skip(t) {
                    return false;
                }
            }
            _ => return false,
        }
    }
    false
}

/// A routine with a one-byte `Result` hands it back in `WREG` as well as in its variable, and the code that
/// called it does not load it again: `rcall F / movf F__RESULT,w` loses the load when the flags it sets are not
/// used. A `return` that does not already have the value in `WREG` gets a `movf F__RESULT,w` first, so the
/// change is made only for a routine whose calls save more than its returns cost. (The variable is still
/// written, and goes when nothing reads it any more.)
fn pass_w_return(items: &mut Vec<Item>, env: &Env) -> bool {
    let mut changed = false;
    for (rt, sym) in &env.byte_results {
        if !env.is_access(sym) {
            continue;
        }
        let keep = protected(items);
        let Some(r) = items.iter().position(|it| matches!(it, Item::Label(l) if l == rt)) else { continue };
        let end = (r + 1..items.len()).find(|&k| matches!(&items[k], Item::Label(l) if !local_label(l))).unwrap_or(items.len());
        // Only routines that leave by a plain `return`.
        let mut returns = Vec::new();
        let mut ok = true;
        for k in r + 1..end {
            match &items[k] {
                Item::Raw(_) | Item::Data(_) | Item::Org(_) | Item::SkipBr(..) => ok = false,
                Item::Br(_, l) if !local_label(l) => ok = false,
                Item::Ins(t) => match parse(t) {
                    Some((m, ops)) => match m.as_str() {
                        "return" if ops.is_empty() => {
                            if keep[k] {
                                ok = false;
                            }
                            returns.push(k);
                        }
                        "return" | "retfie" | "retlw" | "goto" | "reset" | "bra" => ok = false,
                        _ => {}
                    },
                    None => {}
                },
                _ => {}
            }
        }
        // The routine must end in an exit of its own: one that runs on into the next routine (a tail call placed
        // right before its target) hands back that routine's `WREG`.
        let last = (r + 1..end).rev().find(|&k| !matches!(items[k], Item::Comment(_) | Item::Fence));
        let closed = match last.map(|k| &items[k]) {
            Some(Item::Br(Cc::Always, _)) => true,
            Some(Item::Ins(t)) => t.trim() == "return",
            _ => false,
        };
        if !ok || !closed || returns.is_empty() {
            continue;
        }
        let missing: Vec<usize> = returns.iter().copied().filter(|&k| !w_holds(items, k, sym)).collect();
        // The loads after calls that can go.
        let mut loads = Vec::new();
        for c in 0..items.len() {
            if !matches!(&items[c], Item::Call(l) if l == rt) || keep[c] {
                continue;
            }
            let mut d = c + 1;
            while matches!(items.get(d), Some(Item::Comment(_))) {
                d += 1;
            }
            let Some(Item::Ins(t)) = items.get(d) else { continue };
            let Some((m, ops)) = parse(t) else { continue };
            let is_load = m == "movf" && ops.len() == 3 && ops[0] == sym && matches!(ops[1], "w" | "0") && matches!(ops[2], "c" | "0");
            if is_load && !keep[d] && flags_overwritten_first(items, d + 1) {
                loads.push(d);
            }
        }
        if loads.len() <= missing.len() {
            continue;
        }
        let mut edits: Vec<(usize, bool)> = loads.iter().map(|&d| (d, false)).chain(missing.iter().map(|&k| (k, true))).collect();
        edits.sort_by(|a, b| b.0.cmp(&a.0));
        for (k, insert) in edits {
            if insert {
                items.insert(k, Item::Ins(format!("movf {sym}, w, c")));
            } else {
                items.remove(k);
            }
        }
        changed = true;
    }
    changed
}

/// `movf V,w / xorlw A / bnz L … L: movf V,w / xorlw B`: an `If … ElseIf` chain on one variable. `WREG` holds
/// `V xor A` at `L` (which nothing else reaches), so `xorlw A xor B` there gives `V xor B` without loading `V`
/// again: one word and one cycle for each link of the chain.
fn pass_xor_chain(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let lit = |t: &str| -> Option<u8> {
        let (m, ops) = parse(t)?;
        (m == "xorlw" && ops.len() == 1).then(|| parse_lit(ops[0]))?
    };
    for b in 1..items.len().saturating_sub(1) {
        let (Item::Ins(load), Item::Ins(x1), Item::Br(Cc::Nz, l)) = (&items[b - 1], &items[b], &items[b + 1]) else { continue };
        let Some(a) = lit(x1) else { continue };
        let Some((m, ops)) = parse(load) else { continue };
        if m != "movf" || ops.len() != 3 || !matches!(ops[1], "w" | "0") || !env.is_plain(ops[0]) || keep[b - 1] || keep[b] || keep[b + 1] {
            continue;
        }
        let Some(lp) = items.iter().position(|it| matches!(it, Item::Label(x) if x == l)) else { continue };
        if lp + 2 >= items.len() || keep[lp + 1] || keep[lp + 2] {
            continue;
        }
        // Only the branch gets there: it is the single mention, and the code before it does not fall in.
        let mentions = items
            .iter()
            .filter(|it| match it {
                Item::Br(_, t) | Item::Call(t) => t == l,
                Item::Ins(t) | Item::Raw(t) => t.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).any(|tok| tok == l),
                _ => false,
            })
            .count();
        let before = (0..lp).rev().find(|&k| !matches!(items[k], Item::Comment(_) | Item::Fence));
        let closed = match before.map(|k| &items[k]) {
            Some(Item::Br(Cc::Always, _)) => true,
            Some(Item::Ins(t)) => t.trim() == "return",
            _ => false,
        };
        if mentions != 1 || !closed {
            continue;
        }
        let (Item::Ins(again), Item::Ins(x2)) = (&items[lp + 1], &items[lp + 2]) else { continue };
        if again != load {
            continue;
        }
        let Some(bv) = lit(x2) else { continue };
        items[lp + 2] = Item::Ins(format!("xorlw 0x{:02X}", a ^ bv));
        items.remove(lp + 1);
        return true;
    }
    false
}

/// `movlb k` when the bank is already `k` along the straight run before it.
fn pass_redundant_movlb(items: &mut Vec<Item>) -> bool {
    let keep = protected(items);
    let mut known: Option<String> = None;
    let mut dead = vec![false; items.len()];
    for (i, it) in items.iter().enumerate() {
        match it {
            Item::Comment(_) | Item::Fence => {}
            Item::Ins(t) if t.trim_start().starts_with("movlb ") => {
                let k = t.trim_start()[6..].trim().to_string();
                if keep[i] {
                    known = None;
                } else if known.as_deref() == Some(k.as_str()) {
                    dead[i] = true;
                } else {
                    known = Some(k);
                }
            }
            // A conditional branch falls through with the bank unchanged; the rest ends the run.
            Item::Br(cc, _) if *cc != Cc::Always => {}
            Item::Ins(t) if parse(t).is_some_and(|(m, _)| !matches!(m.as_str(), "return" | "retfie" | "goto" | "bra" | "call" | "rcall")) => {
                if keep[i] {
                    known = None;
                }
            }
            _ => known = None,
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// `lfsr n, X` when FSR n already holds X on every path to it: the pointer was loaded earlier in the same straight
/// run and nothing since has written it. `PLUSW`/`INDF` accesses leave the pointer alone, so a second access to the
/// same array (the swap in a bubble sort) reloads nothing. Any other mention of an FSR, the auto-increment forms, a
/// label, a branch taken, a call or raw text forgets what is known. Interrupt handlers save and restore FSR0..2.
///
/// The same holds for a pointer copied in from RAM, `movff S, FSRnL` / `movff S+1, FSRnH` (the pointer of a `ByRef`
/// parameter): the pair goes when FSR n already holds S, and is forgotten when anything may write S or S+1. S is
/// matched by name: a `ByRef` pointer slot has no other name in a straight run (an overlaid frame byte cannot be
/// written while S is still to be read), and routines are not reentrant, so an interrupt does not change it either.
fn pass_redundant_lfsr(items: &mut Vec<Item>) -> bool {
    let keep = protected(items);
    let mut known: [Option<String>; 3] = [None, None, None];
    let mut dead = vec![false; items.len()];
    let mut pair_second = usize::MAX;
    for (i, it) in items.iter().enumerate() {
        if i == pair_second {
            continue;
        }
        match it {
            Item::Comment(_) | Item::Fence => {}
            Item::Br(cc, _) if *cc != Cc::Always => {}
            Item::Ins(t) => {
                let low = t.trim().to_ascii_lowercase();
                if let Some((n, s)) = fsr_pair(items, i) {
                    let v = format!("@{s}");
                    pair_second = i + 1;
                    if keep[i] || keep[i + 1] {
                        known[n] = None;
                    } else if known[n].as_deref() == Some(v.as_str()) {
                        dead[i] = true;
                        dead[i + 1] = true;
                    } else {
                        known[n] = Some(v);
                    }
                    continue;
                }
                for k in known.iter_mut() {
                    if let Some(s) = k.as_deref().and_then(|v| v.strip_prefix('@'))
                        && may_write_sym(&low, s)
                    {
                        *k = None;
                    }
                }
                if let Some(rest) = low.strip_prefix("lfsr ") {
                    let (n, v) = rest.split_once(',').map(|(a, b)| (a.trim(), b.trim())).unwrap_or(("", ""));
                    match (n.parse::<usize>(), v.is_empty()) {
                        (Ok(n), false) if n < 3 => {
                            if keep[i] {
                                known[n] = None;
                            } else if known[n].as_deref() == Some(v) {
                                dead[i] = true;
                            } else {
                                known[n] = Some(v.to_string());
                            }
                        }
                        _ => known = [None, None, None],
                    }
                } else if parse(t).is_none() || low.contains("fsr") || low.contains("inc0") || low.contains("dec0")
                    || low.contains("inc1") || low.contains("dec1") || low.contains("inc2") || low.contains("dec2")
                    || matches!(parse(t), Some((m, _)) if matches!(m.as_str(), "return" | "retfie" | "goto" | "bra" | "call" | "rcall"))
                {
                    known = [None, None, None];
                }
            }
            _ => known = [None, None, None],
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// `movff S, FSRnL` at `i` and `movff S+1, FSRnH` right after it: `(n, S)`, with S in lower case.
fn fsr_pair(items: &[Item], i: usize) -> Option<(usize, String)> {
    let ops = |k: usize| -> Option<(String, String)> {
        let Some(Item::Ins(t)) = items.get(k) else { return None };
        let (mn, o) = parse(t)?;
        (mn == "movff" && o.len() == 2).then(|| (o[0].to_ascii_lowercase(), o[1].to_ascii_lowercase()))
    };
    let (s, d) = ops(i)?;
    let (s1, d1) = ops(i + 1)?;
    let n = d.strip_prefix("fsr")?.strip_suffix('l')?.parse::<usize>().ok().filter(|&n| n < 3)?;
    let ok = d1 == format!("fsr{n}h") && s1 == format!("{s}+1") && !s.contains("fsr") && !s.contains('+') && !s.contains("ind")
        && !s.contains("inc") && !s.contains("dec") && !s.contains("plusw");
    ok.then_some((n, s))
}

/// Whether the instruction `low` (lower case) may write the byte `s` or `s+1`: it names `s` anywhere except as the
/// operand an instruction only reads (`movff s, x`, `movf s, w`, a test or compare). Unknown forms count as writes.
fn may_write_sym(low: &str, s: &str) -> bool {
    if !low.contains(s) {
        return false;
    }
    let Some((mn, o)) = parse(low) else { return true };
    match mn.as_str() {
        "movff" | "movffl" => o.get(1).is_none_or(|d| d.contains(s)),
        "tstfsz" | "cpfseq" | "cpfsgt" | "cpfslt" | "btfsc" | "btfss" => false,
        // A byte instruction with a destination writes its file operand unless the result goes to W. (Not the bit
        // instructions: their second operand is a bit number, so `bcf s, 0` is a write.)
        "addwf" | "addwfc" | "andwf" | "comf" | "decf" | "decfsz" | "dcfsnz" | "incf" | "incfsz" | "infsnz" | "iorwf"
        | "movf" | "rlcf" | "rlncf" | "rrcf" | "rrncf" | "subfwb" | "subwf" | "subwfb" | "swapf" | "xorwf" => {
            !(o.len() >= 2 && matches!(o[1], "w" | "0"))
        }
        _ => true,
    }
}

fn same_byte(env: &Env, a: &str, b: &str) -> bool {
    a == b || env.addr(a).is_some_and(|x| env.addr(b) == Some(x))
}

/// `movff s, d` when `d` already holds the same byte as `s`: an earlier `movff s, d` or `movff d, s` in the same straight
/// run copied it and neither byte has been written since (a result stored to its variable and read straight back into
/// `__A` after an inlined function). Only compiler-placed RAM is reasoned about; anything the pass does not understand,
/// a label, a call or a taken branch forgets every pair, and an indirect write forgets them too.
fn pass_copy_back(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let mut pairs: Vec<(String, String)> = Vec::new();
    // Scratch bytes whose value is a callee's result: no peephole pass can delete the write, so a copy of one may
    // be carried past a statement end (`c = a * b` then `c = c / b`: the product stored to `c` and read back).
    let mut from_call = [false; 16];
    let mut carry: Vec<(String, String)> = Vec::new();
    let mut dead = vec![false; items.len()];
    for (i, it) in items.iter().enumerate() {
        if keep[i] {
            pairs.clear();
            continue;
        }
        match it {
            Item::Comment(_) => {}
            // No scratch value is carried past a statement, so a pair that names one is not either.
            Item::Fence => pairs.retain(|p| carry.contains(p) || (scratch(&p.0).is_none() && scratch(&p.1).is_none())),
            Item::Call(t) if env.reg_calls.contains(t) => {
                pairs.clear();
                carry.clear();
                from_call = [true; 16];
            }
            Item::Br(cc, _) if *cc != Cc::Always => {}
            Item::Ins(t) => {
                let Some(e) = effect(t) else {
                    pairs.clear();
                    carry.clear();
                    from_call = [false; 16];
                    continue;
                };
                for l in &e.writes {
                    if let Loc::S(k) = l {
                        from_call[*k as usize] = false;
                    }
                }
                let movff = parse(t).filter(|(m, o)| m == "movff" && o.len() == 2).map(|(_, o)| (o[0].trim().to_string(), o[1].trim().to_string()));
                if let Some((s, d)) = &movff
                    && pairs.iter().any(|(a, b)| (same_byte(env, a, s) && same_byte(env, b, d)) || (same_byte(env, a, d) && same_byte(env, b, s)))
                {
                    dead[i] = true;
                    continue;
                }
                if e.wmem.contains(&Mem::Unknown) {
                    pairs.clear();
                }
                pairs.retain(|(a, b)| {
                    // Compare plain bytes by address: `X` and `X+0` name the same byte.
                    let same = |x: &str, n: &str| x == n || env.addr(x).is_some_and(|ax| env.addr(n) == Some(ax));
                    let hit = |n: &str| {
                        e.wmem.iter().any(|m| matches!(m, Mem::Sym(x) if same(x, n)))
                            || scratch(n).is_some_and(|k| e.writes.contains(&Loc::S(k)))
                    };
                    !hit(a) && !hit(b)
                });
                carry.retain(|c| pairs.contains(c));
                if let Some((s, d)) = movff
                    && s != d
                    && (scratch(&s).is_some() || env.is_plain(&s))
                    && (scratch(&d).is_some() || env.is_plain(&d))
                {
                    if let Some(k) = scratch(&s)
                        && from_call[k as usize]
                        && scratch(&d).is_none()
                    {
                        carry.push((s.clone(), d.clone()));
                    }
                    pairs.push((s, d));
                }
            }
            _ => {
                pairs.clear();
                carry.clear();
                from_call = [false; 16];
            }
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// [`pass_copy_back`] for the enhanced mid-range core, where a byte copy is `movf s, w` / `movwf d`: the `movwf d`
/// is deleted when `d` already holds the byte `s` (a result stored to its variable and read straight back into `__A`).
/// The `movf` is left for the `WREG` passes. A pair whose scratch byte was last written by a call with its result in
/// the scratch registers survives a statement end, as in [`pass_copy_back`].
fn pass_copy_back16(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let mut pairs: Vec<(String, String)> = Vec::new();
    let mut carry: Vec<(String, String)> = Vec::new();
    let mut from_call = [false; 16];
    // The byte `WREG` is known to copy (`movf s, w`).
    let mut wsrc: Option<String> = None;
    let mut dead = vec![false; items.len()];
    let tracked = |n: &str| scratch(n).is_some() || env.is_plain(n);
    for (i, it) in items.iter().enumerate() {
        if keep[i] {
            pairs.clear();
            carry.clear();
            wsrc = None;
            continue;
        }
        match it {
            Item::Comment(_) => {}
            Item::Fence => {
                pairs.retain(|p| carry.contains(p) || (scratch(&p.0).is_none() && scratch(&p.1).is_none()));
                if wsrc.as_deref().is_some_and(|w| scratch(w).is_some()) {
                    wsrc = None;
                }
            }
            Item::Call(t) if env.reg_calls.contains(t) => {
                pairs.clear();
                carry.clear();
                wsrc = None;
                from_call = [true; 16];
            }
            Item::Ins(t) => {
                let Some(e) = effect(t) else {
                    pairs.clear();
                    carry.clear();
                    wsrc = None;
                    from_call = [false; 16];
                    continue;
                };
                let (mn, ops) = parse(t).unwrap_or_default();
                let movwf = (mn == "movwf" && ops.len() == 1).then(|| ops[0].trim().to_string());
                if let (Some(d), Some(s)) = (&movwf, &wsrc)
                    && pairs.iter().any(|(a, b)| (same_byte(env, a, s) && same_byte(env, b, d)) || (same_byte(env, a, d) && same_byte(env, b, s)))
                {
                    dead[i] = true;
                    continue;
                }
                for l in &e.writes {
                    if let Loc::S(k) = l {
                        from_call[*k as usize] = false;
                    }
                }
                if e.wmem.contains(&Mem::Unknown) {
                    pairs.clear();
                    wsrc = None;
                }
                let hit_by = |n: &str| {
                    e.wmem.iter().any(|m| matches!(m, Mem::Sym(x) if same_byte(env, x, n))) || scratch(n).is_some_and(|k| e.writes.contains(&Loc::S(k)))
                };
                pairs.retain(|(a, b)| !hit_by(a) && !hit_by(b));
                carry.retain(|c| pairs.contains(c));
                if wsrc.as_deref().is_some_and(hit_by) {
                    wsrc = None;
                }
                if let (Some(d), Some(s)) = (&movwf, &wsrc)
                    && !same_byte(env, s, d)
                    && tracked(s)
                    && tracked(d)
                {
                    if let Some(k) = scratch(s)
                        && from_call[k as usize]
                        && scratch(d).is_none()
                    {
                        carry.push((s.clone(), d.clone()));
                    }
                    pairs.push((s.clone(), d.clone()));
                }
                if e.writes.contains(&Loc::W) {
                    wsrc = (mn == "movf" && ops.len() == 2 && matches!(ops[1].trim(), "w" | "0") && tracked(ops[0].trim())).then(|| ops[0].trim().to_string());
                }
            }
            _ => {
                pairs.clear();
                carry.clear();
                wsrc = None;
                from_call = [false; 16];
            }
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// Whether `sym` (`F__TMP` or `F__TMP+1`) is a compiler temporary: never address-taken, so only the named reads see it.
fn is_temp(sym: &str) -> bool {
    split_off(sym).is_some_and(|(n, _)| n.ends_with("__TMP"))
}

/// Enhanced mid-range copy forwarding: after `movf s, w` / `movwf d` (both bytes compiler-placed or scratch), a later
/// `movf d, w` reads `s` instead while neither byte has been written. Chains collapse a step per round
/// (`__A <- __C`, `TMP <- __A`, read `TMP` becomes a read of `__C`), and [`pass_dead_temp_stores`] then removes the
/// copies that nothing reads.
fn pass_forward16(items: &mut [Item], env: &Env) -> bool {
    let keep = protected(items);
    let mut pairs: Vec<(String, String)> = Vec::new(); // (d, s): d holds the byte s
    let mut wsrc: Option<String> = None;
    let mut edits: Vec<(usize, String)> = Vec::new();
    let tracked = |n: &str| scratch(n).is_some() || env.is_plain(n);
    for (i, it) in items.iter().enumerate() {
        if keep[i] {
            pairs.clear();
            wsrc = None;
            continue;
        }
        match it {
            Item::Comment(_) => {}
            Item::Fence => {
                pairs.retain(|(a, b)| scratch(a).is_none() && scratch(b).is_none());
                if wsrc.as_deref().is_some_and(|w| scratch(w).is_some()) {
                    wsrc = None;
                }
            }
            Item::Ins(t) => {
                let Some(e) = effect(t) else {
                    pairs.clear();
                    wsrc = None;
                    continue;
                };
                let (mn, ops) = parse(t).unwrap_or_default();
                let to_w = mn == "movf" && ops.len() == 2 && matches!(ops[1].trim(), "w" | "0");
                let mut read = to_w.then(|| ops[0].trim().to_string());
                if let Some(d) = &read
                    && let Some((_, src)) = pairs.iter().find(|(a, _)| same_byte(env, a, d))
                {
                    edits.push((i, format!("movf {src}, w")));
                    read = Some(src.clone());
                }
                if e.wmem.contains(&Mem::Unknown) {
                    pairs.clear();
                    wsrc = None;
                }
                let hit_by = |n: &str| {
                    e.wmem.iter().any(|m| matches!(m, Mem::Sym(x) if same_byte(env, x, n))) || scratch(n).is_some_and(|k| e.writes.contains(&Loc::S(k)))
                };
                pairs.retain(|(a, b)| !hit_by(a) && !hit_by(b));
                if wsrc.as_deref().is_some_and(hit_by) {
                    wsrc = None;
                }
                if mn == "movwf"
                    && ops.len() == 1
                    && let Some(s) = &wsrc
                {
                    let d = ops[0].trim().to_string();
                    if !same_byte(env, s, &d) && tracked(s) && tracked(&d) {
                        pairs.push((d, s.clone()));
                    }
                }
                if e.writes.contains(&Loc::W) {
                    wsrc = read.filter(|r| tracked(r));
                }
            }
            _ => {
                pairs.clear();
                wsrc = None;
            }
        }
    }
    let changed = !edits.is_empty();
    for (i, t) in edits {
        items[i] = Item::Ins(t);
    }
    changed
}

/// Enhanced mid-range result retargeting: a value built in a scratch byte `__An` and then copied
/// (`movf __An, w` / `movwf D`) into a compiler-placed variable `D` is built in `D` instead. From the last pure write of
/// `__An` (`movwf`, `clrf`) to the copy, every operand `__An` becomes `D` and the copy goes, so `t = x + y` is
/// `movf x, w` / `addwf y, w` / `movwf t`-shaped work done in `t` with no staging (the 16F half of the PIC18 result
/// coalescing). Only when the stretch is straight-line, nothing in it reads or writes `D` or reaches memory through an
/// FSR, and `__An` is dead after the copy. The writes to `D` move up past the stretch, the same ordering the in-place
/// `t = t + 3` already has.
fn pass_retarget16(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let mut dead = vec![false; items.len()];
    let mut edits: Vec<(usize, String)> = Vec::new();
    let mut claimed = vec![false; items.len()];
    for j in 1..items.len() {
        if keep[j] || claimed[j] {
            continue;
        }
        let Item::Ins(t) = &items[j] else { continue };
        let Some((mn, ops)) = parse(t) else { continue };
        if mn != "movwf" || ops.len() != 1 {
            continue;
        }
        let d = ops[0].to_string();
        if scratch(&d).is_some() || is_indirect(&d) || !env.is_plain(&d) || split_off(&d).is_none_or(|(n, _)| env.shared.contains(n)) {
            continue;
        }
        // The load right before: `movf __An, w`.
        let mut c = j;
        let mut found_load = None;
        while c > 0 {
            c -= 1;
            match &items[c] {
                Item::Comment(_) => {}
                Item::Ins(u) if !keep[c] => {
                    found_load = parse(u).and_then(|(m, o)| (m == "movf" && o.len() == 2 && matches!(dest(o[1]), Some(Dest::W))).then(|| o[0].to_string()));
                    break;
                }
                _ => break,
            }
        }
        let Some(src) = found_load else { continue };
        let Some(k) = scratch(&src) else { continue };
        if claimed[c] {
            continue;
        }
        // Back from the load to the last pure write of `__An`.
        let mut window: Vec<usize> = vec![c];
        let mut def = None;
        let mut m = c;
        let mut ok = true;
        while m > 0 && window.len() < 40 && c - m < 120 {
            m -= 1;
            match &items[m] {
                Item::Comment(_) => {}
                Item::Ins(u) if !keep[m] && !claimed[m] => {
                    let Some(e) = effect(u) else {
                        ok = false;
                        break;
                    };
                    // A bank or page select in the stretch: `D` may need a bank the scratch byte (common RAM) does not.
                    if matches!(parse(u), Some((mm, _)) if mm == "movlb" || mm == "movlp") {
                        ok = false;
                        break;
                    }
                    let touches_d = e.rmem.iter().any(|r| same_byte(env, r, &d) || is_indirect(r))
                        || e.wmem.iter().any(|w| match w {
                            Mem::Unknown => true,
                            Mem::Sym(w) => same_byte(env, w, &d),
                        });
                    if touches_d {
                        ok = false;
                        break;
                    }
                    let reads_s = e.reads.contains(&Loc::S(k));
                    let writes_s = e.writes.contains(&Loc::S(k));
                    if writes_s && !reads_s {
                        // `movwf`/`clrf` only: another instruction form would need its own operand rewrite.
                        let (wm, _) = parse(u).unwrap_or_default();
                        if matches!(wm.as_str(), "movwf" | "clrf") {
                            def = Some(m);
                        } else {
                            ok = false;
                        }
                        break;
                    }
                    if reads_s || writes_s {
                        window.push(m);
                    }
                }
                _ => {
                    ok = false;
                    break;
                }
            }
        }
        let (true, Some(def)) = (ok, def) else { continue };
        window.push(def);
        if !matches!(loc_live(items, j, Loc::S(k), env), Live::Dead) {
            continue;
        }
        // `__An` must be read only inside the stretch between the def and the copy (anything else in it is `D`-free).
        for &w in &window {
            let Item::Ins(u) = &items[w] else { continue };
            let (wm, wo) = parse(u).unwrap();
            let new: Vec<String> = wo.iter().map(|o| if scratch(o) == Some(k) { d.clone() } else { o.to_string() }).collect();
            edits.push((w, format!("{wm} {}", new.join(", "))));
            claimed[w] = true;
        }
        claimed[j] = true;
        dead[j] = true;
    }
    let changed = dead.iter().any(|&x| x);
    for (i, t) in edits {
        items[i] = Item::Ins(t);
    }
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// Deletes `movwf T` to a compiler temporary that nothing reads before it is written again (or the routine returns).
fn pass_dead_temp_stores(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let mut dead = vec![false; items.len()];
    for (i, it) in items.iter().enumerate() {
        let Item::Ins(t) = it else { continue };
        if keep[i] {
            continue;
        }
        let Some((m, o)) = parse(t) else { continue };
        if m == "movwf" && o.len() == 1 && is_temp(o[0].trim()) && env.is_plain(o[0].trim()) && byte_dead_paths(items, i + 1, o[0].trim(), env) {
            dead[i] = true;
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// Whether the RAM byte `sym` cannot be read again from item `from` on before it is written (or the routine
/// returns): follows both sides of every branch and skip, through statement ends (a value held in a temporary may be
/// reused across one, see `pass_load_reuse`). A call, raw assembly, anything it cannot follow, or a long search counts
/// as a read.
fn byte_dead_paths(items: &[Item], from: usize, sym: &str, env: &Env) -> bool {
    let label_at = |target: &str| items.iter().position(|x| matches!(x, Item::Label(l) if l == target));
    let mut work = vec![from];
    let mut seen = std::collections::HashSet::new();
    let mut budget = 400usize;
    while let Some(mut k) = work.pop() {
        if !seen.insert(k) {
            continue;
        }
        loop {
            if budget == 0 {
                return false;
            }
            budget -= 1;
            let Some(it) = items.get(k) else { return false };
            match it {
                Item::Comment(_) | Item::Label(_) | Item::Fence => {}
                Item::Br(cc, target) => {
                    let Some(p) = label_at(target) else { return false };
                    if *cc == Cc::Always {
                        k = p;
                        continue;
                    }
                    work.push(p);
                }
                Item::Ins(t) => {
                    if matches!(parse(t), Some((m, _)) if m == "return" || m == "retlw" || m == "retfie") {
                        break;
                    }
                    let Some(e) = effect(t) else { return false };
                    if e.rmem.iter().any(|m| same_byte(env, m, sym)) {
                        return false;
                    }
                    let written = e.wmem.iter().any(|m| matches!(m, Mem::Sym(x) if same_byte(env, x, sym)));
                    if is_skip(t) {
                        let mut n = k + 1;
                        while matches!(items.get(n), Some(Item::Comment(_) | Item::Fence)) {
                            n += 1;
                        }
                        if !matches!(items.get(n), Some(Item::Ins(_) | Item::Br(..))) {
                            return false;
                        }
                        work.push(n + 1);
                    } else if written {
                        break;
                    }
                }
                _ => return false,
            }
            k += 1;
        }
    }
    true
}

/// The RAM byte a pure store writes: `clrf X`, `setf X`, `movwf X` or `movff s, X` (the instruction does not read `X`).
fn pure_store_target(t: &str, env: &Env) -> Option<String> {
    let (m, o) = parse(t)?;
    let d = match (m.as_str(), o.len()) {
        ("clrf" | "setf" | "movwf", 1..=2) => o[0].trim(),
        ("movff", 2) if !same_byte(env, o[0].trim(), o[1].trim()) => o[1].trim(),
        _ => return None,
    };
    (env.is_plain(d) && scratch(d).is_none()).then(|| d.to_string())
}

/// A store to compiler-placed RAM that the same straight run stores to again before anything can read the byte
/// (`clrf R+1` from widening `Result = ADRESL`, then `movff ADRESH, R+1`): the first store is deleted. The run ends at
/// a branch, a skip, a call, raw assembly or anything the pass does not understand, which keep the store; an
/// indirect read or write keeps it too (it could reach the byte). An interrupt handler that reads the variable in
/// between would have seen the first value: that ordering is not one the program relies on (see the module notes).
fn pass_overwritten_store(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let mut dead = vec![false; items.len()];
    for i in 0..items.len() {
        if keep[i] {
            continue;
        }
        let Item::Ins(t) = &items[i] else { continue };
        let Some(sym) = pure_store_target(t, env) else { continue };
        let Some(e0) = effect(t) else { continue };
        // The store's own read must have no side effect: `movff SSP1BUF, X` reads a FIFO and `movff POSTINC0, X` steps FSR0.
        if !e0.rmem.iter().all(|m| env.is_plain(m)) {
            continue;
        }
        if e0.flags_w != 0 && flags_live(items, i, e0.flags_w) {
            continue;
        }
        let mut over = false;
        for (k, it) in items.iter().enumerate().skip(i + 1) {
            match it {
                Item::Comment(_) | Item::Fence | Item::Label(_) => {}
                Item::Ins(u) => {
                    if keep[k] {
                        break;
                    }
                    let Some(e) = effect(u) else { break };
                    // A read the address lookup cannot place (`X+1+1`, an absolute address) may be the byte itself.
                    let may_read = |m: &String| {
                        is_indirect(m) || same_byte(env, m, &sym) || (env.addr(m).is_none() && (m.contains('+') || m.starts_with(|c: char| c.is_ascii_digit())))
                    };
                    if is_skip(u) || e.wmem.contains(&Mem::Unknown) || e.rmem.iter().any(may_read) {
                        break;
                    }
                    if pure_store_target(u, env).is_some_and(|d| same_byte(env, &d, &sym)) {
                        over = true;
                        break;
                    }
                    if e.wmem.iter().any(|m| matches!(m, Mem::Sym(x) if same_byte(env, x, &sym))) {
                        break;
                    }
                }
                _ => break,
            }
        }
        dead[i] = over;
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// `movf X, w` + `movwf T` (or `movff X, T`), a few instructions that set up an index in `WREG` / an FSR, then
/// `movff T, <indirect>`: the value is staged in `T` only because `WREG` is needed for the index. When nothing in
/// between writes `X` or touches `T`, the flags the `movf` sets are dead, the first instruction after it overwrites
/// `WREG`, and `T` is not read again before it is written, the store reads `X` itself (2 words, or 4 for `movff`).
fn pass_stage_store(items: &mut Vec<Item>, env: &Env) -> bool {
    let mut keep = protected(items);
    let mut changed = false;
    let mut i = 0;
    while i + 2 < items.len() {
        let ins = |k: usize| -> Option<(String, Vec<String>)> {
            match items.get(k) {
                Some(Item::Ins(t)) if !keep[k] => parse(t).map(|(m, o)| (m, o.iter().map(|x| x.trim().to_string()).collect())),
                _ => None,
            }
        };
        // The staging: (source, temporary, items it takes).
        let stage = match (ins(i), ins(i + 1)) {
            (Some((m1, o1)), Some((m2, o2))) if m1 == "movf" && o1.len() >= 2 && o1[1] == "w" && m2 == "movwf" && !o2.is_empty() => Some((o1[0].clone(), o2[0].clone(), 2)),
            (Some((m1, o1)), _) if m1 == "movff" && o1.len() == 2 => Some((o1[0].clone(), o1[1].clone(), 1)),
            _ => None,
        };
        let Some((x, t, used)) = stage else {
            i += 1;
            continue;
        };
        // `TABLAT` too: reading it has no side effect, and only a table read (which ends the window) changes it.
        let source_ok = env.is_plain(&x) || x.eq_ignore_ascii_case("TABLAT");
        if !source_ok || !env.is_plain(&t) || scratch(&t).is_some() || same_byte(env, &x, &t) {
            i += 1;
            continue;
        }
        // The window: straight-line instructions up to the store.
        let mut j = i + used;
        let mut found = None;
        let mut first = true;
        while j < items.len() && j < i + used + 8 {
            let Some((m, o)) = ins(j) else { break };
            let Item::Ins(text) = &items[j] else { break };
            if m == "movff" && o.len() == 2 && same_byte(env, &o[0], &t) && is_indirect(&o[1]) {
                found = Some((j, o[1].clone()));
                break;
            }
            let Some(e) = effect(text) else { break };
            // A scratch byte's writes are tracked locations (`writes`), not untracked memory (`wmem`).
            let x_scratch_written = scratch(&x).is_some_and(|k| e.writes.contains(&Loc::S(k)));
            if is_skip(text) || x_scratch_written || e.rmem.iter().any(|r| same_byte(env, r, &t))
                || e.wmem.iter().any(|w| matches!(w, Mem::Unknown) || matches!(w, Mem::Sym(s) if same_byte(env, s, &t) || same_byte(env, s, &x)))
            {
                break;
            }
            if first && used == 2 && !(e.writes.contains(&Loc::W) && !e.reads.contains(&Loc::W)) {
                break;
            }
            first = false;
            j += 1;
        }
        let Some((j, dst)) = found else {
            i += 1;
            continue;
        };
        if j == i + used || (used == 2 && flags_live(items, i, Z | N)) || !byte_dead_paths(items, j + 1, &t, env) {
            i += 1;
            continue;
        }
        items[j] = Item::Ins(format!("movff {x}, {dst}"));
        items.drain(i..i + used);
        keep = protected(items);
        changed = true;
    }
    changed
}

/// One array element already copied into a byte of compiler RAM: `arr(idx + add)` is in `holder`.
struct Held {
    arr: String,
    idx: String,
    add: String,
    holder: String,
}

/// FSR0 is not used again before it is reloaded or the run ends (no pass keeps FSR0 across a label, call or jump).
fn fsr0_dead_after(items: &[Item], from: usize) -> bool {
    for it in &items[from + 1..] {
        match it {
            Item::Comment(_) | Item::Fence => {}
            Item::Br(cc, _) if *cc != Cc::Always => {}
            Item::Ins(t) => {
                let low = t.trim().to_ascii_lowercase();
                if low.starts_with("lfsr 0") {
                    return true;
                }
                if low.contains("plusw0") || low.contains("indf0") || low.contains("inc0") || low.contains("dec0") || low.contains("fsr0") || low.starts_with("addfsr 0") || low.starts_with("subfsr 0") || parse(t).is_none() {
                    return false;
                }
            }
            _ => return true,
        }
    }
    true
}

/// `movf i, w; [addlw k]; lfsr 0, A; movf PLUSW0, w; movwf h` reads `A(i+k)` into `h`. When an earlier load of the same
/// element went into a byte `r` that has not been written since (nor `i`, nor `A` through any store), the four or five
/// instructions become `movf r, w` (the bubble-sort swap rereads `data(j)` and `data(j+1)` it compared a moment before).
/// The `lfsr` goes too when FSR0 is not used before its next load. Any indirect store, label, call or unknown
/// instruction forgets what is held.
fn pass_load_reuse(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let n = items.len();
    let mut held: Vec<Held> = Vec::new();
    let mut out: Vec<Item> = Vec::with_capacity(n);
    let mut changed = false;
    let same = |a: &str, b: &str| a == b || env.addr(a).is_some_and(|x| env.addr(b) == Some(x));
    let ins_at = |i: usize| -> Option<(String, Vec<String>)> {
        match items.get(i) {
            Some(Item::Ins(t)) if !keep[i] => parse(t).map(|(m, o)| (m, o.iter().map(|x| x.trim().to_string()).collect())),
            _ => None,
        }
    };
    let mut i = 0;
    while i < n {
        if keep[i] {
            held.clear();
        }
        // Try to match a group starting here.
        let g = (|| {
            let (m0, o0) = ins_at(i)?;
            if m0 != "movf" || o0.len() != 3 || !matches!(o0[1].as_str(), "w" | "0") || o0[2] != "c" || !env.is_plain(&o0[0]) || scratch(&o0[0]).is_some() {
                return None;
            }
            let mut j = i + 1;
            let mut add = String::new();
            if let Some((m, o)) = ins_at(j)
                && m == "addlw"
                && o.len() == 1
            {
                add = o[0].clone();
                j += 1;
            }
            let (ml, ol) = ins_at(j)?;
            if ml != "lfsr" || ol.len() != 2 || ol[0] != "0" {
                return None;
            }
            let arr = ol[1].clone();
            let lf = j;
            let (mr, or) = ins_at(j + 1)?;
            if mr != "movf" || or.len() != 3 || !or[0].eq_ignore_ascii_case("PLUSW0") || !matches!(or[1].as_str(), "w" | "0") {
                return None;
            }
            let rd = j + 1;
            let h = match ins_at(j + 2) {
                Some((mw, ow)) if mw == "movwf" && ow.len() == 2 && ow[1] == "c" && env.is_plain(&ow[0]) && scratch(&ow[0]).is_none() => Some(ow[0].clone()),
                _ => None,
            };
            Some((o0[0].clone(), add, arr, lf, rd, h))
        })();
        if let Some((idx, add, arr, lf, rd, h)) = g {
            let hit = held.iter().find(|e| e.arr == arr && e.add == add && same(&e.idx, &idx)).map(|e| e.holder.clone());
            let flags_ok = add.is_empty() || !flags_live(items, rd, C | OV);
            if let (Some(r), true) = (hit, flags_ok) {
                // Replace the load; keep the `lfsr` unless FSR0 is dead after it.
                out.push(Item::Ins(format!("movf {r}, w, c")));
                if !fsr0_dead_after(items, rd) {
                    out.push(items[lf].clone());
                }
                changed = true;
                i = rd + 1;
                // The `movwf h` that follows is processed as an ordinary instruction (it records h too).
                if let Some(h) = &h {
                    held.retain(|e| !same(&e.holder, h) && !same(&e.idx, h));
                    if !same(&r, h) {
                        held.push(Held { arr, idx, add, holder: h.clone() });
                    }
                    out.push(items[i].clone());
                    i += 1;
                }
                continue;
            }
            // No earlier copy: copy the group through and remember the new one.
            for k in i..(rd + 1 + usize::from(h.is_some())) {
                out.push(items[k].clone());
            }
            if let Some(h) = h {
                held.retain(|e| !same(&e.holder, &h) && !same(&e.idx, &h));
                held.push(Held { arr, idx, add, holder: h });
                i = rd + 2;
            } else {
                i = rd + 1;
            }
            continue;
        }
        // An ordinary item.
        match &items[i] {
            Item::Comment(_) | Item::Fence => {}
            Item::Br(cc, _) if *cc != Cc::Always => {}
            Item::Ins(t) => match effect(t) {
                None => held.clear(),
                Some(e) => {
                    if e.wmem.contains(&Mem::Unknown) {
                        held.clear();
                    }
                    held.retain(|h| {
                        !e.wmem.iter().any(|m| matches!(m, Mem::Sym(x) if same(x, &h.holder) || same(x, &h.idx) || split_off(x).map(|b| b.0) == split_off(&h.arr).map(|b| b.0)))
                    });
                }
            },
            _ => held.clear(),
        }
        out.push(items[i].clone());
        i += 1;
    }
    if changed {
        *items = out;
    }
    changed
}

/// A wide sum built in `__A`: `movff X0, __A0 ...` then `movf Y0, w ; addwf __A0, f ; movf Y1, w ; addwfc __A1, f ...`.
/// Returns the byte count and the symbols it reads, when `items[i..]` starts one.
fn sum_group(items: &[Item], i: usize, keep: &[bool]) -> Option<(usize, Vec<String>)> {
    let ins = |k: usize| -> Option<(String, Vec<String>)> {
        match items.get(k) {
            Some(Item::Ins(t)) if !keep[k] => parse(t).map(|(m, o)| (m, o.iter().map(|x| x.trim().to_string()).collect())),
            _ => None,
        }
    };
    let mut n = 0;
    while n < 4 {
        match ins(i + n) {
            Some((m, o)) if m == "movff" && o.len() == 2 && scratch(&o[1]) == Some(n as u8) && scratch(&o[0]).is_none() => n += 1,
            _ => break,
        }
    }
    if n < 2 {
        return None;
    }
    let mut syms = Vec::new();
    for k in 0..n {
        syms.push(ins(i + k)?.1[0].clone());
    }
    for k in 0..n {
        let (m, o) = ins(i + n + 2 * k)?;
        if m != "movf" || o.len() != 3 || !matches!(o[1].as_str(), "w" | "0") || scratch(&o[0]).is_some() {
            return None;
        }
        syms.push(o[0].clone());
        let (m, o) = ins(i + n + 2 * k + 1)?;
        let want = if k == 0 { "addwf" } else { "addwfc" };
        if m != want || o.len() != 3 || scratch(&o[0]) != Some(k as u8) || o[1] != "f" {
            return None;
        }
    }
    Some((n, syms))
}

/// A wide sum built in `__A` again while `__A` still holds it: `if acc >= r + b then acc = acc - (r + b)`. Nothing
/// between the two copies may write `__A`'s bytes or either operand, and no label may let another path in. The later
/// copy goes when `WREG` and the flags are dead after it (it leaves the sum in `__A`, which is all the rest reads).
fn pass_sum_share(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let mut dead = vec![false; items.len()];
    let mut i = 0;
    while i < items.len() {
        let Some((n, syms)) = sum_group(items, i, &keep) else {
            i += 1;
            continue;
        };
        let len = 3 * n;
        let mut k = i;
        let mut found = false;
        while k > 0 && i - k < 80 {
            k -= 1;
            // An earlier copy ending at `k`, identical text.
            if k + 1 >= len && (0..len).all(|j| matches!((&items[k + 1 - len + j], &items[i + j]), (Item::Ins(a), Item::Ins(b)) if a == b)) && !dead[k + 1 - len] && sum_group(items, k + 1 - len, &keep).is_some() {
                found = true;
                break;
            }
            if keep[k] {
                break;
            }
            match &items[k] {
                Item::Comment(_) => {}
                Item::Br(cc, _) if *cc != Cc::Always => {}
                Item::Ins(t) => {
                    let Some(e) = effect(t) else { break };
                    let hits = |name: &str| {
                        e.wmem.iter().any(|m| matches!(m, Mem::Unknown) || matches!(m, Mem::Sym(x) if same_byte(env, x, name)))
                            || scratch(name).is_some_and(|s| e.writes.contains(&Loc::S(s)))
                    };
                    if syms.iter().any(|s| hits(s)) || (0..n).any(|b| e.writes.contains(&Loc::S(b as u8)) || e.wmem.iter().any(|m| matches!(m, Mem::Sym(x) if same_byte(env, x, &format!("__A{b}"))))) {
                        break;
                    }
                }
                _ => break,
            }
        }
        if found && w_and_flags_dead(items, i + len, 2) {
            for d in dead.iter_mut().skip(i).take(len) {
                *d = true;
            }
            i += len;
        } else {
            i += 1;
        }
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

/// Instructions that leave `WREG` alone.
fn keeps_w(t: &str) -> bool {
    let Some((mn, ops)) = parse(t) else { return false };
    match mn.as_str() {
        "nop" | "movlb" | "movwf" | "movff" | "clrf" | "setf" | "bsf" | "bcf" | "btg" | "btfss" | "btfsc" | "tblrd*" | "tblrd*+" | "tblrd*-" | "tblrd+*" | "lfsr" | "bra" | "bz" | "bnz" | "bc" | "bnc" | "bn" | "bnn" | "bov" | "bnov" => true,
        // Byte instructions that put their result back in the file register.
        "incf" | "decf" | "comf" | "swapf" | "rlcf" | "rrcf" | "rlncf" | "rrncf" | "addwf" | "addwfc" | "subwf" | "subwfb" | "andwf" | "iorwf" | "xorwf" | "movf" | "decfsz" | "incfsz" | "infsnz" | "dcfsnz" => {
            ops.get(1).is_some_and(|d| matches!(*d, "f" | "1"))
        }
        _ => false,
    }
}

/// A routine that takes its argument in `WREG` starts with `movwf P` (marked by a `warg` comment).
/// When `P` is read once, by `movf P,w`, and `WREG` is certainly unchanged until then, both go:
/// the argument is used straight from `WREG`. When `P` is never read the store goes.
fn pass_warg(items: &mut Vec<Item>) -> bool {
    let keep = protected(items);
    for c in 0..items.len() {
        if !matches!(&items[c], Item::Comment(t) if t == "warg") {
            continue;
        }
        let Some(m) = (c + 1..items.len().min(c + 4)).find(|&k| matches!(&items[k], Item::Ins(t) if t.trim_start().starts_with("movwf "))) else { continue };
        if (c + 1..m).any(|k| !matches!(&items[k], Item::Ins(t) if t.trim_start().starts_with("movlb "))) || keep[m] {
            continue;
        }
        let Item::Ins(store) = &items[m] else { continue };
        let Some((_, ops)) = parse(store) else { continue };
        let sym = ops[0].to_string();
        let mentions = |t: &str| t.split(|ch: char| !(ch.is_ascii_alphanumeric() || ch == '_')).any(|tok| tok == sym);
        let mut others = Vec::new();
        let mut opaque = false;
        for (k, it) in items.iter().enumerate() {
            match it {
                Item::Ins(t) if k != m && mentions(t) => others.push(k),
                Item::Raw(t) if mentions(t) => opaque = true,
                _ => {}
            }
        }
        if opaque {
            continue;
        }
        let mut gone = vec![m];
        if let [r] = others[..] {
            let Item::Ins(rd) = &items[r] else { continue };
            let reads_w = parse(rd).is_some_and(|(mn, o)| mn == "movf" && o.len() >= 2 && o[0] == sym && matches!(o[1], "w" | "0"));
            if !reads_w || r < m || keep[r] || flags_live_in_routine(items, r, Z | N) {
                continue;
            }
            // Every instruction between keeps W, and the only ways in are from inside.
            let mut labels: Vec<&str> = Vec::new();
            let mut ok = true;
            for it in &items[m + 1..r] {
                match it {
                    Item::Comment(_) | Item::Fence => {}
                    Item::Label(l) => labels.push(l),
                    Item::Ins(t) => ok &= keeps_w(t),
                    Item::Br(..) => {}
                    _ => ok = false,
                }
            }
            if !ok {
                continue;
            }
            for (k, it) in items.iter().enumerate() {
                match it {
                    Item::Br(_, t) | Item::Call(t) if labels.contains(&t.as_str()) && !(m < k && k < r) => ok = false,
                    Item::Ins(t) | Item::Raw(t) if labels.iter().any(|l| t.split(|ch: char| !(ch.is_ascii_alphanumeric() || ch == '_')).any(|tok| tok == *l)) => ok = false,
                    _ => {}
                }
            }
            // Branches inside the stretch may only go to labels inside it (or to `r` itself).
            for it in &items[m + 1..r] {
                if let Item::Br(_, t) = it
                    && !labels.contains(&t.as_str())
                {
                    ok = false;
                }
            }
            if !ok {
                continue;
            }
            gone.push(r);
        } else if !others.is_empty() {
            continue;
        }
        gone.push(c);
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !gone.contains(&(k - 1))
        });
        return true;
    }
    false
}

/// Replaces a read of a scratch register by a read of the byte it was just copied from.
fn pass_forward(items: &mut [Item], env: &Env) -> bool {
    let mut changed = false;
    let keep = protected(items);
    for j in 0..items.len() {
        if keep[j] {
            continue;
        }
        let Item::Ins(t) = &items[j] else { continue };
        let Some((mn, ops)) = parse(t) else { continue };
        // The forms that only read a file register: (operand to replace, needs the access bit).
        let (idx, needs_access) = match mn.as_str() {
            "movff" if ops.len() == 2 => (0, false),
            "movf" | "addwf" | "addwfc" | "subwf" | "subwfb" | "subfwb" | "andwf" | "iorwf" | "xorwf" if ops.len() == 3 && dest(ops[1]).is_some_and(|d| matches!(d, Dest::W)) && ops[2].eq_ignore_ascii_case("c") => (0, true),
            _ => continue,
        };
        let Some(Loc::S(r)) = loc(ops[idx]) else { continue };
        // Find the `movff s, __R` that supplied it.
        let mut src: Option<String> = None;
        let mut k = j;
        'back: while k > 0 {
            k -= 1;
            match &items[k] {
                Item::Comment(_) => {}
                Item::Ins(u) => {
                    let Some(e) = effect(u) else { break };
                    if keep[k] {
                        break;
                    }
                    if e.writes.contains(&Loc::S(r)) {
                        if let Some((m, o)) = parse(u)
                            && m == "movff"
                            && o.len() == 2
                            && loc(o[1]) == Some(Loc::S(r))
                            && match loc(o[0]) {
                                // Another scratch register is in the Access Bank and tracked.
                                Some(Loc::S(q)) => q != r,
                                Some(Loc::W) => false,
                                None => env.is_plain(o[0]) && (!needs_access || env.is_access(o[0])),
                            }
                        {
                            // The source must not change between the copy and the read.
                            let s = o[0].to_string();
                            let sloc = loc(&s);
                            let clobbered = items[k + 1..j].iter().any(|it| match it {
                                Item::Ins(v) => effect(v).is_none_or(|ev| sloc.is_some_and(|l| ev.writes.contains(&l)) || ev.wmem.iter().any(|m| matches!(m, Mem::Unknown) || *m == Mem::Sym(s.clone()))),
                                Item::Comment(_) => false,
                                _ => true,
                            });
                            if !clobbered {
                                src = Some(s);
                            }
                        }
                        break 'back;
                    }
                }
                _ => break,
            }
        }
        let Some(s) = src else { continue };
        let mut new_ops: Vec<String> = ops.iter().map(|o| o.to_string()).collect();
        new_ops[idx] = s;
        items[j] = Item::Ins(format!("{mn} {}", new_ops.join(", ")));
        changed = true;
    }
    changed
}

/// Result forwarding, the other direction: `movff P, __R` followed (with nothing else touching `__R`) by
/// `movff __R, v` writes `v` from `P` directly, when `__R` is not read again. The write of `v` moves up past the
/// instructions in between, which is only done when none of them reads or writes `v`; an indirect access cannot
/// reach a compiler-placed variable by another name, so it does not count as one.
fn pass_retarget(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let mut dead = vec![false; items.len()];
    for j in 0..items.len() {
        if keep[j] || dead[j] {
            continue;
        }
        let Item::Ins(t) = &items[j] else { continue };
        let Some((mn, ops)) = parse(t) else { continue };
        if mn != "movff" || ops.len() != 2 {
            continue;
        }
        let Some(Loc::S(r)) = loc(ops[0]) else { continue };
        if loc(ops[1]).is_some() || is_indirect(ops[1]) || !env.is_plain(ops[1]) {
            continue;
        }
        let dst = ops[1].to_string();
        let Some(da) = env.addr(&dst) else { continue };
        let same = |m: &str| env.addr(m).is_none_or(|a| a == da) && !is_indirect(m);
        let mut producer = None;
        let mut k = j;
        while k > 0 {
            k -= 1;
            if dead[k] {
                continue;
            }
            match &items[k] {
                Item::Comment(_) => {}
                Item::Ins(u) => {
                    let Some(e) = effect(u) else { break };
                    if keep[k] || e.reads.contains(&Loc::S(r)) {
                        break;
                    }
                    if e.writes.contains(&Loc::S(r)) {
                        if let Some((m, o)) = parse(u)
                            && m == "movff"
                            && o.len() == 2
                            && loc(o[1]) == Some(Loc::S(r))
                        {
                            producer = Some(k);
                        }
                        break;
                    }
                    let touches = e.rmem.iter().any(|m| same(m)) || e.wmem.iter().any(|m| match m {
                        Mem::Unknown => false,
                        Mem::Sym(m) => same(m),
                    });
                    if touches {
                        break;
                    }
                }
                _ => break,
            }
        }
        let Some(k) = producer else { continue };
        if matches!(loc_live(items, j, Loc::S(r), env), Live::Live) {
            continue;
        }
        let Item::Ins(u) = &items[k] else { continue };
        let (_, o) = parse(u).unwrap();
        items[k] = Item::Ins(format!("movff {}, {}", o[0], dst));
        dead[j] = true;
    }
    let changed = dead.iter().any(|&d| d);
    if changed {
        let mut k = 0;
        items.retain(|_| {
            k += 1;
            !dead[k - 1]
        });
    }
    changed
}

fn is_skip(t: &str) -> bool {
    matches!(parse(t), Some((m, _)) if matches!(m.as_str(), "btfsc" | "btfss" | "decfsz" | "dcfsnz" | "incfsz" | "infsnz" | "tstfsz" | "cpfseq" | "cpfsgt" | "cpfslt"))
}

/// The items no pass may delete, rewrite or rely on: those inside `Keep` regions, and the item
/// right after a skip instruction (it runs only on one path).
fn protected(items: &[Item]) -> Vec<bool> {
    let mut inside = false;
    let mut after_skip = false;
    items
        .iter()
        .map(|it| match it {
            Item::Keep(on) => {
                inside = *on;
                after_skip = false;
                true
            }
            Item::Comment(_) => inside,
            _ => {
                let r = inside || after_skip;
                after_skip = matches!(it, Item::Ins(t) if is_skip(t));
                r
            }
        })
        .collect()
}

/// Runs the pass to a fixed point.
/// The width in bytes of a divide helper called as `__divN` / `__sdivN`.
fn div_helper_width(name: &str) -> Option<u8> {
    let r = name.strip_prefix("__")?;
    let d = r.strip_prefix("sdiv").or_else(|| r.strip_prefix("divk")).or_else(|| r.strip_prefix("div"))?;
    d.parse::<u8>().ok().filter(|n| (1..=4).contains(n))
}

/// The run of instructions right before the call at `c` that load the operands `__A`/`__B` (and nothing else), as
/// `(index of first item, the instructions)`. `None` when the run does not set every operand byte, reads a scratch
/// register or `WREG` before writing it, touches memory it does not own, or reads anything that is not a plain variable.
fn div_prep(items: &[Item], c: usize, n: u8, bn: u8, env: &Env) -> Option<(usize, Vec<String>, Vec<String>)> {
    let mut start = c;
    let mut j = c;
    while j > 0 {
        j -= 1;
        match &items[j] {
            Item::Comment(_) => {}
            Item::Ins(t) => {
                let e = effect(t)?;
                let ok = e.wmem.is_empty()
                    && e.writes.iter().all(|l| matches!(l, Loc::W) || matches!(l, Loc::S(i) if *i < 8))
                    && e.rmem.iter().all(|m| env.is_plain(m));
                if !ok {
                    break;
                }
                start = j;
            }
            _ => break,
        }
    }
    let mut text = Vec::new();
    let mut reads = Vec::new();
    let mut set = [false; 8];
    let mut w_set = false;
    for it in &items[start..c] {
        let Item::Ins(t) = it else { continue };
        let e = effect(t)?;
        if e.reads.iter().any(|l| matches!(l, Loc::S(_))) || (e.reads.contains(&Loc::W) && !w_set) {
            return None;
        }
        for l in &e.writes {
            match l {
                Loc::W => w_set = true,
                Loc::S(i) => set[*i as usize] = true,
            }
        }
        reads.extend(e.rmem);
        text.push(t.clone());
    }
    let (n, bn) = (n as usize, bn as usize);
    ((0..n).all(|i| set[i]) && (0..bn).all(|i| set[4 + i])).then_some((start, text, reads))
}

/// `q = x / y` followed by `r = x Mod y` (or the other way round) on the same operands: the helper leaves the
/// quotient in `__A` and the remainder in `__C`, so the second call and its copies of the operands are dropped.
/// Only between two calls with the same helper, the same operand loading, and nothing in between but stores of the
/// result into variables the operands do not live in (none of them touching a scratch register, so the first
/// result is still in `__A` and `__C`). A `Mod` first copies `__C` over `__A` and so ends the chain.
fn pass_div_share(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let calls: Vec<usize> = (0..items.len()).filter(|&i| matches!(&items[i], Item::Call(n) if div_helper_width(n).is_some())).collect();
    let mut dead = vec![false; items.len()];
    for w in calls.windows(2) {
        let (c1, c2) = (w[0], w[1]);
        let (Item::Call(n1), Item::Call(n2)) = (&items[c1], &items[c2]) else { continue };
        if n1 != n2 || keep[c1..=c2].iter().any(|&k| k) {
            continue;
        }
        let n = div_helper_width(n1).unwrap_or(0);
        // `__divk4` takes a one-byte divisor in `__B0`.
        let bn = if n1.starts_with("__divk") { 1 } else { n };
        let (Some((_, t1, _)), Some((s2, t2, r2))) = (div_prep(items, c1, n, bn, env), div_prep(items, c2, n, bn, env)) else { continue };
        if t1 != t2 || s2 <= c1 {
            continue;
        }
        let bases: Vec<&str> = r2.iter().filter_map(|m| split_off(m).map(|(b, _)| b)).collect();
        let clean = items[c1 + 1..s2].iter().all(|it| match it {
            Item::Comment(_) | Item::Fence => true,
            Item::Ins(t) => effect(t).is_some_and(|e| {
                !e.writes.iter().any(|l| matches!(l, Loc::S(_)))
                    && e.wmem.iter().all(|m| matches!(m, Mem::Sym(s) if split_off(s).is_some_and(|(b, _)| !bases.contains(&b))))
            }),
            _ => false,
        });
        if !clean {
            continue;
        }
        for d in dead.iter_mut().take(c2 + 1).skip(s2) {
            *d = true;
        }
    }
    if !dead.iter().any(|&d| d) {
        return false;
    }
    let mut i = 0;
    items.retain(|_| {
        i += 1;
        !dead[i - 1]
    });
    true
}

fn kind(t: &str) -> Option<&str> {
    t.trim_start().split_whitespace().next()
}

/// For an image that ends below 64 KB every code or table address has a zero upper byte, so setting `TBLPTRU` (or a
/// pointer's third byte) from `highword(sym)` is a clear, and the carry into it after an indexed table address
/// cannot happen. `movlw highword(S); movwf X; movlw 0; addwfc X, f` becomes `clrf X` and `movlw highword(S);
/// movwf X` becomes `clrf X`. The clear stays, because a flash write elsewhere may have left `TBLPTRU` non-zero.
/// `clrf` sets Z and leaves W alone, so the rewrite needs the next instruction to be one that neither reads Z nor
/// W (`W` held `highword`, which is zero, but nothing may count on it).
pub fn narrow_highword(items: Vec<Item>) -> Vec<Item> {
    let neutral = |it: Option<&Item>| match it {
        Some(Item::Ins(t)) => {
            let t = t.trim_start().to_ascii_lowercase();
            let m = t.split_whitespace().next().unwrap_or("");
            m == "tblrd*+" || m == "clrf" || m == "movlw" || m == "movff" || (m == "movf" && t.contains(", w"))
        }
        _ => false,
    };
    let mut out: Vec<Item> = Vec::with_capacity(items.len());
    let mut i = 0;
    while i < items.len() {
        if let Item::Ins(a) = &items[i]
            && kind(a) == Some("movlw")
            && a.contains("highword(")
            && let Some(Item::Ins(b)) = items.get(i + 1)
            && kind(b) == Some("movwf")
        {
            let x = b.trim_start()["movwf".len()..].trim().to_string(); // "X, c"
            let name = x.split(',').next().unwrap_or("").trim().to_string();
            let carry = matches!((items.get(i + 2), items.get(i + 3)), (Some(Item::Ins(c)), Some(Item::Ins(d)))
                if c.trim() == "movlw 0" && d.trim().replace("  ", " ") == format!("addwfc {name}, f, c"));
            let n = if carry { 4 } else { 2 };
            if neutral(items.get(i + n)) {
                out.push(Item::Ins(format!("clrf {x}")));
                i += n;
                continue;
            }
        }
        out.push(items[i].clone());
        i += 1;
    }
    out
}

pub fn optimise(mut items: Vec<Item>, env: &Env) -> Vec<Item> {
    let mut prologues = true;
    for _ in 0..12 {
        let mut changed = false;
        changed |= pass_div_share(&mut items, env);
        changed |= pass_unused_labels(&mut items);
        changed |= pass_tail_call(&mut items);
        changed |= pass_unreachable(&mut items);
        changed |= pass_halt_loop(&mut items);
        changed |= pass_hoist_movlb(&mut items);
        changed |= pass_redundant_movlb(&mut items);
        changed |= pass_redundant_movlb_flow(&mut items);
        changed |= pass_load_reuse(&mut items, env);
        changed |= pass_redundant_lfsr(&mut items);
        changed |= pass_copy_back(&mut items, env);
        changed |= pass_overwritten_store(&mut items, env);
        changed |= pass_stage_store(&mut items, env);
        changed |= pass_sum_share(&mut items, env);
        changed |= pass_known_sfr_bits(&mut items, env);
        changed |= pass_warg(&mut items);
        changed |= pass_bit_branch(&mut items);
        changed |= pass_bool_thread(&mut items, env);
        changed |= pass_jump_thread(&mut items);
        changed |= pass_skip_over_branch(&mut items);
        changed |= pass_branch_to_next(&mut items);
        changed |= pass_branch_over_branch(&mut items);
        changed |= pass_xorlw_zero(&mut items);
        changed |= pass_xor_chain(&mut items, env);
        changed |= pass_repeat_test(&mut items, env);
        changed |= pass_incdec_test(&mut items);
        changed |= pass_incdec_w(&mut items, env);
        changed |= pass_forward(&mut items, env);
        changed |= pass_zero_load(&mut items);
        changed |= pass_retarget(&mut items, env);
        changed |= pass_wreg(&mut items, env);
        changed |= pass_dead_stores(&mut items, env);
        if !env.keep_writes {
            changed |= pass_write_only(&mut items, env);
        }
        if !changed {
            if !prologues {
                break;
            }
            prologues = false;
            // Once everything else has settled: one bank selection per routine.
            if !pass_bank_prologue(&mut items) {
                break;
            }
        }
    }
    // Last of all: the dead-store passes above take `WREG` to be dead at a `return`, so they must not run
    // after this one, which makes the result in `WREG` something callers depend on.
    pass_w_return(&mut items, env);
    items.retain(|it| !matches!(it, Item::Comment(t) if t == "warg"));
    items
}

/// [`optimise`] for the enhanced mid-range core: the passes that do not depend on PIC18 instructions. The bank
/// clean-up has its own pass (`codegen16::opt`), and there is no `movff` to forward or argument in WREG.
pub fn optimise16(mut items: Vec<Item>, env: &Env) -> Vec<Item> {
    // Cleared on the way out even if a pass panics.
    struct Reset;
    impl Drop for Reset {
        fn drop(&mut self) {
            CORE16.with(|c| c.set(false));
        }
    }
    CORE16.with(|c| c.set(true));
    let _reset = Reset;
    for _ in 0..8 {
        let mut changed = false;
        changed |= pass_unused_labels(&mut items);
        changed |= pass_tail_call(&mut items);
        changed |= pass_unreachable(&mut items);
        changed |= pass_halt_loop(&mut items);
        changed |= pass_branch_to_next(&mut items);
        changed |= pass_skipbr_over_branch(&mut items);
        changed |= pass_branch_over_branch(&mut items);
        changed |= pass_xorlw_zero(&mut items);
        changed |= pass_repeat_test(&mut items, env);
        changed |= pass_copy_back16(&mut items, env);
        changed |= pass_forward16(&mut items, env);
        changed |= pass_dead_temp_stores(&mut items, env);
        changed |= pass_retarget16(&mut items, env);
        changed |= pass_wreg(&mut items, env);
        changed |= pass_dead_stores(&mut items, env);
        if !env.keep_writes {
            changed |= pass_write_only(&mut items, env);
        }
        if !changed {
            break;
        }
    }
    items
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::asm::Cc;

    fn env() -> Env {
        let mut plain = HashMap::new();
        plain.insert("__A0".to_string(), (0x00, 4));
        plain.insert("__B0".to_string(), (0x04, 4));
        plain.insert("__C0".to_string(), (0x08, 4));
        plain.insert("__D0".to_string(), (0x0C, 4));
        plain.insert("X".to_string(), (0x10, 2));
        plain.insert("Y".to_string(), (0x12, 2));
        Env { plain, access: (0x00, 0x60), access_sfr: (0x60, 0x100), keep_writes: false, reg_calls: vec!["REG".into()], byte_results: vec![], shared: Default::default() }
    }

    fn ins(t: &str) -> Item {
        Item::Ins(t.to_string())
    }

    /// Runs with some other code reading every test variable, so stores to them stay.
    fn run(src: &[Item]) -> Vec<String> {
        let mut all = vec![Item::Raw("lfsr 0, X+Y+R".into())];
        all.extend_from_slice(src);
        run_alone(&all).split_off(1)
    }

    fn run_alone(src: &[Item]) -> Vec<String> {
        optimise(src.to_vec(), &env())
            .iter()
            .map(|i| match i {
                Item::Ins(t) => t.clone(),
                Item::Label(l) => format!("{l}:"),
                Item::Br(cc, l) => format!("br{cc:?} {l}"),
                Item::Fence => "--".into(),
                _ => "?".into(),
            })
            .collect()
    }

    #[test]
    fn sum_still_in_scratch_is_not_built_again() {
        let mut v = Vec::new();
        let sum = |v: &mut Vec<Item>| {
            for k in 0..4 {
                v.push(ins(&format!("movff X+{k}, __A{k}")));
            }
            for k in 0..4 {
                v.push(ins(&format!("movf Y+{k}, w, c")));
                v.push(ins(&format!("{} __A{k}, f, c", if k == 0 { "addwf" } else { "addwfc" })));
            }
        };
        sum(&mut v);
        v.push(ins("movf __A0, w, c"));
        v.push(ins("subwf __D0, f, c"));
        v.push(Item::Br(Cc::Nc, "L1".into()));
        sum(&mut v);
        v.push(ins("movf __A0, w, c"));
        v.push(ins("subwf X, f, c"));
        let out = run(&v);
        assert_eq!(out.iter().filter(|l| l.starts_with("movff X")).count(), 4);
        // A write to an operand in between keeps the second sum.
        let mut w = Vec::new();
        sum(&mut w);
        w.push(ins("incf X, f, c"));
        sum(&mut w);
        w.push(ins("movf __A0, w, c"));
        w.push(ins("subwf X, f, c"));
        assert_eq!(run(&w).iter().filter(|l| l.starts_with("movff X")).count(), 8);
    }

    #[test]
    fn branch_to_next_is_removed() {
        let r = run(&[Item::Br(Cc::Always, "L".into()), Item::Label("L".into())]);
        assert_eq!(r, vec!["L:"]);
        let r = run(&[Item::Br(Cc::Z, "L".into()), ins("nop"), Item::Label("L".into())]);
        assert_eq!(r.len(), 3);
    }

    #[test]
    fn zero_test_after_logic_is_removed() {
        let r = run(&[ins("andlw 0x80"), ins("xorlw 0x00"), Item::Br(Cc::Z, "L".into())]);
        assert_eq!(r, vec!["andlw 0x80", "brZ L"]);
        // `movlw` sets no flags, so the test stays.
        let r = run(&[ins("movlw 0x80"), ins("xorlw 0x00"), Item::Br(Cc::Z, "L".into())]);
        assert_eq!(r.len(), 3);
    }

    #[test]
    fn dead_scratch_store_before_overwrite() {
        let r = run(&[ins("movff __C0, __A0"), ins("movff __A1, __A0"), Item::Fence]);
        assert_eq!(r, vec!["--"]);
        // Read in between keeps it.
        let r = run(&[ins("movff X, __A0"), ins("movwf __A0, c"), ins("movff __A0, Y"), Item::Fence]);
        assert_eq!(r.len(), 3, "{r:?}");
    }

    #[test]
    fn reload_after_a_conditional_branch_and_the_write_only_copy_go() {
        let r = run_alone(&[
            ins("movf TABLAT, w, c"),
            ins("movwf X, c"),
            Item::Br(Cc::Z, "L".into()),
            ins("movf X, w, c"),
            Item::Call("f".into()),
            Item::Label("L".into()),
        ]);
        assert_eq!(r.len(), 4, "{r:?}");
    }

    #[test]
    fn a_read_of_another_byte_keeps_the_store() {
        let r = run_alone(&[ins("movwf X+1, c"), ins("movf X, w, c"), ins("addwf Y, f, c")]);
        assert_eq!(r.len(), 3, "{r:?}");
    }

    #[test]
    fn stores_to_user_variables_are_kept() {
        let r = run(&[ins("movff __A0, X"), Item::Fence]);
        assert_eq!(r.len(), 2);
        let r = run(&[ins("movwf X, c"), Item::Fence]);
        assert_eq!(r.len(), 2);
    }

    #[test]
    fn scratch_is_live_across_labels_and_calls() {
        let r = run(&[ins("movff X, __A0"), Item::Label("L".into()), ins("movff __A0, Y")]);
        assert_eq!(r.len(), 3);
        let r = run(&[ins("movff X, __A0"), Item::Call("__mul2".into()), Item::Fence]);
        assert_eq!(r.len(), 3);
        // A routine reads its parameters from memory, so the scratch copy is dead.
        let r = run(&[ins("movff X, __A0"), Item::Call("f".into()), Item::Fence]);
        assert_eq!(r.len(), 2);
        // A register-call routine reads `__A` and `__B`.
        let r = run(&[ins("movff X, __A0"), Item::Call("REG".into()), Item::Fence]);
        assert_eq!(r.len(), 3);
    }

    #[test]
    fn copy_is_forwarded_and_the_copy_dies() {
        let r = run(&[ins("movff X, __A0"), ins("movf __A0, w, c"), ins("movwf Y, c"), Item::Fence]);
        assert_eq!(r, vec!["movf X, w, c", "movwf Y, c", "--"]);
        // The source changes in between: no forwarding.
        let r = run(&[ins("movff X, __A0"), ins("clrf X, c"), ins("movf __A0, w, c"), ins("movwf Y, c"), Item::Fence]);
        assert!(r.contains(&"movf __A0, w, c".to_string()), "{r:?}");
    }

    #[test]
    fn forwarded_scratch_in_a_wide_copy() {
        let r = run(&[ins("movff X, __A0"), ins("movff X+1, __A0+1"), ins("movf __A0, w, c"), ins("addwf __A1, w, c"), ins("movwf Y, c"), Item::Fence]);
        assert_eq!(r, vec!["movf X, w, c", "addwf X+1, w, c", "movwf Y, c", "--"]);
    }

    #[test]
    fn redundant_wreg_loads() {
        let r = run(&[ins("movlw 0x01"), ins("addwf X, f, c"), ins("movlw 0x01"), ins("addwf Y, f, c")]);
        assert_eq!(r, vec!["movlw 0x01", "addwf X, f, c", "addwf Y, f, c"]);
        // A label forgets W.
        let r = run(&[ins("movlw 0x01"), Item::Label("L".into()), ins("movlw 0x01"), ins("addwf Y, f, c")]);
        assert_eq!(r.len(), 4);
        // Writing W in between forgets it.
        let r = run(&[ins("movlw 0x01"), ins("addlw 3"), ins("movlw 0x01"), ins("addwf Y, f, c")]);
        assert_eq!(r.len(), 4);
    }

    #[test]
    fn reload_after_store_needs_dead_flags() {
        // movwf X ; movf X,w : the reload goes when nothing reads Z/N afterwards.
        let r = run(&[ins("movwf X, c"), ins("movf X, w, c"), ins("addwf Y, f, c"), ins("movff X, Y")]);
        assert_eq!(r, vec!["movwf X, c", "addwf Y, f, c", "movff X, Y"]);
        // A branch on Z after it needs the flags of the reload.
        let r = run(&[ins("movwf X, c"), ins("movf X, w, c"), Item::Br(Cc::Z, "L".into())]);
        assert_eq!(r.len(), 3);
    }

    #[test]
    fn indirect_write_forgets_memory_copy() {
        let r = run(&[ins("movwf X, c"), ins("movwf POSTINC0, c"), ins("movf X, w, c"), ins("addwf Y, f, c")]);
        assert_eq!(r.len(), 4);
    }

    #[test]
    fn plusw_access_reads_w() {
        let r = run(&[ins("lfsr 0, A"), ins("movf K, w, c"), ins("movf PLUSW0, w, c"), ins("movwf Y, c")]);
        assert_eq!(r.len(), 4);
        let r = run(&[ins("lfsr 0, A"), ins("movf K, w, c"), ins("movff Y, PLUSW0")]);
        assert_eq!(r.len(), 3);
    }

    #[test]
    fn highword_set_becomes_a_clear() {
        let r = narrow_highword(vec![ins("movlw highword(S)"), ins("movwf TBLPTRU, c"), ins("movlw 0"), ins("addwfc TBLPTRU, f, c"), ins("tblrd*+")]);
        assert_eq!(r.len(), 2, "{r:?}");
        let r = narrow_highword(vec![ins("movlw highword(S)"), ins("movwf __A2, c"), ins("clrf __A3, c")]);
        assert!(matches!(&r[0], Item::Ins(t) if t == "clrf __A2, c") && r.len() == 2, "{r:?}");
        // the next instruction reads W or a flag: left alone
        let r = narrow_highword(vec![ins("movlw highword(S)"), ins("movwf __A2, c"), ins("movwf __A3, c")]);
        assert_eq!(r.len(), 3);
        let r = narrow_highword(vec![ins("movlw highword(S)"), ins("movwf __A2, c"), Item::Br(Cc::Z, "_L9".into())]);
        assert_eq!(r.len(), 3);
    }

    #[test]
    fn second_lfsr_of_the_same_array_goes() {
        let r = run(&[ins("lfsr 0, A"), ins("movf K, w, c"), ins("movf PLUSW0, w, c"), ins("movwf Y, c"), ins("lfsr 0, A"), ins("movf K, w, c"), ins("movff Y, PLUSW0")]);
        assert_eq!(r.iter().filter(|t| t.starts_with("lfsr")).count(), 1);
        // an auto-increment, a different array, or a label forgets the pointer
        let r = run(&[ins("lfsr 0, A"), ins("movf Y, w, c"), ins("movwf POSTINC0, c"), ins("lfsr 0, A"), ins("movf Y, w, c"), ins("movwf INDF0, c")]);
        assert_eq!(r.iter().filter(|t| t.starts_with("lfsr")).count(), 2);
        let r = run(&[ins("lfsr 0, A"), ins("lfsr 0, B"), ins("lfsr 0, A")]);
        assert_eq!(r.iter().filter(|t| t.starts_with("lfsr")).count(), 3);
        let r = run(&[ins("movf Y, w, c"), Item::Br(Cc::Z, "_L9".into()), ins("lfsr 0, A"), Item::Label("_L9".into()), ins("lfsr 0, A")]);
        assert_eq!(r.iter().filter(|t| t.starts_with("lfsr")).count(), 2);
    }

    #[test]
    fn reload_of_a_scratch_byte_just_stored_from_w_goes() {
        let r = run(&[ins("lfsr 0, A"), ins("movf K, w, c"), ins("movf PLUSW0, w, c"), ins("movwf __A0, c"), ins("movf __A0, w, c"), ins("xorwf Y, f, c")]);
        assert!(!r.contains(&"movf __A0, w, c".to_string()), "{r:?}");
        // flags read afterwards, W changed, or the scratch byte rewritten: the reload stays
        let r = run(&[ins("movf Y, w, c"), ins("movwf __A0, c"), ins("movf __A0, w, c"), Item::Br(Cc::Z, "_L9".into()), Item::Label("_L9".into()), ins("movwf X, c")]);
        assert!(r.contains(&"movf __A0, w, c".to_string()), "{r:?}");
        let r = run(&[ins("movf Y, w, c"), ins("movwf __A0, c"), ins("movlw 0x05"), ins("addwf X, f, c"), ins("movf __A0, w, c"), ins("xorwf Y, f, c"), ins("movwf X, c")]);
        assert!(r.contains(&"movf __A0, w, c".to_string()), "{r:?}");
        let r = run(&[ins("movf Y, w, c"), ins("movwf __A0, c"), ins("incf __A0, f, c"), ins("movf __A0, w, c"), ins("xorwf Y, f, c"), ins("movwf X, c")]);
        assert!(r.contains(&"movf __A0, w, c".to_string()), "{r:?}");
    }

    #[test]
    fn copy_back_after_a_store_goes() {
        let r = run(&[ins("movff __A0, X"), ins("movff __A1, X+1"), ins("movff X, __A0"), ins("movff X+1, __A1"), ins("addwf Y, f, c")]);
        assert_eq!(r.iter().filter(|t| t.starts_with("movff")).count(), 2, "{r:?}");
        // either byte written in between, or a label: the copy stays
        let r = run(&[ins("movff __A0, X"), ins("incf __A0, f, c"), ins("movff X, __A0"), ins("movf __A0, w, c"), ins("movwf Y, c")]);
        assert!(r.iter().any(|t| t == "movff X, __A0" || t == "movf X, w, c"), "{r:?}");
        let r = run(&[ins("movff __A0, X"), ins("incf X, f, c"), ins("movff X, __A0"), ins("movf __A0, w, c"), ins("movwf Y, c")]);
        assert!(r.iter().any(|t| t == "movff X, __A0" || t == "movf X, w, c"), "{r:?}");
        let r = run(&[ins("movff __A0, X"), ins("movwf POSTINC0, c"), ins("movff X, __A0"), ins("movf __A0, w, c"), ins("movwf Y, c")]);
        assert!(r.iter().any(|t| t == "movff X, __A0" || t == "movf X, w, c"), "{r:?}");
        let r = run(&[ins("movff __A0, X"), Item::Br(Cc::Z, "_L9".into()), Item::Label("_L9".into()), ins("movff X, __A0"), ins("movf __A0, w, c"), ins("movwf Y, c")]);
        assert!(r.iter().any(|t| t == "movff X, __A0" || t == "movf X, w, c"), "{r:?}");
    }

    #[test]
    fn copy_back_into_scratch_is_not_trusted_past_a_statement_end() {
        let r = run(&[ins("movff __A0, X"), Item::Fence, ins("movff X, __A0"), ins("movf __A0, w, c"), ins("movwf Y, c")]);
        assert!(r.iter().any(|t| t == "movff X, __A0" || t == "movf X, w, c"), "{r:?}");
    }

    fn load(add: &str, h: &str) -> Vec<Item> {
        let mut v = vec![ins("movf X, w, c")];
        if !add.is_empty() {
            v.push(ins(&format!("addlw {add}")));
        }
        v.extend([ins("lfsr 0, A"), ins("movf PLUSW0, w, c"), ins(&format!("movwf {h}, c"))]);
        v
    }

    fn reads(r: &[String]) -> usize {
        r.iter().filter(|t| t.starts_with("movf PLUSW0")).count()
    }

    #[test]
    fn element_already_in_a_temp_is_not_loaded_again() {
        let mut s = load("", "Y");
        s.extend(load("", "Y+1"));
        assert_eq!(reads(&run(&s)), 1);
        let mut s = load("0x01", "Y");
        s.extend(load("0x01", "Y+1"));
        s.push(ins("subwf Y, w, c"));
        assert_eq!(reads(&run(&s)), 1);
        // a different offset is a different element
        let mut s = load("", "Y");
        s.extend(load("0x01", "Y+1"));
        assert_eq!(reads(&run(&s)), 2);
        // holder, index or array written in between: loaded again
        for mid in [vec![ins("movwf Y, c")], vec![ins("incf X, f, c")], vec![ins("movlw 1"), ins("movff Y+1, PLUSW0")], vec![ins("lfsr 0, A"), ins("movwf POSTINC0, c")]] {
            let mut s = load("", "Y");
            s.extend(mid);
            s.extend(load("", "Y+1"));
            assert_eq!(reads(&run(&s)), 2, "{s:?}");
        }
        // a label between
        let mut s = vec![ins("movf Y, w, c"), Item::Br(Cc::Z, "_L9".into())];
        s.extend(load("", "Y"));
        s.push(Item::Label("_L9".into()));
        s.extend(load("", "Y+1"));
        assert_eq!(reads(&run(&s)), 2);
    }

    #[test]
    fn staged_byte_is_stored_from_its_source() {
        let text = |v: &[Item]| v.iter().filter_map(|i| if let Item::Ins(t) = i { Some(t.clone()) } else { None }).collect::<Vec<_>>();
        let go = |src: Vec<Item>| {
            let mut v = src;
            pass_stage_store(&mut v, &env());
            text(&v)
        };
        // `movf X, w` / `movwf Y`, the index into W, then the store of Y: the store reads X itself.
        let r = go(vec![ins("movf X, w, c"), ins("movwf Y, c"), ins("movf X+1, w, c"), ins("movff Y, PLUSW0"), ins("return")]);
        assert_eq!(r, vec!["movf X+1, w, c", "movff X, PLUSW0", "return"]);
        let r = go(vec![ins("movff X, Y"), ins("movff X+1, Y+1"), ins("movff Y, POSTINC0"), ins("return")]);
        assert_eq!(r, vec!["movff X+1, Y+1", "movff X, POSTINC0", "return"]);
        // Kept: the source is written in between (a scratch byte's writes are tracked apart from other memory), the
        // staged byte is read later, or W is read before it is set again.
        for src in [
            vec![ins("movff __A0, Y"), ins("movff X, __A0"), ins("movff Y, POSTINC0"), ins("return")],
            vec![ins("movff X, Y"), ins("clrf X, c"), ins("movff Y, POSTINC0"), ins("return")],
            vec![ins("movff X, Y"), ins("movff Y, POSTINC0"), ins("movf Y, w, c"), ins("return")],
            vec![ins("movff X, Y"), ins("movff Y, POSTINC0"), Item::Br(Cc::Z, "_L1".into()), ins("return"), Item::Label("_L1".into()), ins("movf Y, w, c"), ins("return")],
            vec![ins("movf X, w, c"), ins("movwf Y, c"), ins("addlw 0x01"), ins("movff Y, PLUSW0"), ins("return")],
        ] {
            let before = text(&src);
            assert_eq!(go(src), before);
        }
    }

    #[test]
    fn skip_and_raw_end_a_run() {
        let r = run(&[ins("movlw 0x01"), ins("btfsc X, 0, c"), ins("movlw 0x01"), ins("addwf Y, f, c")]);
        assert_eq!(r.len(), 4);
        let r = run(&[ins("movlw 0x01"), Item::Raw("movlw 5".into()), ins("movlw 0x01"), ins("addwf Y, f, c")]);
        assert_eq!(r.len(), 4);
    }

    #[test]
    fn the_instruction_after_a_skip_is_left_alone() {
        // Sign extension: the second movlw runs on one path only.
        let r = run(&[ins("movlw 0x00"), ins("btfsc __A0, 7, c"), ins("movlw 0xFF"), ins("addwf Y, f, c"), ins("movlw 0xFF"), ins("addwf Y, f, c")]);
        assert_eq!(r.len(), 6, "{r:?}");
        // A branch to the next instruction after a skip is not redundant.
        let r = run(&[ins("btfss X, 0, c"), Item::Br(Cc::Always, "L".into()), Item::Label("L".into())]);
        assert_eq!(r.len(), 3, "{r:?}");
        // A conditional copy is not a supplier.
        let r = run(&[ins("btfsc X, 0, c"), ins("movff Y, __A0"), ins("movf __A0, w, c"), ins("movwf Y, c"), Item::Fence]);
        assert!(r.contains(&"movf __A0, w, c".to_string()), "{r:?}");
    }

    #[test]
    fn bit_test_compare_becomes_skip_branch() {
        let seq = |x: &str, cc: Cc| {
            vec![ins("movlw 0"), ins("movlb 14"), ins("btfsc R, 4, b"), ins("movlw 1"), ins(x), Item::Br(cc, "L".into()), ins("movlw 0"), ins("movwf X, c"), Item::Label("L".into()), ins("movlw 0"), ins("movwf Y, c"), Item::Fence]
        };
        // Boolean = 0 is "bit clear": branch when W (the bit) is non-zero.
        let r = run(&seq("xorlw 0x00", Cc::Nz));
        assert_eq!(&r[..3], ["movlb 14", "btfsc R, 4, b", "brAlways L"], "{r:?}");
        let r = run(&seq("xorlw 0x00", Cc::Z));
        assert_eq!(&r[..3], ["movlb 14", "btfss R, 4, b", "brAlways L"], "{r:?}");
        let r = run(&seq("xorlw 0x01", Cc::Nz));
        assert_eq!(&r[1], "btfss R, 4, b", "{r:?}");
        // btfss complements the Boolean.
        let mut s = seq("xorlw 0x01", Cc::Z);
        s[2] = ins("btfss R, 4, b");
        let r = run(&s);
        assert_eq!(&r[1], "btfss R, 4, b", "{r:?}");
        // W is read at the target: unchanged.
        let mut s = seq("xorlw 0x00", Cc::Nz);
        s[9] = ins("movwf Y, c");
        // (Then `Y` is read, so the store is not one a later store overwrites.)
        s[10] = ins("addwf Y, f, c");
        assert_eq!(run(&s).len(), s.len(), "{:?}", run(&s));
    }

    #[test]
    fn overwritten_store_is_deleted() {
        // `clrf X` then `movff S, X` in a straight run: the clear goes.
        let r = run(&[ins("clrf X, c"), ins("movff S, X"), Item::Fence]);
        assert_eq!(r, ["movff S, X", "--"], "{r:?}");
        // A read in between, a branch, a skip or an indirect access keeps it.
        let r = run(&[ins("clrf X, c"), ins("movf X, w, c"), ins("movwf Y, c"), ins("movff S, X"), Item::Fence]);
        assert_eq!(r[0], "clrf X, c", "{r:?}");
        let r = run(&[ins("clrf X, c"), Item::Br(Cc::Z, "L".into()), ins("movff S, X"), Item::Label("L".into()), ins("movf X, w, c"), ins("movwf Y, c"), Item::Fence]);
        assert_eq!(r[0], "clrf X, c", "{r:?}");
        let r = run(&[ins("clrf X, c"), ins("btfsc R, 1, c"), ins("movff S, X"), Item::Fence]);
        assert_eq!(r[0], "clrf X, c", "{r:?}");
        let r = run(&[ins("clrf X, c"), ins("movf INDF0, w, c"), ins("movwf Y, c"), ins("movff S, X"), Item::Fence]);
        assert_eq!(r[0], "clrf X, c", "{r:?}");
        // A store that reads a device register or steps an FSR is kept: the read itself matters.
        let r = run(&[ins("movff SSP1BUF, X"), ins("movff SSP1BUF, X"), ins("movf X, w, c"), ins("movwf Y, c"), Item::Fence]);
        assert_eq!(&r[..2], ["movff SSP1BUF, X", "movff SSP1BUF, X"], "{r:?}");
        let r = run(&[ins("movff POSTINC0, X"), ins("movff S, X"), ins("movf X, w, c"), ins("movwf Y, c"), Item::Fence]);
        assert_eq!(r[0], "movff POSTINC0, X", "{r:?}");
        // `X+0+1` is the byte `X+1` spelled another way (an array element's word alias): a read of it keeps the store.
        let r = run(&[ins("movwf X+1, c"), ins("movff X+0+1, Y"), ins("movff S, X+1"), ins("movf Y, w, c"), ins("movwf T, c"), Item::Fence]);
        assert_eq!(r[0], "movwf X+1, c", "{r:?}");
    }

    fn texts(v: &[Item]) -> Vec<String> {
        v.iter()
            .map(|i| match i {
                Item::Ins(t) => t.clone(),
                Item::Label(l) => format!("{l}:"),
                Item::Br(cc, l) => format!("br{cc:?} {l}"),
                Item::Fence => "--".into(),
                _ => "?".into(),
            })
            .collect()
    }

    #[test]
    fn byref_pointer_reload_is_dropped() {
        let pair = || [ins("movff P, FSR0L"), ins("movff P+1, FSR0H")];
        let mut v: Vec<Item> = pair().into_iter().chain([ins("decf INDF0, f, c"), ins("movf P, w, c")]).chain(pair()).chain([ins("movf INDF0, w, c")]).collect();
        pass_redundant_lfsr(&mut v);
        assert_eq!(texts(&v), ["movff P, FSR0L", "movff P+1, FSR0H", "decf INDF0, f, c", "movf P, w, c", "movf INDF0, w, c"]);
        // A write to the pointer (an inlined second call), a label or a call in between keeps the reload.
        for mid in [ins("movwf P+1, c"), ins("movff Y, P"), ins("bcf P, 0, c"), ins("incf P+1, f, c"), Item::Label("L".into()), ins("rcall F")] {
            let mut v: Vec<Item> = pair().into_iter().chain([mid]).chain(pair()).collect();
            pass_redundant_lfsr(&mut v);
            assert_eq!(v.len(), 5, "{:?}", texts(&v));
        }
    }

    #[test]
    fn step_then_test_and_incdec_compares() {
        // `decf X, f` has set Z from X: the `movf X, f` test goes.
        let mut v = vec![ins("decf X, f, c"), ins("movf X, f, c"), Item::Br(Cc::Nz, "L".into())];
        pass_repeat_test(&mut v, &env());
        assert_eq!(texts(&v), ["decf X, f, c", "brNz L"]);
        // W just stored to X: `incf X, w` is `addlw 0x01`.
        let mut v = vec![ins("movwf X, c"), ins("incf X, w, c"), Item::Br(Cc::Z, "L".into())];
        pass_incdec_w(&mut v, &env());
        assert_eq!(texts(&v), ["movwf X, c", "addlw 0x01", "brZ L"]);
        // `movf X, w ; xorlw 1 ; bnz` with W and the carry dead on both paths: `decf X, w`.
        let tail = || vec![ins("movlw 5"), ins("movwf Y, c"), Item::Label("L".into()), ins("movlw 6"), ins("movwf Y, c"), Item::Fence];
        let mut v = vec![ins("movf X, w, c"), ins("xorlw 0x01"), Item::Br(Cc::Nz, "L".into())];
        v.extend(tail());
        pass_incdec_test(&mut v);
        assert_eq!(texts(&v)[..2], ["decf X, w, c", "brNz L"]);
        // A chain of compares that goes on with W (`xorlw` again) keeps the xor.
        let mut v = vec![ins("movf X, w, c"), ins("xorlw 0xFF"), Item::Br(Cc::Z, "L".into()), ins("xorlw 0xFD"), Item::Br(Cc::Z, "L".into())];
        v.extend(tail());
        pass_incdec_test(&mut v);
        assert_eq!(texts(&v)[1], "xorlw 0xFF");
    }

    #[test]
    fn bit_branch_sees_through_a_skip_over_a_branch() {
        // `(a Or b)`: the fall-through starts with another bit test; W and flags are dead on both paths.
        let s = vec![
            ins("movlw 0"), ins("btfsc R, 4, b"), ins("movlw 1"), ins("xorlw 0x00"), Item::Br(Cc::Z, "T".into()),
            ins("btfsc R, 6, b"), Item::Br(Cc::Always, "E".into()),
            Item::Label("T".into()), ins("movlw 0x60"), ins("subwf X, w, c"), Item::Fence, Item::Label("E".into()), Item::Fence,
        ];
        let r = run(&s);
        assert_eq!(&r[..2], ["btfss R, 4, b", "brAlways T"], "{r:?}");
        // W is read after the skip: unchanged.
        let mut s2 = s.clone();
        s2[8] = ins("addwf X, f, c");
        assert_eq!(run(&s2)[0], "movlw 0");
    }

    /// `btfsc Q ; <A=1 / B=0 Boolean> ; movwf X ; movf X,w ; bz T ; <rest>`: the five lines of the Boolean build.
    fn bool_seq(before_t: Vec<Item>, at_t: Vec<Item>) -> Vec<Item> {
        let mut v = vec![
            ins("btfsc Q, 1, b"), Item::Br(Cc::Always, "X1".into()),
            ins("movlw 1"), Item::Br(Cc::Always, "J".into()),
            Item::Label("X1".into()), ins("movlw 0"), Item::Label("J".into()),
            ins("movwf X, c"), Item::Fence, ins("movf X, w, c"), Item::Br(Cc::Z, "T".into()),
        ];
        v.extend(before_t);
        v.push(Item::Label("T".into()));
        v.extend(at_t);
        v
    }

    #[test]
    fn a_boolean_built_and_tested_at_once_is_a_jump_on_each_path() {
        // Nothing reads X, and WREG and the flags are dead at both destinations: no Boolean at all.
        let s = bool_seq(vec![ins("movlw 5"), ins("movwf Y, c")], vec![ins("movlw 6"), ins("movwf Y, c"), Item::Fence]);
        let r = run_alone(&s);
        assert_eq!(&r[..2], ["btfsc Q, 1, b", "brAlways T"], "{r:?}");
        assert!(!r.iter().any(|l| l.contains(" X")), "{r:?}");
    }

    #[test]
    fn a_boolean_that_is_read_elsewhere_keeps_its_store() {
        let s = bool_seq(vec![ins("movlw 5"), ins("movwf Y, c")], vec![ins("movlw 6"), ins("movwf Y, c"), Item::Fence]);
        let r = run(&s);
        // Each path stores its own value and the reload and test are gone.
        assert_eq!(r.iter().filter(|l| *l == "movwf X, c").count(), 2, "{r:?}");
        assert!(!r.iter().any(|l| l == "movf X, w, c"), "{r:?}");
    }

    #[test]
    fn a_boolean_whose_flags_are_read_at_a_destination_is_left_alone() {
        // The code at T branches on Z: the `movf` is what set it.
        let s = bool_seq(vec![ins("movlw 5"), ins("movwf Y, c")], vec![Item::Br(Cc::Z, "T".into()), ins("movlw 6"), Item::Fence]);
        let r = run_alone(&s);
        assert!(r.iter().any(|l| l == "movf X, w, c"), "{r:?}");
    }

    #[test]
    fn a_boolean_whose_wreg_is_read_at_a_destination_keeps_its_value_in_wreg() {
        // The rest of the code adds WREG to Y: the value must still be in WREG, so the loads stay.
        let s = bool_seq(vec![ins("addwf Y, f, c")], vec![ins("movlw 6"), ins("movwf Y, c"), Item::Fence]);
        let r = run_alone(&s);
        assert!(r.iter().any(|l| l == "movlw 1") && r.iter().any(|l| l == "movlw 0"), "{r:?}");
        assert!(!r.iter().any(|l| l == "movf X, w, c"), "{r:?}");
    }


    #[test]
    fn a_boolean_stored_in_one_byte_of_a_wider_object_keeps_its_store() {
        // `X+1` is a byte of X: the name alone does not show whether X is read, so the store stays.
        let mut s = bool_seq(vec![ins("movlw 5"), ins("movwf Y, c")], vec![ins("movlw 6"), ins("movwf Y, c"), Item::Fence]);
        for it in s.iter_mut() {
            if let Item::Ins(t) = it {
                *t = t.replace("movwf X, c", "movwf X+1, c").replace("movf X, w, c", "movf X+1, w, c");
            }
        }
        let r = run_alone(&s);
        assert!(r.iter().any(|l| l == "movwf X+1, c"), "{r:?}");
    }

    #[test]
    fn a_bit_test_that_another_skip_passes_over_is_not_inverted() {
        // `tstfsz Y` skips the `btfsc`; inverting it would change where that skip lands.
        let s = vec![
            ins("tstfsz Y, c"), ins("btfsc Q, 1, b"), Item::Br(Cc::Always, "L1".into()), Item::Br(Cc::Always, "L2".into()), Item::Label("L1".into()),
            ins("movlw 1"), ins("movwf Y, c"), Item::Label("L2".into()), ins("movlw 2"), ins("movwf Y, c"), Item::Fence,
        ];
        let r = run(&s);
        assert!(r.iter().any(|l| l == "btfsc Q, 1, b") && !r.iter().any(|l| l == "btfss Q, 1, b"), "{r:?}");
    }

    #[test]
    fn a_branch_to_a_branch_goes_to_the_final_target() {
        let s = vec![Item::Br(Cc::Z, "A".into()), ins("movlw 1"), ins("movwf Y, c"), Item::Label("A".into()), Item::Br(Cc::Always, "B".into()), ins("nop"), Item::Label("B".into()), ins("movlw 2"), ins("movwf Y, c"), Item::Fence];
        let r = run(&s);
        assert_eq!(r[0], "brZ B", "{r:?}");
    }


    #[test]
    fn a_status_bit_test_at_a_destination_reads_the_flags_the_movf_set() {
        // `btfsc STATUS, 2` is a Z test: the `movf` must stay.
        let s = bool_seq(vec![ins("btfsc STATUS, 2, c"), ins("movlw 5"), ins("movwf Y, c")], vec![ins("movlw 6"), ins("movwf Y, c"), Item::Fence]);
        let r = run_alone(&s);
        assert!(r.iter().any(|l| l == "movf X, w, c"), "{r:?}");
    }

    #[test]
    fn call_before_return_becomes_a_jump() {
        let r = run(&[Item::Call("F".into()), Item::Fence, ins("return")]);
        assert_eq!(r, vec!["brAlways F", "--"]);
        // A label between keeps the return for the other path.
        let r = run(&[Item::Call("F".into()), Item::Label("M".into()), ins("return")]);
        assert_eq!(r, vec!["?", "M:", "return"]);
    }

    #[test]
    fn code_after_a_return_without_a_label_is_dropped() {
        let r = run(&[ins("return"), ins("incf X, f, c"), Item::Label("K".into()), ins("incf Y, f, c")]);
        assert_eq!(r, vec!["return", "K:", "incf Y, f, c"]);
    }

    #[test]
    fn instruction_skipped_by_a_test_is_not_dead_after_a_branch() {
        let r = run(&[ins("btfss X, 0, c"), Item::Br(Cc::Always, "L".into()), ins("incf Y, f, c"), Item::Label("L".into())]);
        assert!(r.contains(&"incf Y, f, c".to_string()));
    }

    #[test]
    fn unnamed_labels_go_and_named_ones_stay() {
        let r = run(&[Item::Label("_L1".into()), Item::Label("F".into()), ins("incf X, f, c")]);
        assert_eq!(r, vec!["F:", "incf X, f, c"]);
    }

    #[test]
    fn bank_select_leaves_a_polling_loop() {
        let r = run(&[Item::Label("_L1".into()), ins("movlb 14"), ins("btfss PIR3, 4, b"), Item::Br(Cc::Always, "_L1".into())]);
        assert_eq!(r, vec!["movlb 14", "_L1:", "btfss PIR3, 4, b", "brAlways _L1"]);
        // A call in the loop may change the bank: it stays.
        let r = run(&[Item::Label("_L1".into()), ins("movlb 14"), Item::Call("F".into()), Item::Br(Cc::Always, "_L1".into())]);
        assert_eq!(r[1], "movlb 14");
    }

    #[test]
    fn test_of_a_value_just_stored_repeats_the_load_flags() {
        let r = run(&[ins("movf TABLAT, w, c"), ins("movwf X, c"), ins("movf X, f, c"), Item::Br(Cc::Nz, "L".into()), Item::Label("L".into())]);
        assert!(!r.iter().any(|t| t == "movf X, f, c"));
    }
    #[test]
    fn conditional_branch_over_a_jump_is_inverted() {
        let r = run(&[Item::Br(Cc::Nz, "A".into()), Item::Br(Cc::Always, "B".into()), Item::Label("A".into()), ins("incf X, f, c")]);
        assert_eq!(r, vec!["brZ B", "A:", "incf X, f, c"]);
    }
    #[test]
    fn second_bank_select_is_dropped() {
        let r = run(&[ins("movlb 15"), ins("clrf ANSELA, b"), ins("movlb 15"), ins("clrf ANSELB, b"), Item::Label("K".into()), ins("movlb 15")]);
        assert_eq!(r, vec!["movlb 15", "clrf ANSELA, b", "clrf ANSELB, b", "K:", "movlb 15"]);
    }
    #[test]
    fn argument_in_w_is_used_in_place() {
        let r = run(&[
            Item::Label("F".into()),
            Item::Comment("warg".into()),
            ins("movwf P, c"),
            Item::Label("_L1".into()),
            ins("btfss PIR3, 4, b"),
            Item::Br(Cc::Always, "_L1".into()),
            ins("movf P, w, c"),
            ins("movwf TX1REG, c"),
            ins("return"),
        ]);
        assert!(!r.iter().any(|t| t.contains("P,")), "{r:?}");
    }

    #[test]
    fn argument_in_w_is_stored_when_w_is_clobbered() {
        let r = run(&[Item::Label("F".into()), Item::Comment("warg".into()), ins("movwf P, c"), ins("movlw 3"), ins("movwf Q, c"), ins("movf P, w, c"), ins("movwf TX1REG, c"), ins("return")]);
        assert!(r.iter().any(|t| t == "movwf P, c"), "{r:?}");
    }

    #[test]
    fn halt_loop_after_an_endless_loop_is_dropped() {
        let ends = |main: Vec<Item>| {
            let mut v = vec![Item::Label("__reset".into())];
            v.extend(main);
            v.push(Item::Label("__halt".into()));
            v.push(Item::Br(Cc::Always, "__halt".into()));
            optimise(v, &env()).iter().any(|i| matches!(i, Item::Br(Cc::Always, t) if t == "__halt"))
        };
        assert!(!ends(vec![Item::Label("_L1".into()), ins("btg LATB, 0, c"), Item::Br(Cc::Always, "_L1".into())]));
        assert!(ends(vec![ins("btg LATB, 0, c")]));
        // A counted loop's `decfsz` / `bra` falls through when the count runs out.
        assert!(ends(vec![Item::Label("_L1".into()), ins("rlcf X, f, c"), ins("decfsz __D0, f, c"), Item::Br(Cc::Always, "_L1".into())]));
    }

    fn run16(src: &[Item]) -> Vec<String> {
        optimise16(src.to_vec(), &env())
            .iter()
            .map(|i| match i {
                Item::Ins(t) => t.clone(),
                Item::Label(l) => format!("{l}:"),
                Item::Br(cc, l) => format!("br{cc:?} {l}"),
                Item::SkipBr(t, l) => format!("{t} -> {l}"),
                Item::Fence => "--".into(),
                _ => "?".into(),
            })
            .collect()
    }

    #[test]
    fn p16_label_used_only_by_a_skip_branch_stays() {
        let r = run16(&[Item::Label("_L1".into()), ins("movwi 0[FSR0]"), Item::SkipBr("decfsz __D0, f".into(), "_L1".into())]);
        assert!(r.contains(&"_L1:".to_string()), "{r:?}");
    }

    #[test]
    fn p16_store_to_a_counted_variable_stays() {
        let mut e = env();
        e.plain.insert("CNT".into(), (0x14, 1));
        let src = [ins("movlw 5"), ins("movwf CNT"), Item::Label("_L1".into()), Item::SkipBr("decfsz CNT, f".into(), "_L1".into())];
        let r = optimise16(src.to_vec(), &e);
        assert!(r.iter().any(|i| matches!(i, Item::Ins(t) if t == "movwf CNT")));
    }

    #[test]
    fn p16_rotate_does_not_set_z() {
        // `rlf` leaves Z alone, so the `movf` before it is not made dead by it.
        let r = run16(&[ins("movf X, w"), ins("rlf Y, f"), Item::Br(Cc::Z, "L".into())]);
        assert!(r.contains(&"movf X, w".to_string()), "{r:?}");
    }
    fn run16_keep(src: &[Item]) -> Vec<String> {
        let mut e = env();
        e.plain.insert("T".into(), (0x20, 2));
        e.keep_writes = true;
        optimise16(src.to_vec(), &e)
            .iter()
            .map(|i| match i {
                Item::Ins(t) => t.clone(),
                Item::Fence => "--".into(),
                _ => "?".into(),
            })
            .collect()
    }

    #[test]
    fn p16_value_built_in_scratch_is_built_in_its_destination() {
        let r = run16_keep(&[ins("movf X, w"), ins("movwf __A0"), ins("movf Y, w"), ins("addwf __A0, f"), ins("movf __A0, w"), ins("movwf T"), Item::Fence]);
        assert!(!r.iter().any(|t| t.contains("__A0")), "{r:?}");
        assert!(r.contains(&"addwf T, f".to_string()) && r.contains(&"movwf T".to_string()), "{r:?}");
    }

    #[test]
    fn p16_retarget_keeps_scratch_when_the_destination_is_read_in_between() {
        // `T = T + X`-shaped: `T` is read after the scratch byte is first written.
        let r = run16_keep(&[ins("movf X, w"), ins("movwf __A0"), ins("movf T, w"), ins("addwf __A0, f"), ins("movf __A0, w"), ins("movwf T"), Item::Fence]);
        assert!(r.iter().any(|t| t.contains("__A0")), "{r:?}");
    }

    #[test]
    fn p16_retarget_leaves_a_variable_an_interrupt_handler_sees() {
        let mut e = env();
        e.plain.insert("T".into(), (0x20, 2));
        e.keep_writes = true;
        e.shared.insert("T".into());
        let src = [ins("movf X, w"), ins("movwf __A0"), ins("movf Y, w"), ins("addwf __A0, f"), ins("movf __A0, w"), ins("movwf T"), Item::Fence];
        let r = optimise16(src.to_vec(), &e);
        assert!(r.iter().any(|i| matches!(i, Item::Ins(t) if t.contains("__A0"))), "{r:?}");
    }

    #[test]
    fn p16_retarget_keeps_scratch_across_a_bank_select() {
        // The destination is in another bank: its stores must stay after the `movlb`.
        let r = run16_keep(&[ins("movf X, w"), ins("movwf __A0"), ins("movf Y, w"), ins("addwf __A0, f"), ins("movf __A0, w"), ins("movlb 2"), ins("movwf T"), Item::Fence]);
        assert!(r.iter().any(|t| t.contains("__A0")), "{r:?}");
        let r = run16_keep(&[ins("movf X, w"), ins("movwf __A0"), ins("movlb 2"), ins("addwf __A0, f"), ins("movf __A0, w"), ins("movwf T"), Item::Fence]);
        assert!(r.iter().any(|t| t.contains("__A0")), "{r:?}");
    }

    #[test]
    fn p16_retarget_keeps_scratch_that_is_read_afterwards() {
        let r = run16_keep(&[ins("movf X, w"), ins("movwf __A0"), ins("movf __A0, w"), ins("movwf T"), ins("movf __A0, w"), ins("movwf T+1")]);
        assert!(r.iter().any(|t| t.contains("__A0")), "{r:?}");
    }

    fn movlbs(r: &[String]) -> usize {
        r.iter().filter(|t| t.starts_with("movlb")).count()
    }

    #[test]
    fn bank_known_across_a_loop_and_a_join() {
        // The polling loop selects the bank once; the code after it needs no second selection.
        let r = run(&[ins("movlb 2"), Item::Label("_L1".into()), ins("btfsc P, 4, b"), Item::Br(Cc::Always, "_L1".into()), ins("movlb 2"), ins("clrf Q, b")]);
        assert_eq!(movlbs(&r), 1, "{r:?}");
        // Both paths into the join have bank 3.
        let r = run(&[ins("movlb 3"), Item::Br(Cc::Z, "_L2".into()), ins("incf Q, f, b"), Item::Label("_L2".into()), ins("movlb 3"), ins("clrf P, b")]);
        assert_eq!(movlbs(&r), 1, "{r:?}");
        // Different banks on the two paths: the selection stays.
        let r = run(&[ins("movlb 3"), Item::Br(Cc::Z, "_L2".into()), ins("movlb 4"), Item::Label("_L2".into()), ins("movlb 3"), ins("clrf P, b")]);
        assert_eq!(movlbs(&r), 3, "{r:?}");
        // A label raw assembly may jump to has an unknown bank.
        let r = run(&[ins("movlb 3"), Item::Label("_L3".into()), ins("movlb 3"), ins("clrf P, b"), Item::Raw("goto _L3".into())]);
        assert_eq!(movlbs(&r), 2, "{r:?}");
    }

    #[test]
    fn bank_after_a_call_is_what_the_callee_leaves() {
        let r = run(&[
            Item::Call("F".into()),
            ins("movlb 2"),
            ins("clrf P, b"),
            ins("return"),
            Item::Label("F".into()),
            ins("movlb 2"),
            ins("clrf Q, b"),
            ins("return"),
        ]);
        // The call leaves bank 2 behind, so the selection after it goes.
        assert_eq!(movlbs(&r), 1, "{r:?}");
        // A callee with two exits in different banks leaves nothing known.
        let r = run(&[
            Item::Call("F".into()),
            ins("movlb 2"),
            ins("clrf P, b"),
            ins("return"),
            Item::Label("F".into()),
            ins("btfsc Q, 0, c"),
            ins("bra _L1"),
            ins("movlb 2"),
            ins("return"),
            Item::Label("_L1".into()),
            ins("movlb 3"),
            ins("return"),
        ]);
        assert_eq!(movlbs(&r), 3, "{r:?}");
    }

    #[test]
    fn bank_prologue_replaces_several_selections() {
        let r = run(&[
            Item::Label("F".into()),
            ins("btfsc Q, 0, c"),
            ins("bra _L1"),
            ins("movlb 2"),
            ins("clrf P, b"),
            ins("return"),
            Item::Label("_L1".into()),
            ins("movlb 2"),
            ins("setf P, b"),
            ins("return"),
        ]);
        assert_eq!(movlbs(&r), 1, "{r:?}");
        assert_eq!(r[1], "movlb 2", "{r:?}");
    }

    #[test]
    fn port_bits_already_at_that_value_are_not_set_again() {
        let r = run(&[ins("clrf ANSELC, b"), ins("bcf ANSELC, 5, b"), ins("bsf TRISC, 5, c"), ins("bcf TRISC, 4, c"), ins("bcf ANSELC, 4, b")]);
        assert_eq!(r, vec!["clrf ANSELC, b", "bsf TRISC, 5, c", "bcf TRISC, 4, c"]);
        // A label can be entered with another value; a bit of the other value is a real change.
        let r = run(&[ins("clrf LATB, b"), Item::Label("_L1".into()), ins("bcf LATB, 1, b"), ins("bsf LATB, 2, b"), ins("bsf LATB, 2, b"), Item::Br(Cc::Z, "_L1".into())]);
        assert_eq!(r.len(), 6, "{r:?}");
        // A compiler variable named like a port register is not one.
        let r = run(&[ins("clrf X, c"), ins("bcf X, 0, c")]);
        assert_eq!(r.len(), 2, "{r:?}");
    }

    fn w_env() -> Env {
        let mut e = env();
        e.plain.insert("FR".to_string(), (0x20, 1));
        e.byte_results = vec![("F".to_string(), "FR".to_string())];
        e
    }

    fn run_w(src: &[Item]) -> Vec<String> {
        let mut all = vec![Item::Raw("lfsr 0, X+Y+R".into())];
        all.extend_from_slice(src);
        optimise(all, &w_env())
            .iter()
            .map(|i| match i {
                Item::Ins(t) => t.clone(),
                Item::Label(l) => format!("{l}:"),
                Item::Br(cc, l) => format!("br{cc:?} {l}"),
                Item::Call(l) => format!("call {l}"),
                Item::Fence => "--".into(),
                _ => "?".into(),
            })
            .skip(1)
            .collect()
    }

    #[test]
    fn result_in_wreg_saves_the_load_after_the_call() {
        let callee = [Item::Label("F".into()), ins("movlw 5"), ins("movwf FR, c"), ins("return")];
        let mut src = vec![Item::Call("F".into()), ins("movf FR, w, c"), ins("movwf Y, c"), Item::Fence, ins("return")];
        src.extend(callee.iter().cloned());
        let r = run_w(&src);
        assert_eq!(&r[..3], ["call F", "movwf Y, c", "--"], "{r:?}");
        // The flags the load set are read by the branch: it stays.
        let mut src = vec![Item::Call("F".into()), ins("movf FR, w, c"), Item::Br(Cc::Z, "_L1".into()), ins("nop"), Item::Label("_L1".into()), Item::Fence, ins("return")];
        src.extend(callee.iter().cloned());
        let r = run_w(&src);
        assert_eq!(&r[..2], ["call F", "movf FR, w, c"], "{r:?}");
    }

    #[test]
    fn result_in_wreg_costs_a_load_at_a_return_without_it() {
        // The value is in FR only; each such return needs `movf FR, w` first, so one call that saves one load does not pay.
        let callee = [Item::Label("F".into()), ins("clrf FR, c"), ins("return")];
        let mut src = vec![Item::Call("F".into()), ins("movf FR, w, c"), ins("movwf Y, c"), Item::Fence, ins("return")];
        src.extend(callee.iter().cloned());
        let r = run_w(&src);
        assert_eq!(&r[..2], ["call F", "movf FR, w, c"], "{r:?}");
        // Two calls do.
        let mut src = vec![Item::Call("F".into()), ins("movf FR, w, c"), ins("movwf Y, c"), ins("incf Y, f, c"), Item::Fence, Item::Call("F".into()), ins("movf FR, w, c"), ins("movwf X, c"), ins("incf X, f, c"), Item::Fence, ins("return")];
        src.extend(callee.iter().cloned());
        let r = run_w(&src);
        assert_eq!(&r[..2], ["call F", "movwf Y, c"], "{r:?}");
        assert!(r.iter().any(|t| t == "movf FR, w, c"), "the return gets the load: {r:?}");
    }

    #[test]
    fn if_chain_on_one_variable_loads_it_once() {
        let r = run(&[
            ins("movf X, w, c"),
            ins("xorlw 0x01"),
            Item::Br(Cc::Nz, "_L1".into()),
            ins("incf Y, f, c"),
            Item::Br(Cc::Always, "_L9".into()),
            Item::Label("_L1".into()),
            ins("movf X, w, c"),
            ins("xorlw 0x02"),
            Item::Br(Cc::Nz, "_L9".into()),
            ins("decf Y, f, c"),
            Item::Label("_L9".into()),
            Item::Fence,
        ]);
        assert!(r.contains(&"xorlw 0x03".to_string()), "{r:?}");
        assert_eq!(r.iter().filter(|t| t.starts_with("movf X")).count(), 1, "{r:?}");
    }

}
