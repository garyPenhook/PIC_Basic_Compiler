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
}
