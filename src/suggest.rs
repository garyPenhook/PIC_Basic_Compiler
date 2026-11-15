//! "Did you mean" suggestions: the closest names to a misspelt one.

/// Edit distance between `a` and `b`, ignoring ASCII case: insertions, deletions,
/// substitutions and swaps of two neighbouring characters each cost one.
pub fn distance(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().map(|c| c.to_ascii_lowercase()).collect();
    let b: Vec<char> = b.chars().map(|c| c.to_ascii_lowercase()).collect();
    let (n, m) = (a.len(), b.len());
    let mut d = vec![vec![0usize; m + 1]; n + 1];
    for (i, row) in d.iter_mut().enumerate() {
        row[0] = i;
    }
    for j in 0..=m {
        d[0][j] = j;
    }
    for i in 1..=n {
        for j in 1..=m {
            let cost = usize::from(a[i - 1] != b[j - 1]);
            let mut v = (d[i - 1][j] + 1).min(d[i][j - 1] + 1).min(d[i - 1][j - 1] + cost);
            if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                v = v.min(d[i - 2][j - 2] + 1);
            }
            d[i][j] = v;
        }
    }
    d[n][m]
}

/// The largest distance still worth suggesting for a name of `len` characters: one slip in a
/// short name, two in a medium one, three in a long one.
fn limit(len: usize) -> usize {
    match len {
        0..=2 => 0,
        3..=4 => 1,
        5..=8 => 2,
        _ => 3,
    }
}

/// The candidates closest to `name` (at most three, best first, earlier candidates first among
/// equals, in the spelling the candidate gives), or none when nothing is close enough.
pub fn closest<'a>(name: &str, candidates: impl IntoIterator<Item = &'a str>) -> Vec<String> {
    let max = limit(name.chars().count());
    if max == 0 {
        return Vec::new();
    }
    let mut best: Vec<(usize, String)> = Vec::new();
    for c in candidates {
        // The name itself is never offered. One that differs only in case is: a lookup that
        // ignores case has found it already, and one that does not (a file name) wants it.
        if c.is_empty() || c == name {
            continue;
        }
        // Cheap length filter before the full table.
        if c.chars().count().abs_diff(name.chars().count()) > max {
            continue;
        }
        let d = distance(name, c);
        if d <= max && !best.iter().any(|(_, b)| b.eq_ignore_ascii_case(c)) {
            best.push((d, c.to_string()));
        }
    }
    // Stable: among equally close names the caller's order (its own names before registers) wins.
    best.sort_by_key(|b| b.0);
    let Some(top) = best.first().map(|b| b.0) else { return Vec::new() };
    // Only the nearest distance: `countr` offers `counter`, not also `count1` two edits away.
    best.into_iter().filter(|b| b.0 == top).take(3).map(|b| b.1).collect()
}

/// `did you mean `a`?` / `did you mean `a` or `b`?`, or `None` with no suggestion.
pub fn did_you_mean(found: &[String]) -> Option<String> {
    match found {
        [] => None,
        [a] => Some(format!("did you mean `{a}`?")),
        [rest @ .., last] => Some(format!("did you mean {} or `{last}`?", rest.iter().map(|s| format!("`{s}`")).collect::<Vec<_>>().join(", "))),
    }
}

/// The usual spelling of a reserved word or built-in name given in lower case (`delayms` is
/// `DelayMS`); other words get a capital first letter.
pub fn pretty(lower: &str) -> String {
    const SPELT: &[(&str, &str)] = &[
        ("addressof", "AddressOf"),
        ("bitof", "BitOf"),
        ("byref", "ByRef"),
        ("byrefconst", "ByRefConst"),
        ("byval", "ByVal"),
        ("delayms", "DelayMS"),
        ("delayus", "DelayUS"),
        ("elseif", "ElseIf"),
        ("endif", "EndIf"),
        ("endselect", "EndSelect"),
        ("endproc", "EndProc"),
        ("exitproc", "ExitProc"),
        ("gosub", "GoSub"),
        ("goto", "GoTo"),
        ("longint", "LongInt"),
        ("longword", "LongWord"),
        ("shortint", "ShortInt"),
        ("noinline", "NoInline"),
        ("sizeof", "SizeOf"),
        ("pinmode", "PinMode"),
        ("pinset", "PinSet"),
        ("pinclear", "PinClear"),
        ("pinpullup", "PinPullUp"),
        ("toupper", "ToUpper"),
        ("tolower", "ToLower"),
        ("clrwdt", "ClrWdt"),
        ("left$", "Left$"),
        ("mid$", "Mid$"),
        ("right$", "Right$"),
        ("str$", "Str$"),
    ];
    if let Some((_, s)) = SPELT.iter().find(|(k, _)| *k == lower) {
        return (*s).to_string();
    }
    let mut c = lower.chars();
    match c.next() {
        Some(f) => format!("{}{}", f.to_ascii_uppercase(), c.as_str()),
        None => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distances() {
        assert_eq!(distance("countr", "counter"), 1);
        assert_eq!(distance("Bytee", "byte"), 1);
        assert_eq!(distance("Wrod", "Word"), 1);
        assert_eq!(distance("abc", "abc"), 0);
        assert_eq!(distance("", "abc"), 3);
    }

    #[test]
    fn suggestions() {
        let c = ["counter", "count", "Byte", "Word", "PORTB", "LATB"];
        assert_eq!(closest("countr", c), vec!["counter".to_string(), "count".to_string()]);
        assert_eq!(closest("Bytee", c), vec!["Byte".to_string()]);
        assert_eq!(closest("PROTB", c), vec!["PORTB".to_string()]);
        assert!(closest("zzzzzz", c).is_empty());
        // Too short to guess at.
        assert!(closest("q", c).is_empty());
        assert_eq!(did_you_mean(&["a".into(), "b".into()]).unwrap(), "did you mean `a` or `b`?");
        assert_eq!(pretty("delayms"), "DelayMS");
        assert_eq!(pretty("next"), "Next");
    }
}
