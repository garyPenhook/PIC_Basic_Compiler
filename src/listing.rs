//! A readable listing (`.lst`) made from the generated assembly (`.S`).
//!
//! The `.S` file is what pic-as reads, so it carries things a person does not want to read: a `#line` before every
//! instruction of a debug build, long mangled names, one `PSECT` per variable. The listing drops all of that and
//! shows what is useful: the BASIC statement above the instructions it became, the word address of every
//! instruction, the BASIC names of the variables, and a RAM map and a size per routine.

use crate::asm::{words_of, words_of16};
use std::collections::{HashMap, HashSet};

struct Var {
    addr: u32,
    bytes: u32,
    name: String,
}

/// Instruction addresses are printed in bytes for the 18F (the unit of the map file and the debugger), in words for
/// the 16F.
pub fn listing(asm: &str, lookup: &dyn Fn(&str, u32) -> Option<String>) -> String {
    let enhanced = asm.contains("delta=2");
    let relocatable = asm.contains("reloc=");
    let unit: u32 = if enhanced { 1 } else { 2 };
    let words = |t: &str| if enhanced { words_of16(t) } else { words_of(t) };
    let device = asm.lines().next().and_then(|l| l.strip_prefix("; basil output for ")).unwrap_or("").trim();

    let mut config: Vec<String> = Vec::new();
    let mut vars: Vec<Var> = Vec::new();
    let mut aliases: Vec<(String, String)> = Vec::new(); // mangled -> BASIC name
    let mut scratch: Vec<(String, u32, u32)> = Vec::new(); // register letter, address, bytes
    let mut other: Vec<(String, u32)> = Vec::new();
    let mut code: Vec<&str> = Vec::new();

    // The data section, up to the code's PSECT.
    let mut in_code = false;
    let (mut org, mut first_global): (u32, Option<String>) = (0, None);
    for l in asm.lines() {
        if in_code {
            code.push(l);
            continue;
        }
        let t = l.trim();
        if let Some(rest) = t.strip_prefix("CONFIG ") {
            if let Some((n, v)) = rest.split_once('=') {
                config.push(format!("{}={}", n.trim(), v.trim()));
            }
        } else if t.starts_with("PSECT code,") || t.starts_with("PSECT basilcode,") {
            in_code = true;
        } else if let Some(r) = t.strip_prefix("ORG ") {
            org = parse_num(r).unwrap_or(0);
        } else if let Some(r) = t.strip_prefix("GLOBAL ") {
            first_global.get_or_insert_with(|| r.trim().to_string());
        } else if let Some(r) = t.strip_prefix("DS ") {
            // A debug build: `DS n  ; name (n bytes)`.
            let (n, note) = r.split_once(';').map_or((r, ""), |(a, b)| (a, b));
            let bytes = n.trim().parse().unwrap_or(1);
            let name = note.trim().split(" (").next().unwrap_or("").to_string();
            if let Some(m) = first_global.take() {
                if !name.is_empty() {
                    aliases.push((m, name.clone()));
                }
            }
            vars.push(Var { addr: org, bytes, name });
        } else if let Some((name, rest)) = t.split_once(" equ ") {
            let (a, note) = rest.split_once(';').map_or((rest, ""), |(a, b)| (a, b));
            let addr = parse_num(a).unwrap_or(0);
            let basic = note.trim().split(" (").next().unwrap_or("").to_string();
            let bytes = note.split('(').nth(1).and_then(|s| s.split_whitespace().next()).and_then(|n| n.parse().ok());
            if let (Some(c), true) = (scratch_letter(name), name.starts_with("__")) {
                match scratch.iter_mut().find(|s| s.0 == c) {
                    Some(s) => {
                        s.1 = s.1.min(addr);
                        s.2 += 1;
                    }
                    None => scratch.push((c, addr, 1)),
                }
            } else if !basic.is_empty() {
                aliases.push((name.to_string(), basic.clone()));
                vars.push(Var { addr, bytes: bytes.unwrap_or(1), name: basic });
            } else {
                other.push((name.to_string(), addr));
            }
        }
    }

    // BASIC names stand in for the mangled ones, unless two variables (locals of different routines) share one.
    let mut seen: HashMap<&str, u32> = HashMap::new();
    for (_, b) in &aliases {
        *seen.entry(b.as_str()).or_default() += 1;
    }
    let reserved: HashSet<&str> = ["a", "b", "c", "f", "w", "z", "n", "ov", "dc", "wreg", "fast", "access", "banked"].into();
    let rename: HashMap<&str, &str> = aliases
        .iter()
        .filter(|(m, b)| m != b && seen[b.as_str()] == 1 && !reserved.contains(b.to_ascii_lowercase().as_str()))
        .map(|(m, b)| (m.as_str(), b.as_str()))
        .collect();

    // The code, one row per line: address, text, and which BASIC line it belongs to.
    enum Row {
        Banner(String),
        Src(String),
        Note(String),
        Label(u32, String),
        Ins(u32, String),
    }
    let mut rows: Vec<Row> = Vec::new();
    let mut pc: u32 = 0;
    let mut cur: Option<(String, u32)> = None;
    let mut shown: Option<(String, u32)> = None;
    let mut routines: Vec<(String, u32)> = vec![("(start-up and program body)".into(), 0)]; // name, start (in words)
    let mut pending_banner: Option<String> = None;
    for l in code {
        let t = l.trim();
        if t.is_empty() || t.starts_with(";SYM ") || t.starts_with("END") || t.starts_with("GLOBAL ") {
            continue;
        }
        if let Some(r) = t.strip_prefix("#line ") {
            let (n, f) = r.split_once(' ').unwrap_or((r, ""));
            cur = Some((f.trim().trim_matches('"').to_string(), n.parse().unwrap_or(0)));
            continue;
        }
        if let Some(r) = t.strip_prefix("ORG ") {
            pc = parse_num(r).unwrap_or(pc) / unit;
            if pc != 0 {
                rows.push(Row::Banner(format!("at 0x{:04X}", pc * unit)));
            }
            continue;
        }
        if t.starts_with("PSECT ") {
            rows.push(Row::Banner(t.split([' ', ',']).nth(1).unwrap_or("").to_string()));
            continue;
        }
        if let Some(c) = t.strip_prefix(';') {
            let c = c.trim();
            if c.starts_with("Sub/Function ") || c.starts_with("helper ") || c.starts_with("Interrupt ") {
                pending_banner = Some(c.to_string());
            } else if c != "warg" {
                rows.push(Row::Note(c.to_string()));
            }
            continue;
        }
        if t.ends_with(':') && !t.contains(' ') {
            let name = t.trim_end_matches(':');
            if let Some(b) = pending_banner.take() {
                routines.push((b.clone(), pc));
                rows.push(Row::Banner(b));
            } else if !name.starts_with("_L") && !name.starts_with("__skip") && !name.starts_with("__") {
                routines.push((name.to_string(), pc));
            }
            rows.push(Row::Label(pc, name.to_string()));
            continue;
        }
        // An instruction. Show its BASIC statement the first time a line is met.
        if cur != shown {
            if let Some((f, n)) = &cur {
                let text = lookup(f, *n).unwrap_or_default();
                let file = f.rsplit('/').next().unwrap_or(f);
                rows.push(Row::Src(format!("{file}:{n}  {}", text.trim())));
            }
            shown = cur.clone();
        }
        let (m, ops) = t.split_once(char::is_whitespace).map_or((t, ""), |(a, b)| (a, b.trim()));
        let ops = replace_names(ops, &rename);
        rows.push(Row::Ins(pc, if ops.is_empty() { m.to_string() } else { format!("{m:<7} {ops}") }));
        pc += words(t);
    }

    let mut out = String::new();
    let bytes = pc * unit;
    out.push_str(&if enhanced { format!("; {device}   {pc} words\n") } else { format!("; {device}   {pc} words ({bytes} bytes)\n") });
    if !config.is_empty() {
        out.push_str(";\n; config:");
        let mut width = 9;
        for c in &config {
            if width + c.len() + 1 > 78 {
                out.push_str("\n;       ");
                width = 9;
            }
            out.push_str(&format!(" {c}"));
            width += c.len() + 1;
        }
        out.push('\n');
    }
    if !vars.is_empty() || !scratch.is_empty() || !other.is_empty() {
        out.push_str(";\n; RAM\n");
        let mut all: Vec<(u32, String, String)> = Vec::new();
        for v in &vars {
            all.push((v.addr, format!("{:>2}", v.bytes), v.name.clone()));
        }
        for (c, a, n) in &scratch {
            all.push((*a, format!("{n:>2}"), format!("__{c}  (compiler scratch)")));
        }
        for (n, a) in &other {
            all.push((*a, "  ".into(), n.clone()));
        }
        all.sort();
        for (a, n, name) in all {
            out.push_str(&format!(";   0x{a:03X}  {n}  {name}\n"));
        }
    }
    if routines.len() > 1 {
        out.push_str(";\n; routines (words)\n");
        let mut ends: Vec<u32> = routines.iter().map(|r| r.1).collect();
        ends.push(pc);
        for (i, (n, s)) in routines.iter().enumerate() {
            let size = ends[i + 1].saturating_sub(*s);
            let a = if relocatable { String::new() } else { format!("0x{:04X}  ", s * unit) };
            out.push_str(&format!(";   {a}{size:>4}  {n}\n"));
        }
    }
    out.push_str(";\n");
    for r in rows {
        match r {
            Row::Banner(b) => out.push_str(&format!("\n; ---- {b}\n")),
            Row::Note(s) => out.push_str(&format!("          ; {s}\n")),
            Row::Src(s) => out.push_str(&format!("\n      ; {s}\n")),
            Row::Label(a, n) if relocatable => {
                let _ = a;
                out.push_str(&format!("      {n}:\n"));
            }
            Row::Label(a, n) => out.push_str(&format!("{:04X}  {n}:\n", a * unit)),
            Row::Ins(a, t) if relocatable => {
                let _ = a;
                out.push_str(&format!("          {t}\n"));
            }
            Row::Ins(a, t) => out.push_str(&format!("{:04X}      {t}\n", a * unit)),
        }
    }
    out
}

fn parse_num(s: &str) -> Option<u32> {
    let s = s.trim();
    match s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")) {
        Some(h) => u32::from_str_radix(h, 16).ok(),
        None => s.parse().ok(),
    }
}

/// `__A0` -> `A`: the compiler's scratch registers.
fn scratch_letter(name: &str) -> Option<String> {
    let r = name.strip_prefix("__")?;
    let (l, d) = r.split_at(1);
    (matches!(l, "A" | "B" | "C" | "D") && !d.is_empty() && d.chars().all(|c| c.is_ascii_digit())).then(|| l.to_string())
}

/// Replace whole identifiers found in `map`.
fn replace_names(text: &str, map: &HashMap<&str, &str>) -> String {
    let mut out = String::with_capacity(text.len());
    let mut word = String::new();
    let flush = |word: &mut String, out: &mut String| {
        if !word.is_empty() {
            out.push_str(map.get(word.as_str()).copied().unwrap_or(word.as_str()));
            word.clear();
        }
    };
    for c in text.chars() {
        if c.is_ascii_alphanumeric() || c == '_' {
            word.push(c);
        } else {
            flush(&mut word, &mut out);
            out.push(c);
        }
    }
    flush(&mut word, &mut out);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_noise_is_dropped_and_names_are_the_basic_ones() {
        let asm = "; basil output for PIC18F27Q10\n#include <xc.inc>\n\nCONFIG CONFIG1L = 0xFF\n\n; ---- data\nPSECT dbg0,class=RAM,space=1,abs,delta=1,noexec\n    ORG 0x024\nGLOBAL PROG_X\nPROG_X:\nGLOBAL X\nX:\nDS 1  ; X (1 byte)\n__A0 equ 0x000\n__A1 equ 0x001\n\nPSECT code,class=CODE,abs,delta=1\n    ORG 0x0000\n__reset:\n#line 3 \"/p/m.bas\"\n    movlw 0x0A\n#line 3 \"/p/m.bas\"\n    movwf PROG_X, c\n__halt:\n    bra __halt\n;SYM __halt 0x0004\n    END __reset\n";
        let l = listing(asm, &|_, n| Some(format!("line {n} text")));
        assert!(!l.contains("#line"));
        assert!(!l.contains("PROG_X"));
        assert!(l.contains("0002      movwf   X, c"));
        assert_eq!(l.matches("m.bas:3").count(), 1);
        assert!(l.contains("0x024   1  X"));
        assert!(l.contains("__A  (compiler scratch)"));
    }
}
