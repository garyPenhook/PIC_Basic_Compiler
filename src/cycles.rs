//! Instruction cycle counts, one table per core, for every pass that weighs cycles against words.
//!
//! The cores differ in what a taken branch or a skip costs, so no pass keeps a number of its own: it asks [`cost`].
//! Every entry below was read from the data sheet named beside it (the page is the PDF page).
//!
//! * [`Core::Pic16e`], the enhanced mid-range (DS40002343F, PIC16F17126/46, p.591, p.593): every instruction takes one
//!   cycle except `call`, `callw`, `return`, `retlw`, `retfie`, `goto`, `bra` and `brw` (two), and a skip that skips
//!   (two; every instruction is one word, so what it skips does not matter). An access through `INDF` whose `FSR`
//!   points at program memory costs one more cycle; that depends on a run-time pointer and is not counted here.
//! * [`Core::Pic18`], the PIC18 of the K22 (DS40001412H p.364-365) and the Q10 (DS40002043F p.626-629): `bra`, `rcall`,
//!   `call`, `goto`, `return`, `retfie`, `retlw`, `movff`, `lfsr` and the table reads and writes take two cycles; a
//!   conditional branch one, two when taken; a skip one, two over a one-word instruction, three over a two-word one.
//! * [`Core::Pic18Q41`] (DS40002214G p.805-807, p.819; extended set p.866-869): as above, and `movffl` and `movsfl`
//!   take three cycles, `callw`, `movsf`, `movss`, `addulnk` and `subulnk` two, `pushl` one, and a skip over a
//!   three-word instruction (`movffl`, `movsfl`) takes four.
//!
//! A byte instruction that stores into `PCL` (`addwf PCL, f`) takes two cycles on every PIC18 (the program counter changes).
//!
//! An instruction the table does not list gives `None` from [`cost`]; a caller must treat it as unknown, not as one cycle.

/// The instruction timing a part follows.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Core {
    Pic16e,
    Pic18,
    Pic18Q41,
}

impl Core {
    /// The core of a device named as in `devices/` (`16F17146`, `PIC18F46K22`, `18F04Q41`), or `None` for a name that is neither.
    pub fn of_device(name: &str) -> Option<Core> {
        let n = name.trim().to_ascii_uppercase();
        let n = n.strip_prefix("PIC").unwrap_or(&n);
        if n.starts_with("18") {
            Some(if n.contains("Q41") { Core::Pic18Q41 } else { Core::Pic18 })
        } else if n.starts_with("16") {
            Some(Core::Pic16e)
        } else {
            None
        }
    }
}

/// Cycles an instruction takes: `fall` when it leaves the program counter alone, `taken` when it branches, or skips.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cost {
    pub fall: u32,
    pub taken: u32,
}

impl Cost {
    const fn flat(n: u32) -> Cost {
        Cost { fall: n, taken: n }
    }
}

/// The cycles of the instruction `text` on `core`. `skipped_words` is the size in words of the instruction that follows
/// it, which a skip passes over (ignored for any other instruction). `None` for text that is not an instruction, or an
/// instruction the table does not know.
pub fn cost(core: Core, text: &str, skipped_words: u32) -> Option<Cost> {
    let t = text.trim();
    if t.is_empty() || t.starts_with(';') || t.ends_with(':') {
        return None;
    }
    let mn = t.split_whitespace().next()?.to_ascii_lowercase();
    match core {
        Core::Pic16e => cost16(&mn),
        Core::Pic18 | Core::Pic18Q41 if writes_pcl(t, &mn) => Some(Cost::flat(2)),
        Core::Pic18 | Core::Pic18Q41 => cost18(core, &mn, skipped_words),
    }
}

/// A byte instruction that stores into `PCL` (`addwf PCL, f`, `movwf PCL`): the program counter changes, so it takes two
/// cycles (DS40002043F p.626 note 2; DS40002214G p.808 note 2; `addwf PCL, f` in basil's dense `Select` takes two in
/// basil-sim).
fn writes_pcl(text: &str, mn: &str) -> bool {
    let rest = text.trim_start()[mn.len()..].trim_start();
    let mut ops = rest.split(',').map(str::trim);
    if !ops.next().is_some_and(|f| f.eq_ignore_ascii_case("PCL")) {
        return false;
    }
    match mn {
        "movwf" => true,
        "addwf" | "addwfc" | "andwf" | "comf" | "decf" | "incf" | "iorwf" | "rlcf" | "rlncf" | "rrcf" | "rrncf" | "subfwb" | "subwf" | "subwfb" | "swapf" | "xorwf" => {
            ops.next().is_some_and(|d| d.eq_ignore_ascii_case("f") || d == "1")
        }
        "clrf" | "setf" | "negf" => true,
        _ => false,
    }
}

fn cost16(mn: &str) -> Option<Cost> {
    Some(match mn {
        "call" | "callw" | "return" | "retlw" | "retfie" | "goto" | "bra" | "brw" => Cost::flat(2),
        // The assembler's two-word forms: `movlp` (one) then `call` or `goto` (two).
        "fcall" | "ljmp" => Cost::flat(3),
        "btfsc" | "btfss" | "decfsz" | "incfsz" => Cost { fall: 1, taken: 2 },
        _ if is_16_one_cycle(mn) => Cost::flat(1),
        _ => return None,
    })
}

fn is_16_one_cycle(mn: &str) -> bool {
    matches!(
        mn,
        "addwf" | "addwfc" | "andwf" | "asrf" | "clrf" | "clrw" | "comf" | "decf" | "incf" | "iorwf" | "lslf" | "lsrf" | "movf" | "movwf" | "nop" | "rlf" | "rrf" | "subwf" | "subwfb" | "swapf" | "xorwf" | "bcf" | "bsf" | "addlw" | "andlw" | "iorlw" | "movlb" | "movlp" | "movlw" | "sublw" | "xorlw" | "clrwdt" | "reset" | "sleep" | "addfsr" | "moviw" | "movwi"
    )
}

fn cost18(core: Core, mn: &str, skipped_words: u32) -> Option<Cost> {
    Some(match mn {
        "bra" | "rcall" | "call" | "goto" | "return" | "retfie" | "retlw" | "movff" | "lfsr" | "tblrd" | "tblwt" => Cost::flat(2),
        m if m.starts_with("tblrd") || m.starts_with("tblwt") => Cost::flat(2),
        "callw" if core == Core::Pic18Q41 => Cost::flat(2),
        "movffl" | "movsfl" if core == Core::Pic18Q41 => Cost::flat(3),
        "movsf" | "movss" | "addulnk" | "subulnk" if core == Core::Pic18Q41 => Cost::flat(2),
        "pushl" if core == Core::Pic18Q41 => Cost::flat(1),
        "bc" | "bn" | "bnc" | "bnn" | "bnov" | "bnz" | "bov" | "bz" => Cost { fall: 1, taken: 2 },
        // A skip fetches the word after it and throws it away; a two-word (three-word) instruction takes one (two) more.
        "btfsc" | "btfss" | "cpfseq" | "cpfsgt" | "cpfslt" | "decfsz" | "dcfsnz" | "incfsz" | "infsnz" | "tstfsz" => Cost { fall: 1, taken: 1 + skipped_words.clamp(1, 3) },
        _ if is_18_one_cycle(mn) => Cost::flat(1),
        _ => return None,
    })
}

fn is_18_one_cycle(mn: &str) -> bool {
    matches!(
        mn,
        "addwf" | "addwfc" | "andwf" | "clrf" | "comf" | "decf" | "incf" | "iorwf" | "movf" | "movwf" | "mulwf" | "negf" | "rlcf" | "rlncf" | "rrcf" | "rrncf" | "setf" | "subfwb" | "subwf" | "subwfb" | "swapf" | "xorwf" | "bcf" | "bsf" | "btg" | "clrwdt" | "daw" | "nop" | "pop" | "push" | "reset" | "sleep" | "addfsr" | "addlw" | "andlw" | "iorlw" | "movlb" | "movlw" | "mullw" | "sublw" | "subfsr" | "xorlw"
    )
}

/// A static cycle count of one routine in the assembly text: every instruction counted once, so a loop counts as a
/// single pass. Not a run-time figure.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Static {
    /// The instructions counted.
    pub ins: u32,
    /// Cycles with every branch and skip falling through.
    pub straight: u32,
    /// Cycles with every branch and skip taken.
    pub taken: u32,
    /// Instructions the table does not know (counted as nothing).
    pub unknown: u32,
}

/// The mnemonic of an assembly line that is an instruction, `None` for a label, directive, data or comment.
fn instruction(line: &str) -> Option<&str> {
    let t = line.trim();
    if t.is_empty() || t.starts_with(';') || t.starts_with('#') || t.ends_with(':') || t.contains(" equ ") {
        return None;
    }
    let mn = t.split_whitespace().next()?;
    let low = mn.to_ascii_lowercase();
    if matches!(low.as_str(), "db" | "dw" | "org" | "psect" | "global" | "config" | "ds" | "align" | "end" | "extrn") {
        return None;
    }
    Some(t)
}

/// Cycles with the routines it calls added in (once per call instruction, not per run time call).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Cycles {
    pub straight: u32,
    pub taken: u32,
    /// Instructions and calls that could not be counted (unknown to the table, or a call to no known routine).
    pub unknown: u32,
    /// The routine can call itself, directly or through others; the call that closes the cycle counts for nothing.
    pub recursive: bool,
}

impl Cycles {
    fn add(&mut self, o: Cycles) {
        self.straight = self.straight.saturating_add(o.straight);
        self.taken = self.taken.saturating_add(o.taken);
        self.unknown += o.unknown;
        self.recursive |= o.recursive;
    }
}

/// One loop: a branch back to a label already passed in the same routine. The cost is one pass from that label to the
/// branch (the trip count is a run-time figure), with the routines called inside it added.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct LoopCycles {
    pub label: String,
    pub pass: Cycles,
}

/// The cycles of one routine: its own instructions, those with its calls added, and its loops.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct RoutineCycles {
    pub name: String,
    pub own: Static,
    /// Call instructions in the routine.
    pub calls: u32,
    pub with_calls: Cycles,
    pub loops: Vec<LoopCycles>,
}

struct RawLoop {
    label: String,
    straight: u32,
    taken: u32,
    calls: Vec<String>,
}

#[derive(Default)]
struct Raw {
    name: String,
    own: Static,
    calls: Vec<String>,
    loops: Vec<RawLoop>,
    /// Running totals and call count at each label seen so far in this routine.
    seen: std::collections::HashMap<String, (u32, u32, usize)>,
}

/// The target of a branch or call: its first operand (`call F`, `bra _L3`, `goto X`), `None` for an instruction without one.
fn operand(ins: &str) -> &str {
    ins.split_whitespace().nth(1).map_or("", |o| o.trim_end_matches(','))
}

fn is_branch(mn: &str) -> bool {
    matches!(mn, "bra" | "goto" | "ljmp" | "bc" | "bn" | "bnc" | "bnn" | "bnov" | "bnz" | "bov" | "bz")
}

fn is_call(mn: &str) -> bool {
    matches!(mn, "call" | "rcall" | "fcall" | "callw")
}

/// Static cycles per routine for the code in `asm` (the text of the `.S` file). A routine runs from one label that is
/// not local (`_L...`) to the next. Every instruction counts once, so a loop is one pass; a `call` adds the whole of the
/// routine it calls (once per call instruction); each loop is listed with the cost of one pass. `words` is the size of
/// an instruction in words (what a skip passes over).
pub fn analyse(core: Core, asm: &str, words: &dyn Fn(&str) -> u32) -> Vec<RoutineCycles> {
    let mut raws: Vec<Raw> = Vec::new();
    let mut in_code = false;
    let lines: Vec<&str> = asm.lines().collect();
    for (i, line) in lines.iter().enumerate() {
        let t = line.trim();
        if !in_code {
            in_code = t.starts_with("PSECT code,") || t.starts_with("PSECT basilcode,");
            continue;
        }
        if let Some(label) = t.strip_suffix(':')
            && !label.contains(char::is_whitespace)
        {
            if !label.starts_with("_L") {
                raws.push(Raw { name: label.to_string(), ..Raw::default() });
            } else if let Some(r) = raws.last_mut() {
                r.seen.insert(label.to_string(), (r.own.straight, r.own.taken, r.calls.len()));
            }
            continue;
        }
        let Some(ins) = instruction(line) else { continue };
        if raws.is_empty() {
            raws.push(Raw::default());
        }
        let next = lines[i + 1..].iter().find_map(|l| instruction(l)).map_or(1, words);
        let r = raws.last_mut().unwrap();
        let mn = ins.split_whitespace().next().unwrap_or("").to_ascii_lowercase();
        let Some(k) = cost(core, ins, next) else {
            r.own.unknown += 1;
            continue;
        };
        if is_call(&mn) {
            r.calls.push(operand(ins).to_string());
        }
        if is_branch(&mn)
            && let Some(&(f, tk, c)) = r.seen.get(operand(ins))
        {
            let lp = RawLoop { label: operand(ins).to_string(), straight: r.own.straight + k.taken - f, taken: r.own.taken + k.taken - tk, calls: r.calls[c..].to_vec() };
            r.loops.push(lp);
        }
        r.own.ins += 1;
        r.own.straight += k.fall;
        r.own.taken += k.taken;
    }
    let index: std::collections::HashMap<&str, usize> = {
        let mut m = std::collections::HashMap::new();
        for (i, r) in raws.iter().enumerate() {
            m.entry(r.name.as_str()).or_insert(i);
        }
        m
    };
    let mut state = vec![0u8; raws.len()];
    let mut memo = vec![Cycles::default(); raws.len()];
    for i in 0..raws.len() {
        inclusive(i, &raws, &index, &mut state, &mut memo);
    }
    raws.iter()
        .enumerate()
        .map(|(i, r)| RoutineCycles {
            name: r.name.clone(),
            own: r.own,
            calls: r.calls.len() as u32,
            with_calls: memo[i],
            loops: r
                .loops
                .iter()
                .map(|l| {
                    let mut c = Cycles { straight: l.straight, taken: l.taken, ..Cycles::default() };
                    for n in &l.calls {
                        c.add(callee_cost(n, &raws, &index, &mut state, &mut memo));
                    }
                    LoopCycles { label: l.label.clone(), pass: c }
                })
                .collect(),
        })
        .collect()
}

fn callee_cost(name: &str, raws: &[Raw], index: &std::collections::HashMap<&str, usize>, state: &mut [u8], memo: &mut [Cycles]) -> Cycles {
    match index.get(name) {
        Some(&j) if state[j] == 1 => Cycles { recursive: true, ..Cycles::default() },
        Some(&j) => inclusive(j, raws, index, state, memo),
        None => Cycles { unknown: 1, ..Cycles::default() },
    }
}

fn inclusive(i: usize, raws: &[Raw], index: &std::collections::HashMap<&str, usize>, state: &mut [u8], memo: &mut [Cycles]) -> Cycles {
    if state[i] == 2 {
        return memo[i];
    }
    state[i] = 1;
    let r = &raws[i];
    let mut c = Cycles { straight: r.own.straight, taken: r.own.taken, unknown: r.own.unknown, recursive: false };
    for n in &r.calls {
        c.add(callee_cost(n, raws, index, state, memo));
    }
    state[i] = 2;
    memo[i] = c;
    c
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(core: Core, t: &str, skip: u32) -> (u32, u32) {
        let k = cost(core, t, skip).unwrap_or_else(|| panic!("{t} unknown"));
        (k.fall, k.taken)
    }

    #[test]
    fn device_names_pick_the_core() {
        assert_eq!(Core::of_device("16F17146"), Some(Core::Pic16e));
        assert_eq!(Core::of_device("PIC16LF15313"), Some(Core::Pic16e));
        assert_eq!(Core::of_device("PIC18F46K22"), Some(Core::Pic18));
        assert_eq!(Core::of_device("18F27Q10"), Some(Core::Pic18));
        assert_eq!(Core::of_device("18F04Q41"), Some(Core::Pic18Q41));
        assert_eq!(Core::of_device("dsPIC33CK64MC105"), None);
    }

    #[test]
    fn pic16_branches_calls_and_skips() {
        assert_eq!(c(Core::Pic16e, "bra L1", 1), (2, 2));
        assert_eq!(c(Core::Pic16e, "call f", 1), (2, 2));
        assert_eq!(c(Core::Pic16e, "return", 1), (2, 2));
        assert_eq!(c(Core::Pic16e, "btfsc STATUS, 2", 1), (1, 2));
        assert_eq!(c(Core::Pic16e, "decfsz cnt, f", 1), (1, 2));
        assert_eq!(c(Core::Pic16e, "movlw 5", 1), (1, 1));
        assert_eq!(c(Core::Pic16e, "ljmp far", 1), (3, 3));
    }

    #[test]
    fn pic18_skips_cost_what_they_pass_over() {
        assert_eq!(c(Core::Pic18, "btfss PORTA, 0, c", 1), (1, 2));
        assert_eq!(c(Core::Pic18, "btfss PORTA, 0, c", 2), (1, 3));
        assert_eq!(c(Core::Pic18, "cpfseq x, a", 2), (1, 3));
        assert_eq!(c(Core::Pic18Q41, "tstfsz x, a", 3), (1, 4));
    }

    #[test]
    fn pic18_branches_and_two_cycle_instructions() {
        assert_eq!(c(Core::Pic18, "bz L", 1), (1, 2));
        assert_eq!(c(Core::Pic18, "bra L", 1), (2, 2));
        assert_eq!(c(Core::Pic18, "goto L", 1), (2, 2));
        assert_eq!(c(Core::Pic18, "movff a, b", 1), (2, 2));
        assert_eq!(c(Core::Pic18, "tblrd*+", 1), (2, 2));
        assert_eq!(c(Core::Pic18, "mullw 3", 1), (1, 1));
    }

    #[test]
    fn a_store_into_pcl_takes_two_cycles() {
        assert_eq!(c(Core::Pic18, "addwf PCL, f, c", 1), (2, 2));
        assert_eq!(c(Core::Pic18Q41, "addwf PCL, f, c", 1), (2, 2));
        assert_eq!(c(Core::Pic18, "movwf PCL, c", 1), (2, 2));
        assert_eq!(c(Core::Pic18, "addwf PCL, w, c", 1), (1, 1));
        assert_eq!(c(Core::Pic18, "movf PCL, w, c", 1), (1, 1));
        assert_eq!(c(Core::Pic18, "addwf x, f, c", 1), (1, 1));
    }

    #[test]
    fn q41_extras_are_not_on_the_older_cores() {
        assert_eq!(c(Core::Pic18Q41, "movffl a, b", 1), (3, 3));
        assert!(cost(Core::Pic18, "movffl a, b", 1).is_none());
        assert!(cost(Core::Pic18, "callw", 1).is_none());
        assert_eq!(c(Core::Pic18Q41, "callw", 1), (2, 2));
        assert_eq!(c(Core::Pic18Q41, "movsf [1], 2", 1), (2, 2));
        assert_eq!(c(Core::Pic18Q41, "movss [1], [2]", 1), (2, 2));
        assert_eq!(c(Core::Pic18Q41, "movsfl [1], 2", 1), (3, 3));
        assert_eq!(c(Core::Pic18Q41, "pushl 4", 1), (1, 1));
        assert!(cost(Core::Pic18, "movsf [1], 2", 1).is_none());
    }

    #[test]
    fn unknown_and_non_instructions_are_none() {
        assert!(cost(Core::Pic18Q41, "foo [1], 2", 1).is_none());
        assert!(cost(Core::Pic16e, "L1:", 1).is_none());
        assert!(cost(Core::Pic16e, "; comment", 1).is_none());
        assert!(cost(Core::Pic16e, "", 1).is_none());
    }

    #[test]
    fn static_cycles_per_routine() {
        let asm = "; basil output\nPSECT code,class=CODE,abs,delta=1\n__reset:\n    movlw 3\n_L1:\n    decfsz WREG, f, c\n    bra _L1\n    return\nF:\n    btfss PORTA, 0, c\n    goto X\n    nop\n    foo 1\n";
        let r = analyse(Core::Pic18, asm, &crate::asm::words_of);
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].name, "__reset");
        // movlw 1 + decfsz 1 (2 taken over a one-word `bra`) + bra 2 + return 2.
        assert_eq!(r[0].own, Static { ins: 4, straight: 6, taken: 7, unknown: 0 });
        // btfss over a two-word `goto`: 1 straight, 3 taken; goto 2; nop 1; `foo` unknown.
        assert_eq!(r[1].own, Static { ins: 3, straight: 4, taken: 6, unknown: 1 });
    }

    #[test]
    fn a_loop_is_one_pass_from_its_label_to_the_branch() {
        let asm = "PSECT code,class=CODE\nR:\n    movlw 3\n_L1:\n    decfsz WREG, f, c\n    bra _L1\n    return\n";
        let r = analyse(Core::Pic18, asm, &crate::asm::words_of);
        assert_eq!(r[0].loops.len(), 1);
        // decfsz 1 (2 when it skips the one-word bra) + bra 2.
        assert_eq!(r[0].loops[0].pass, Cycles { straight: 3, taken: 4, unknown: 0, recursive: false });
        // A forward branch is no loop.
        let fwd = "PSECT code,class=CODE\nR:\n    bra _L2\n_L2:\n    return\n";
        assert!(analyse(Core::Pic18, fwd, &crate::asm::words_of)[0].loops.is_empty());
    }

    #[test]
    fn a_call_adds_the_callee_and_a_loop_adds_the_calls_in_its_body() {
        let asm = "PSECT code,class=CODE\nMAIN:\n    call A\n_L1:\n    call B\n    bra _L1\nA:\n    nop\n    call B\n    return\nB:\n    nop\n    return\n";
        let r = analyse(Core::Pic18, asm, &crate::asm::words_of);
        // B = 1 + 2 = 3; A = 1 + 2 + 3 + 2 = 8; MAIN = 2 + 8 + 2 + 3 + 2 = 17.
        assert_eq!(r[2].with_calls.straight, 3);
        assert_eq!(r[1].with_calls.straight, 8);
        assert_eq!(r[0].with_calls.straight, 17);
        assert_eq!(r[0].calls, 2);
        // The loop: call B 2 + B 3 + bra 2.
        assert_eq!(r[0].loops[0].pass.straight, 7);
    }

    #[test]
    fn recursion_and_unknown_callees_are_flagged_not_counted() {
        let asm = "PSECT code,class=CODE\nF:\n    call G\n    return\nG:\n    call F\n    call NOWHERE\n    return\n";
        let r = analyse(Core::Pic18, asm, &crate::asm::words_of);
        assert!(r[0].with_calls.recursive);
        assert_eq!(r[1].with_calls.unknown, 1);
        // G = call F 2 (the callee is in progress, so nothing added) + call NOWHERE 2 + return 2.
        assert_eq!(r[1].with_calls.straight, 6);
    }
}
