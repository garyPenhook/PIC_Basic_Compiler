//! Page-bit flow for generated CALL/GOTO selections. The caller excludes latch observers,
//! opaque control flow and computed transfers before enabling this analysis.
use super::{Cc, Item};
use crate::fxhash::HashMap;

fn mnemonic(text: &str) -> String {
    text.split_whitespace().next().unwrap_or("").to_ascii_lowercase()
}
fn terminal(it: &Item) -> bool {
    matches!(it, Item::Ins(t) | Item::Raw(t) if matches!(mnemonic(t).as_str(), "return" | "retlw" | "retfie" | "reset"))
}
fn skipped(it: &Item) -> bool {
    matches!(it, Item::Ins(t) | Item::Raw(t) if matches!(mnemonic(t).as_str(), "btfsc" | "btfss" | "decfsz" | "incfsz"))
}
fn relative(it: &Item) -> Option<&str> {
    match it {
        Item::Ins(t) | Item::Raw(t) if mnemonic(t) == "bra" => t.split_whitespace().nth(1),
        _ => None,
    }
}
fn target(it: &Item) -> Option<&str> {
    match it {
        Item::Call(t) | Item::Br(_, t) | Item::SkipBr(_, t) => Some(t),
        _ => None,
    }
}
fn selected(it: &Item, long: bool) -> bool {
    matches!(it, Item::Call(_)) || (long && matches!(it, Item::Br(..) | Item::SkipBr(..)))
}

pub(super) fn selections(items: &[Item], long: &[bool], labels: &HashMap<String, u32>) -> Vec<bool> {
    let n = items.len();
    let mut index = HashMap::default();
    for (i, it) in items.iter().enumerate() {
        match it {
            Item::Label(l) => {
                index.insert(l.as_str(), i);
            }
            Item::Raw(t) if t.trim().ends_with(':') => {
                index.insert(t.trim().trim_end_matches(':'), i);
            }
            _ => {}
        }
    }
    let page = |t: &str| labels.get(t).map(|a| (a >> 11) as i32);
    let edges = |i: usize| -> Vec<usize> {
        let mut out = Vec::new();
        match &items[i] {
            Item::Br(_, t) | Item::SkipBr(_, t) => {
                if let Some(&j) = index.get(t.as_str()) {
                    out.push(j);
                }
            }
            _ => {
                if let Some(t) = relative(&items[i])
                    && let Some(&j) = index.get(t)
                {
                    out.push(j);
                }
            }
        }
        if !terminal(&items[i]) && !matches!(&items[i], Item::Br(Cc::Always, _)) && relative(&items[i]).is_none() {
            if i + 1 < n {
                out.push(i + 1);
            }
            if skipped(&items[i]) {
                if let Some(j) = (i + 1..n).find(|&j| super::size16(&items[j], long[j], true) > 0) {
                    if j + 1 < n {
                        out.push(j + 1);
                    }
                }
            }
        }
        out
    };
    let mut entries: Vec<&str> = items.iter().filter_map(|it| if let Item::Call(t) = it { Some(t.as_str()) } else { None }).collect();
    entries.sort_unstable();
    entries.dedup();
    // Greatest fixed point: a callee preserves its incoming call page only if every
    // selection it can execute, including in transitive callees, selects that same page.
    let mut preserves: HashMap<&str, bool> = entries.iter().map(|&t| (t, true)).collect();
    loop {
        let mut changed = false;
        for &entry in &entries {
            if !preserves[entry] {
                continue;
            }
            let mut seen = vec![false; n];
            let mut todo = index.get(entry).copied().into_iter().collect::<Vec<_>>();
            let mut ok = page(entry).is_some() && !todo.is_empty();
            while let Some(i) = todo.pop() {
                if seen[i] {
                    continue;
                }
                seen[i] = true;
                if selected(&items[i], long[i]) && target(&items[i]).is_none_or(|t| page(t) != page(entry)) {
                    ok = false;
                    break;
                }
                if let Item::Call(t) = &items[i]
                    && !preserves.get(t.as_str()).copied().unwrap_or(false)
                {
                    ok = false;
                    break;
                }
                todo.extend(edges(i));
            }
            if !ok {
                preserves.insert(entry, false);
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    const BOTTOM: i32 = -2;
    const UNKNOWN: i32 = -1;
    let mut at = vec![BOTTOM; n];
    let mut todo = Vec::new();
    fn join(at: &mut [i32], todo: &mut Vec<usize>, i: usize, value: i32) {
        let next = if at[i] == BOTTOM || at[i] == value { value } else { UNKNOWN };
        if at[i] != next {
            at[i] = next;
            todo.push(i);
        }
    }
    if n > 0 {
        join(&mut at, &mut todo, 0, 0);
    }
    for (i, it) in items.iter().enumerate() {
        if matches!(it, Item::Label(l) if l.starts_with("__ISR")) {
            join(&mut at, &mut todo, i, UNKNOWN);
        }
    }
    while let Some(i) = todo.pop() {
        let cur = at[i];
        if let Item::Call(t) = &items[i] {
            let p = page(t).unwrap_or(UNKNOWN);
            if let Some(&j) = index.get(t.as_str()) {
                join(&mut at, &mut todo, j, p);
            }
            if i + 1 < n {
                join(&mut at, &mut todo, i + 1, if preserves.get(t.as_str()).copied().unwrap_or(false) { p } else { UNKNOWN });
            }
        } else {
            if matches!(&items[i], Item::Br(cc, _) if *cc != Cc::Always) || matches!(&items[i], Item::SkipBr(..)) {
                if i + 1 < n {
                    join(&mut at, &mut todo, i + 1, cur);
                }
            }
            for j in edges(i) {
                let taken = matches!(&items[i], Item::Br(_, t) | Item::SkipBr(_, t) if index.get(t.as_str()) == Some(&j));
                let value = if taken && selected(&items[i], long[i]) { target(&items[i]).and_then(page).unwrap_or(UNKNOWN) } else { cur };
                join(&mut at, &mut todo, j, value);
            }
        }
    }
    items.iter().enumerate().map(|(i, it)| selected(it, long[i]) && (at[i] < 0 || target(it).and_then(page) != Some(at[i]))).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn label(s: &str) -> Item {
        Item::Label(s.into())
    }
    fn call(s: &str) -> Item {
        Item::Call(s.into())
    }
    fn ins(s: &str) -> Item {
        Item::Ins(s.into())
    }
    fn labs() -> HashMap<String, u32> {
        [("A", 10), ("B", 2050), ("JOIN", 20), ("END", 25)].into_iter().map(|(s, a)| (s.into(), a)).collect()
    }
    #[test]
    fn calls_preserve_latch_not_program_counter_page() {
        let items = vec![call("A"), call("B"), call("B"), call("A"), ins("return"), label("A"), ins("nop"), ins("return"), label("B"), ins("return")];
        assert_eq!(selections(&items, &vec![false; items.len()], &labs())[..4], [false, true, false, true]);
    }
    #[test]
    fn cross_page_callees_do_not_restore_the_callers_latch() {
        let items = vec![call("A"), call("A"), ins("return"), label("A"), call("B"), ins("return"), label("B"), ins("return")];
        let pages = selections(&items, &vec![false; items.len()], &labs());
        assert!(!pages[0]);
        assert!(pages[1]);
        assert!(pages[4]);
    }
    #[test]
    fn joins_and_skips_include_the_unselected_path_with_zero_word_metadata() {
        let items =
            vec![Item::Br(Cc::Z, "JOIN".into()), call("B"), label("JOIN"), call("A"), ins("return"), label("A"), ins("return"), label("B"), ins("return")];
        assert!(selections(&items, &vec![false; items.len()], &labs())[3]);
        let items = vec![
            ins("btfsc STATUS, 0"),
            Item::Fence,
            label("JOIN"),
            ins("bra END"),
            call("B"),
            label("END"),
            call("A"),
            ins("return"),
            label("A"),
            ins("return"),
            label("B"),
            ins("return"),
        ];
        assert!(selections(&items, &vec![false; items.len()], &labs())[6]);
    }
    #[test]
    fn assembler_recomputes_layout_after_removing_page_selections() {
        let items = vec![call("A"), call("B"), call("B"), call("A"), ins("return"), label("A"), ins("return"), Item::Org(2048), label("B"), ins("return")];
        let baseline = crate::asm::assemble16(&items, 0, true);
        let result = crate::asm::assemble16_tracked(&items, 0);
        assert_eq!(result.lines.iter().filter(|l| l.contains("movlp")).count(), 2);
        assert_eq!(baseline.lines.iter().filter(|l| l.contains("movlp")).count(), 4);
        assert_eq!(result.labels["A"], 7);
        assert_eq!(result.labels["B"], 2048);
    }
    #[test]
    fn page_boundary_moves_are_rechecked_and_interrupt_entries_are_unknown() {
        let mut items = vec![call("A"), call("A")];
        items.extend((0..2044).map(|_| ins("nop")));
        items.extend([label("A"), ins("return")]);
        let result = crate::asm::assemble16_tracked(&items, 0);
        assert_eq!(result.labels["A"], 2046);
        assert!(!result.lines.iter().any(|l| l.contains("movlp")));
        let items = vec![ins("return"), label("__ISR_H"), call("A"), ins("retfie"), label("A"), ins("return")];
        assert!(selections(&items, &vec![false; items.len()], &labs())[2]);
    }
    #[test]
    fn long_conditional_and_counted_branches_change_only_the_taken_path() {
        for branch in [Item::Br(Cc::Z, "B".into()), Item::SkipBr("decfsz __A0, f".into(), "B".into())] {
            let items = vec![branch, call("A"), ins("return"), label("A"), ins("return"), label("B"), ins("return")];
            let mut long = vec![false; items.len()];
            long[0] = true;
            let pages = selections(&items, &long, &labs());
            assert!(pages[0]);
            assert!(!pages[1]);
        }
    }
}
