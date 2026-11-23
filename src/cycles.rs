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
//! * [`Core::Pic18Q41`] (DS40002214G p.805-807, p.819): as above, and `movffl` takes three cycles, `callw` two, and a
//!   skip over a three-word instruction (`movffl`) takes four.
//!
//! `movsf` and `movss` (Q41) are not in the table: their cycle counts were not read, so [`cost`] gives `None` for them
//! and a caller must treat the instruction as unknown, not as one cycle.

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
        Core::Pic18 | Core::Pic18Q41 => cost18(core, &mn, skipped_words),
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
        "movffl" if core == Core::Pic18Q41 => Cost::flat(3),
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

/// Static cycles per routine for the code in `asm` (the text of the `.S` file). A routine runs from one label that is
/// not local (`_L...`) to the next; the result is keyed by that label. `words` is the size of an instruction in words
/// (what a skip passes over).
pub fn per_routine(core: Core, asm: &str, words: &dyn Fn(&str) -> u32) -> Vec<(String, Static)> {
    let mut out: Vec<(String, Static)> = Vec::new();
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
            && !label.starts_with("_L")
        {
            out.push((label.to_string(), Static::default()));
            continue;
        }
        let Some(ins) = instruction(line) else { continue };
        if out.is_empty() {
            out.push((String::new(), Static::default()));
        }
        let next = lines[i + 1..].iter().find_map(|l| instruction(l)).map_or(1, words);
        let r = &mut out.last_mut().unwrap().1;
        match cost(core, ins, next) {
            Some(k) => {
                r.ins += 1;
                r.straight += k.fall;
                r.taken += k.taken;
            }
            None => r.unknown += 1,
        }
    }
    out
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
    fn q41_extras_are_not_on_the_older_cores() {
        assert_eq!(c(Core::Pic18Q41, "movffl a, b", 1), (3, 3));
        assert!(cost(Core::Pic18, "movffl a, b", 1).is_none());
        assert!(cost(Core::Pic18, "callw", 1).is_none());
        assert_eq!(c(Core::Pic18Q41, "callw", 1), (2, 2));
    }

    #[test]
    fn unknown_and_non_instructions_are_none() {
        assert!(cost(Core::Pic18Q41, "movsf [1], 2", 1).is_none());
        assert!(cost(Core::Pic16e, "L1:", 1).is_none());
        assert!(cost(Core::Pic16e, "; comment", 1).is_none());
        assert!(cost(Core::Pic16e, "", 1).is_none());
    }

    #[test]
    fn static_cycles_per_routine() {
        let asm = "; basil output\nPSECT code,class=CODE,abs,delta=1\n__reset:\n    movlw 3\n_L1:\n    decfsz WREG, f, c\n    bra _L1\n    return\nF:\n    btfss PORTA, 0, c\n    goto X\n    nop\n    foo 1\n";
        let r = per_routine(Core::Pic18, asm, &crate::asm::words_of);
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].0, "__reset");
        // movlw 1 + decfsz 1 (2 taken over a one-word `bra`) + bra 2 + return 2.
        assert_eq!(r[0].1, Static { ins: 4, straight: 6, taken: 7, unknown: 0 });
        // btfss over a two-word `goto`: 1 straight, 3 taken; goto 2; nop 1; `foo` unknown.
        assert_eq!(r[1].1, Static { ins: 3, straight: 4, taken: 6, unknown: 1 });
    }
}
