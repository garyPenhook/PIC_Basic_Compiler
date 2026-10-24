//! The assembly item list and its final form: branch relaxation and pic-as text.
//!
//! The code generator produces `Item`s with symbolic jump targets. Short forms (`bra`, `rcall`,
//! one-word conditional branches) are used wherever the target is in range; out-of-range ones
//! become `goto`/`call` (and an inverted skip for conditional branches). The sizes are exact, so
//! the relaxation reaches the smallest consistent assignment (PLAN §7A.3 priority 5).

use std::collections::HashMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cc {
    Always,
    Z,
    Nz,
    C,
    Nc,
    N,
    Nn,
    Ov,
    Nov,
}

impl Cc {
    pub fn invert(self) -> Cc {
        match self {
            Cc::Z => Cc::Nz,
            Cc::Nz => Cc::Z,
            Cc::C => Cc::Nc,
            Cc::Nc => Cc::C,
            Cc::N => Cc::Nn,
            Cc::Nn => Cc::N,
            Cc::Ov => Cc::Nov,
            Cc::Nov => Cc::Ov,
            Cc::Always => Cc::Always,
        }
    }
    fn mnemonic(self) -> &'static str {
        match self {
            Cc::Always => "bra",
            Cc::Z => "bz",
            Cc::Nz => "bnz",
            Cc::C => "bc",
            Cc::Nc => "bnc",
            Cc::N => "bn",
            Cc::Nn => "bnn",
            Cc::Ov => "bov",
            Cc::Nov => "bnov",
        }
    }
}

#[derive(Clone, Debug)]
pub enum Item {
    Label(String),
    /// One instruction, fully written (`movwf X, c`).
    Ins(String),
    /// A branch to a label: `bra`/`bcc`, or the long form when out of range.
    Br(Cc, String),
    /// `rcall` or `call`.
    Call(String),
    /// Lines from an `Asm` block, passed through.
    Raw(String),
    Comment(String),
    /// End of a statement: no value is carried in `WREG` or the scratch registers past it. Emits
    /// nothing; the peephole pass reads it.
    Fence,
    /// `Keep(true)` starts, and `Keep(false)` ends, code whose exact instructions matter (cycle
    /// counted delays): the peephole pass leaves it untouched. Emits nothing.
    Keep(bool),
    /// Constant bytes in program memory (an even number of them).
    Data(Vec<u8>),
}

/// Words an instruction occupies, from its mnemonic.
pub fn words_of(text: &str) -> u32 {
    let t = text.trim();
    let m = t.split(|c: char| c.is_whitespace()).next().unwrap_or("").to_ascii_lowercase();
    match m.as_str() {
        "goto" | "call" | "movff" | "lfsr" | "movsf" | "movss" => 2,
        "" => 0,
        _ if m.ends_with(':') => 0,
        _ if m.starts_with(';') || m.starts_with('#') => 0,
        // Directives and data defined in raw blocks; counted as one word each when unknown.
        _ => 1,
    }
}

pub struct Assembled {
    pub lines: Vec<String>,
    /// Word address (from the start of the code) of every label.
    pub labels: HashMap<String, u32>,
    pub words: u32,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Form {
    Short,
    Long,
}

fn size_of(it: &Item, f: Form) -> u32 {
    match it {
        Item::Label(_) | Item::Comment(_) | Item::Fence | Item::Keep(_) => 0,
        Item::Ins(t) => words_of(t),
        Item::Raw(t) => words_of(t),
        Item::Br(Cc::Always, _) => if f == Form::Short { 1 } else { 2 },
        Item::Br(_, _) => if f == Form::Short { 1 } else { 3 },
        Item::Call(_) => if f == Form::Short { 1 } else { 2 },
        Item::Data(b) => b.len().div_ceil(2) as u32,
    }
}

/// Resolves branch forms and produces the text. `start` is the word address of the first item.
pub fn assemble(items: &[Item], start: u32) -> Assembled {
    let mut forms = vec![Form::Short; items.len()];
    let mut labels: HashMap<String, u32> = HashMap::new();
    loop {
        labels.clear();
        let mut pc = start;
        let mut at = vec![0u32; items.len()];
        for (i, it) in items.iter().enumerate() {
            at[i] = pc;
            match it {
                Item::Label(l) => {
                    labels.insert(l.clone(), pc);
                }
                // A label written in an `Asm` block (benchmark markers, entry points).
                Item::Raw(t) if t.trim().ends_with(':') && !t.trim().contains(' ') => {
                    labels.insert(t.trim().trim_end_matches(':').to_string(), pc);
                }
                _ => {}
            }
            pc += size_of(it, forms[i]);
        }
        let mut changed = false;
        for (i, it) in items.iter().enumerate() {
            if forms[i] == Form::Long {
                continue;
            }
            let (target, limit) = match it {
                Item::Br(Cc::Always, t) | Item::Call(t) => (t, 1023i64),
                Item::Br(_, t) => (t, 127i64),
                _ => continue,
            };
            // Targets outside the generated code (device symbols) are assumed far away.
            let ok = labels.get(target).is_some_and(|&t| {
                let d = t as i64 - (at[i] as i64 + 1);
                (-limit - 1..=limit).contains(&d)
            });
            if !ok {
                forms[i] = Form::Long;
                changed = true;
            }
        }
        if !changed {
            let words = pc - start;
            let mut lines = Vec::new();
            let mut skip_n = 0;
            for (i, it) in items.iter().enumerate() {
                match it {
                    Item::Label(l) => lines.push(format!("{l}:")),
                    Item::Ins(t) => lines.push(format!("    {t}")),
                    Item::Raw(t) => lines.push(format!("    {t}")),
                    Item::Comment(t) => lines.push(format!("    ; {t}")),
                    Item::Fence | Item::Keep(_) => {}
                    Item::Data(b) => {
                        let text: Vec<String> = b.iter().map(|x| format!("0x{x:02X}")).collect();
                        lines.push(format!("    db {}", text.join(", ")));
                    }
                    Item::Br(cc, t) => match (forms[i], cc) {
                        (Form::Short, _) => lines.push(format!("    {} {t}", cc.mnemonic())),
                        (Form::Long, Cc::Always) => lines.push(format!("    goto {t}")),
                        (Form::Long, cc) => {
                            skip_n += 1;
                            let l = format!("__skip{skip_n}");
                            lines.push(format!("    {} {l}", cc.invert().mnemonic()));
                            lines.push(format!("    goto {t}"));
                            lines.push(format!("{l}:"));
                        }
                    },
                    Item::Call(t) => lines.push(format!("    {} {t}", if forms[i] == Form::Short { "rcall" } else { "call" })),
                }
            }
            return Assembled { lines, labels, words };
        }
    }
}
