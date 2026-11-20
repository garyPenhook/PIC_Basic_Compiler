//! Outlining (procedural abstraction) of repeated instruction runs, PIC18.
//!
//! Generated code repeats itself: the argument set-up and call of `OledFillRect(x, y, w, h, 1)` differ only in
//! constants, but screens full of identical `movlw 1 / movwf P__ON / ...` runs, `clrf` of a high byte before every
//! call, and the same statement written in several places are common. This pass runs on the final items, after every
//! peephole pass, and moves a run that occurs often enough into one shared block (`__PLn`) that each occurrence
//! calls. The run executes the same instructions in the same order, so registers, flags and memory after the call
//! are exactly what they were after the inline run.
//!
//! What may be outlined: straight-line instructions with no label inside, no branch, no stack or program-counter
//! access, and not inside a `Keep` (cycle counted) or `Fit` (jump table) region. Two refinements:
//!
//! * A run that ends in a `call` becomes a block that ends in a jump to that routine. The routine then returns
//!   straight to the outlined site, so the hardware stack is no deeper than before.
//! * Any other run adds one stack level while it executes, so those are used only when the program has the headroom
//!   (the worst case is one extra level in the main chain and in each interrupt priority).
//!
//! A skip instruction may sit inside a run, but not last (it would skip past the `return`), and not just before a
//! jump-ending run's last item. A run may not start straight after a skip instruction, which would now skip the
//! whole call instead of one instruction.

use crate::asm::{assemble, words_of, Cc, Item};
use std::collections::HashMap;

/// Longest run, in instructions, that is looked for.
const MAX_LEN: usize = 48;

const SKIPS: [&str; 10] = ["btfsc", "btfss", "cpfseq", "cpfsgt", "cpfslt", "tstfsz", "decfsz", "dcfsnz", "incfsz", "infsnz"];

/// Instructions that change the flow of control or the stack.
const FLOW: [&str; 21] = [
    "return", "retfie", "retlw", "reset", "sleep", "push", "pop", "call", "rcall", "callw", "goto", "bra", "bz", "bnz", "bc", "bnc", "bn", "bnn", "bov", "bnov", "clrwdt",
];

/// Registers whose use makes an instruction depend on where it runs or on the stack.
const SPECIAL: [&str; 9] = ["pcl", "pclath", "pclatu", "tosl", "tosh", "tosu", "stkptr", "$", ":"];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    Plain,
    Skip,
    /// A `call`: only as the last instruction of a run.
    Tail,
}

struct Tok {
    id: u32,
    item: usize,
    words: u32,
    kind: Kind,
    /// An instruction before this one skips it (a run cannot start here).
    after_skip: bool,
    run: usize,
}

fn mnemonic(t: &str) -> String {
    t.split_whitespace().next().unwrap_or("").to_ascii_lowercase()
}

fn is_skip(it: &Item) -> bool {
    match it {
        Item::Ins(t) => SKIPS.contains(&mnemonic(t).as_str()),
        // Raw text may end in anything.
        Item::Raw(_) => true,
        _ => false,
    }
}

/// `Some(kind, text)` for an item that may be part of a run.
fn classify(it: &Item) -> Option<(Kind, String)> {
    match it {
        Item::Ins(t) => {
            let t = t.split(';').next().unwrap_or("").trim();
            let m = mnemonic(t);
            if m.is_empty() || FLOW.contains(&m.as_str()) {
                return None;
            }
            let low = t.to_ascii_lowercase();
            if SPECIAL.iter().any(|s| low.contains(s)) {
                return None;
            }
            let kind = if SKIPS.contains(&m.as_str()) { Kind::Skip } else { Kind::Plain };
            Some((kind, t.split_whitespace().collect::<Vec<_>>().join(" ")))
        }
        Item::Call(t) => Some((Kind::Tail, format!("\0call {t}"))),
        _ => None,
    }
}

fn tokenise(items: &[Item], ids: &mut HashMap<String, u32>) -> Vec<Tok> {
    let mut toks: Vec<Tok> = Vec::new();
    let mut run = 0usize;
    let mut guarded = 0u32;
    for (i, it) in items.iter().enumerate() {
        match it {
            Item::Keep(true) | Item::Fit(true) => {
                guarded += 1;
                run += 1;
                continue;
            }
            Item::Keep(false) | Item::Fit(false) => {
                guarded = guarded.saturating_sub(1);
                run += 1;
                continue;
            }
            Item::Comment(_) | Item::Fence => continue,
            _ => {}
        }
        if guarded > 0 {
            run += 1;
            continue;
        }
        match classify(it) {
            Some((kind, text)) => {
                let next = ids.len() as u32;
                let id = *ids.entry(text).or_insert(next);
                let after_skip = items[..i].iter().rev().find(|x| !matches!(x, Item::Comment(_) | Item::Fence | Item::Label(_))).is_some_and(is_skip);
                let words = match it {
                    Item::Ins(t) => words_of(t),
                    _ => 2,
                };
                toks.push(Tok { id, item: i, words, kind, after_skip, run });
                // A tail call ends the run: nothing after it may join a run that includes it.
                if kind == Kind::Tail {
                    run += 1;
                }
            }
            None => run += 1,
        }
    }
    toks
}

fn mix(h: u64, id: u32) -> u64 {
    (h ^ (id as u64 + 0x9E37_79B9_7F4A_7C15)).wrapping_mul(0x0000_0100_0000_01B3).rotate_left(23)
}

/// Replaces repeated runs by calls to shared blocks. `allow_plain` lets runs that do not end in a call cost a
/// hardware-stack level. Never returns a larger program than it was given.
pub fn outline(items: Vec<Item>, allow_plain: bool) -> Vec<Item> {
    let before = assemble(&items, 0).words;
    let mut cur = items.clone();
    let mut ids: HashMap<String, u32> = HashMap::new();
    let mut bodies: Vec<(String, Vec<Item>)> = Vec::new();
    loop {
        let toks = tokenise(&cur, &mut ids);
        let mut cands: HashMap<(u64, usize), Vec<usize>> = HashMap::new();
        for s in 0..toks.len() {
            if toks[s].after_skip {
                continue;
            }
            let mut h = 0u64;
            for k in 0..MAX_LEN.min(toks.len() - s) {
                let t = &toks[s + k];
                if t.run != toks[s].run {
                    break;
                }
                h = mix(h, t.id);
                if k == 0 {
                    // A single instruction is never worth a call.
                    if t.kind == Kind::Tail {
                        break;
                    }
                    continue;
                }
                let tail = t.kind == Kind::Tail;
                let valid = if tail { toks[s + k - 1].kind != Kind::Skip } else { t.kind != Kind::Skip && allow_plain };
                if valid {
                    cands.entry((h, k + 1)).or_default().push(s);
                }
                if tail {
                    break;
                }
            }
        }
        // The best run: most words saved, counting a call as two words and a `return` as one.
        let mut best: Option<(i64, (u64, usize), Vec<usize>)> = None;
        for (key, starts) in &cands {
            if starts.len() < 2 {
                continue;
            }
            let len = key.1;
            let first = starts[0];
            let w: i64 = toks[first..first + len].iter().map(|t| t.words as i64).sum();
            let tail = toks[first + len - 1].kind == Kind::Tail;
            // Greedy, non-overlapping, and really equal (not just the same hash).
            let mut picked: Vec<usize> = Vec::new();
            for &s in starts {
                if picked.last().is_some_and(|&p| s < p + len) {
                    continue;
                }
                if (0..len).all(|k| toks[s + k].id == toks[first + k].id) {
                    picked.push(s);
                }
            }
            let n = picked.len() as i64;
            let gain = n * (w - 2) - (w + if tail { 0 } else { 1 });
            // Ties go to the longer run, then to the one that starts first, so the output does not depend on the
            // order the map is walked in.
            if gain > 0 && best.as_ref().is_none_or(|b| (gain, len, std::cmp::Reverse(picked[0])) > (b.0, b.1.1, std::cmp::Reverse(b.2[0]))) {
                best = Some((gain, *key, picked));
            }
        }
        let Some((_, key, picked)) = best else { break };
        let len = key.1;
        let name = format!("__PL{}", bodies.len());
        // The body from the first occurrence.
        let first = picked[0];
        let mut body: Vec<Item> = Vec::new();
        for k in 0..len {
            match &cur[toks[first + k].item] {
                Item::Call(t) => body.push(Item::Br(Cc::Always, t.clone())),
                it => body.push(it.clone()),
            }
        }
        if !matches!(body.last(), Some(Item::Br(..))) {
            body.push(Item::Ins("return".into()));
        }
        bodies.push((name.clone(), body));
        // Rebuild: each occurrence becomes `call name`, keeping its line markers.
        let mut start_of: HashMap<usize, usize> = HashMap::new();
        for &s in &picked {
            start_of.insert(toks[s].item, toks[s + len - 1].item);
        }
        let mut out: Vec<Item> = Vec::with_capacity(cur.len());
        let mut i = 0;
        while i < cur.len() {
            if let Some(&end) = start_of.get(&i) {
                for it in &cur[i..=end] {
                    if matches!(it, Item::Comment(t) if t.starts_with("#line ")) {
                        out.push(it.clone());
                    }
                }
                out.push(Item::Call(name.clone()));
                i = end + 1;
            } else {
                out.push(cur[i].clone());
                i += 1;
            }
        }
        cur = out;
    }
    if bodies.is_empty() {
        return items;
    }
    for (name, body) in bodies {
        cur.push(Item::Label(name));
        cur.extend(body);
    }
    if assemble(&cur, 0).words < before { cur } else { items }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ins(s: &str) -> Item {
        Item::Ins(s.to_string())
    }

    fn site(v: u8) -> Vec<Item> {
        vec![ins(&format!("movlw 0x{v:02X}")), ins("movwf A, c"), ins("clrf A+1, c"), ins("movlw 0x01"), ins("movwf B, c")]
    }

    fn words(items: &[Item]) -> u32 {
        assemble(items, 0).words
    }

    #[test]
    fn repeated_run_becomes_a_call() {
        let mut items = vec![Item::Label("main".into())];
        for _ in 0..6 {
            items.extend(site(5));
            items.push(Item::Call("F".into()));
        }
        items.push(Item::Label("F".into()));
        items.push(ins("return"));
        let before = words(&items);
        let out = outline(items, true);
        assert!(words(&out) < before, "{} !< {}", words(&out), before);
        assert!(out.iter().any(|i| matches!(i, Item::Label(l) if l == "__PL0")));
        // The run ends in the call to F, so the block jumps to it and needs no `return` of its own.
        assert!(out.iter().any(|i| matches!(i, Item::Br(Cc::Always, t) if t == "F")));
    }

    #[test]
    fn runs_that_differ_stay_inline() {
        let mut items = vec![Item::Label("main".into())];
        for v in 0..6 {
            items.extend(site(v));
            items.push(Item::Call("F".into()));
        }
        items.push(Item::Label("F".into()));
        items.push(ins("return"));
        // The common tail (everything after the first `movlw`) is still shared.
        let out = outline(items.clone(), true);
        assert!(words(&out) < words(&items));
        assert!(out.iter().filter(|i| matches!(i, Item::Call(t) if t == "__PL0")).count() >= 6);
    }

    #[test]
    fn plain_runs_need_stack_headroom() {
        let mut items = vec![Item::Label("main".into())];
        for _ in 0..6 {
            items.extend(site(5));
            items.push(ins("nop"));
            items.push(Item::Label("x".into()));
            items.push(Item::Br(Cc::Always, "x".into()));
        }
        let none = outline(items.clone(), false);
        assert_eq!(words(&none), words(&items));
        let some = outline(items.clone(), true);
        assert!(words(&some) < words(&items));
    }

    #[test]
    fn labels_branches_and_guards_split_runs() {
        let mut items = vec![Item::Label("main".into())];
        for k in 0..6 {
            items.extend(site(5));
            items.push(Item::Label(format!("l{k}")));
            items.extend(site(5));
            items.push(Item::Br(Cc::Always, "main".into()));
        }
        let out = outline(items, true);
        // No block contains a label or a branch from the middle of a site.
        let at = out.iter().position(|i| matches!(i, Item::Label(l) if l == "__PL0")).unwrap();
        assert!(out[at + 1..].iter().all(|i| !matches!(i, Item::Label(l) if l.starts_with('l'))));
        let mut keep = vec![Item::Keep(true)];
        for _ in 0..6 {
            keep.extend(site(5));
        }
        keep.push(Item::Keep(false));
        assert_eq!(words(&outline(keep.clone(), true)), words(&keep));
    }

    #[test]
    fn skip_rules() {
        // A skip is never the last instruction of a block, and a program counter access is never outlined.
        let mut items = vec![Item::Label("main".into())];
        for _ in 0..6 {
            items.extend(site(5));
            items.push(ins("btfsc PORTA, 0, c"));
            items.push(Item::Label("y".into()));
        }
        let out = outline(items, true);
        if let Some(at) = out.iter().position(|i| matches!(i, Item::Label(l) if l == "__PL0")) {
            let body: Vec<&Item> = out[at + 1..].iter().take_while(|i| !matches!(i, Item::Label(_))).collect();
            assert!(!matches!(body.iter().rev().nth(1), Some(Item::Ins(t)) if t.starts_with("btfsc")));
        }
        let mut pc = vec![Item::Label("main".into())];
        for _ in 0..6 {
            pc.extend(site(5));
            pc.push(ins("addwf PCL, f, c"));
            pc.push(Item::Label("z".into()));
        }
        let o = outline(pc, true);
        let at = o.iter().position(|i| matches!(i, Item::Label(l) if l == "__PL0")).unwrap();
        assert!(o[at..].iter().all(|i| !matches!(i, Item::Ins(t) if t.contains("PCL"))));
        // A run straight after a skip stays where it is (the skip would now jump over the whole call).
        let mut after = vec![Item::Label("main".into())];
        for _ in 0..6 {
            after.push(ins("btfsc PORTA, 0, c"));
            after.extend(site(5));
            after.push(Item::Label("w".into()));
        }
        let o = outline(after, true);
        for w in o.windows(2) {
            if matches!(&w[0], Item::Ins(t) if t.starts_with("btfsc")) {
                assert!(!matches!(&w[1], Item::Call(_)), "a call straight after a skip");
            }
        }
    }
}
