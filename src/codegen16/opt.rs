//! Clean-up passes over the generated item list.

use crate::asm::{Cc, Item};
use std::collections::HashMap;

/// What is known about BSR at a point of the code.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Bsr {
    /// Not reached yet by the walk.
    Bottom,
    Known(u32),
    Unknown,
}

fn meet(a: Bsr, b: Bsr) -> Bsr {
    match (a, b) {
        (Bsr::Bottom, x) | (x, Bsr::Bottom) => x,
        (Bsr::Known(x), Bsr::Known(y)) if x == y => Bsr::Known(x),
        _ => Bsr::Unknown,
    }
}

fn tokens(t: &str) -> impl Iterator<Item = &str> {
    t.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).filter(|s| !s.is_empty())
}

fn movlb_of(t: &str) -> Option<u32> {
    let t = t.trim();
    let rest = t.strip_prefix("movlb")?.trim();
    rest.parse::<u32>().ok()
}

/// Removes every `movlb` that selects the bank BSR already holds on all paths that reach it. A path is followed
/// from the reset vector through fall-through, jumps and the item after a call (a callee may leave any bank
/// selected); a label that assembly text or a call can reach, and every handler, starts with BSR unknown.
pub fn drop_redundant_movlb(items: Vec<Item>) -> Vec<Item> {
    let n = items.len();
    let mut label_at: HashMap<&str, usize> = HashMap::new();
    for (i, it) in items.iter().enumerate() {
        if let Item::Label(l) = it {
            label_at.insert(l.as_str(), i);
        }
    }
    // Labels some other kind of jump can reach: calls, assembly text (branches written as instructions, addresses
    // taken with `low`/`high`), and the interrupt entry.
    let mut open: Vec<bool> = vec![false; n];
    for it in &items {
        match it {
            Item::Call(t) => {
                if let Some(&i) = label_at.get(t.as_str()) {
                    open[i] = true;
                }
            }
            Item::Ins(t) | Item::Raw(t) => {
                for tok in tokens(t) {
                    if let Some(&i) = label_at.get(tok) {
                        open[i] = true;
                    }
                }
            }
            _ => {}
        }
    }
    for (l, &i) in &label_at {
        if l.starts_with("__ISR") || *l == "__reset" {
            open[i] = true;
        }
    }
    let mut at_label: Vec<Bsr> = (0..n).map(|i| if open[i] { Bsr::Unknown } else { Bsr::Bottom }).collect();
    // Does control fall from item `i` to item `i + 1`?
    let falls = |it: &Item| -> bool {
        match it {
            Item::Br(Cc::Always, _) => false,
            Item::Ins(t) => !matches!(t.split_whitespace().next(), Some("return" | "retfie" | "retlw" | "goto" | "bra")),
            _ => true,
        }
    };
    loop {
        let mut changed = false;
        let mut cur = Bsr::Bottom;
        for i in 0..n {
            match &items[i] {
                Item::Label(_) => {
                    // Fall-through joins whatever else reaches the label.
                    let m = meet(at_label[i], cur);
                    if m != at_label[i] {
                        at_label[i] = m;
                        changed = true;
                    }
                    cur = m;
                }
                Item::Br(_, t) | Item::SkipBr(_, t) => {
                    if let Some(&j) = label_at.get(t.as_str()) {
                        let m = meet(at_label[j], cur);
                        if m != at_label[j] {
                            at_label[j] = m;
                            changed = true;
                        }
                    }
                }
                Item::Call(_) | Item::Raw(_) => cur = Bsr::Unknown,
                Item::Ins(t) => {
                    if let Some(b) = movlb_of(t) {
                        cur = Bsr::Known(b);
                    } else if tokens(t).any(|x| x == "BSR") {
                        cur = Bsr::Unknown;
                    }
                }
                _ => {}
            }
            if !falls(&items[i]) {
                cur = Bsr::Bottom;
            }
        }
        if !changed {
            break;
        }
    }
    // Second walk: drop what is redundant.
    let mut out = Vec::with_capacity(n);
    let mut cur = Bsr::Bottom;
    for (i, it) in items.into_iter().enumerate() {
        let mut keep = true;
        match &it {
            Item::Label(_) => cur = meet(at_label[i], cur),
            Item::Call(_) | Item::Raw(_) => cur = Bsr::Unknown,
            Item::Ins(t) => {
                if let Some(b) = movlb_of(t) {
                    if cur == Bsr::Known(b) {
                        keep = false;
                    }
                    cur = Bsr::Known(b);
                } else if tokens(t).any(|x| x == "BSR") {
                    cur = Bsr::Unknown;
                }
            }
            _ => {}
        }
        if !falls(&it) {
            cur = Bsr::Bottom;
        }
        if keep {
            out.push(it);
        }
    }
    out
}
