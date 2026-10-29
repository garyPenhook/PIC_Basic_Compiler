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

/// What `WREG` is known to hold.
#[derive(Clone, PartialEq, Debug)]
enum W {
    Unknown,
    Imm(u8),
    /// A copy of this compiler-placed byte.
    Mem(String),
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
                // Redundant load?
                if e.writes == [Loc::W] && e.reads.is_empty() {
                    if let (Some(k), W::Imm(h)) = (e.w_imm, &w)
                        && k == *h
                        && e.flags_w == 0
                    {
                        dead[i] = true;
                        continue;
                    }
                    if let (Some(m), W::Mem(h)) = (&e.w_mem, &w)
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
                if let W::Mem(h) = &next {
                    let clobbered = e.wmem.iter().any(|m| match m {
                        Mem::Unknown => true,
                        Mem::Sym(s) => s == h,
                    });
                    if clobbered {
                        next = W::Unknown;
                    }
                }
                // `movwf m` leaves a copy of W in m.
                if !wrote_w && let Some(m) = &e.w_mem && e.reads == [Loc::W] && env.is_plain(m) && e.wmem == [Mem::Sym(m.clone())] {
                    next = W::Mem(m.clone());
                }
                // A scratch register copy of W stays valid only until it is rewritten: not tracked.
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
    while i < items.len() {
        let keep = protected(items);
        if let Some((n, new)) = match_bit_branch(items, i, &keep) {
            // `n` items from `i`, minus an optional `movlb` between them that is kept.
            items.splice(i..i + n, new);
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
            Item::Br(Cc::Always, _) => true,
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
/// test of `x` repeats them. Only for compiler-placed RAM, whose read has no side effect.
fn pass_repeat_test(items: &mut Vec<Item>, env: &Env) -> bool {
    let keep = protected(items);
    let real: Vec<usize> = (0..items.len()).filter(|&i| !matches!(items[i], Item::Fence | Item::Comment(_))).collect();
    let mut dead = vec![false; items.len()];
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
                            && loc(o[0]).is_none()
                            && env.is_plain(o[0])
                            && (!needs_access || env.is_access(o[0]))
                        {
                            // The source must not change between the copy and the read.
                            let s = o[0].to_string();
                            let clobbered = items[k + 1..j].iter().any(|it| match it {
                                Item::Ins(v) => effect(v).is_none_or(|ev| ev.wmem.iter().any(|m| matches!(m, Mem::Unknown) || *m == Mem::Sym(s.clone()))),
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
pub fn optimise(mut items: Vec<Item>, env: &Env) -> Vec<Item> {
    for _ in 0..8 {
        let mut changed = false;
        changed |= pass_unused_labels(&mut items);
        changed |= pass_tail_call(&mut items);
        changed |= pass_unreachable(&mut items);
        changed |= pass_halt_loop(&mut items);
        changed |= pass_hoist_movlb(&mut items);
        changed |= pass_redundant_movlb(&mut items);
        changed |= pass_warg(&mut items);
        changed |= pass_bit_branch(&mut items);
        changed |= pass_branch_to_next(&mut items);
        changed |= pass_branch_over_branch(&mut items);
        changed |= pass_xorlw_zero(&mut items);
        changed |= pass_repeat_test(&mut items, env);
        changed |= pass_forward(&mut items, env);
        changed |= pass_wreg(&mut items, env);
        changed |= pass_dead_stores(&mut items, env);
        if !env.keep_writes {
            changed |= pass_write_only(&mut items, env);
        }
        if !changed {
            break;
        }
    }
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
        changed |= pass_branch_over_branch(&mut items);
        changed |= pass_xorlw_zero(&mut items);
        changed |= pass_repeat_test(&mut items, env);
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
        Env { plain, access: (0x00, 0x60), access_sfr: (0x60, 0x100), keep_writes: false, reg_calls: vec!["REG".into()] }
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
        assert_eq!(run(&s).len(), s.len() - 0, "{:?}", run(&s));
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
}
