//! Line-based preprocessor: `#define`, `#undefine`, `#ifdef`, `#ifndef`, `#else`, `#endif`,
//! `#error`, `#warning`, `#option`. Removed lines are replaced by empty lines so that line
//! numbers in later diagnostics stay correct. `#if`, `#elseif`, `#constant` and `#variable` need
//! a compile-time expression evaluator and are reported as unsupported for now.

use crate::diag::{Diagnostics, Span};
use std::collections::HashSet;

#[derive(Debug, Clone)]
pub struct OptionDirective {
    pub name: String,
    pub value: String,
    pub span: Span,
}

pub struct Preprocessed {
    pub text: String,
    pub options: Vec<OptionDirective>,
}

struct Cond {
    /// The enclosing region is active.
    parent: bool,
    /// Some branch of this conditional has already been taken.
    taken: bool,
    active: bool,
    seen_else: bool,
}

/// True for a line that starts an assembler block (`Asm` ...), whose body is passed through raw.
fn starts_asm(code: &str) -> bool {
    let low = code.trim_start().to_ascii_lowercase();
    low == "asm" || (low.starts_with("asm") && !low.as_bytes()[3].is_ascii_alphanumeric() && low.as_bytes()[3] != b'_')
}

/// Updates the open-comment stack for one line, ignoring text in strings and after `'` or `//`.
fn scan_block_comments(line: &str, blocks: &mut Vec<u8>) {
    let b = line.as_bytes();
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        let c = b[i];
        match blocks.last() {
            Some(b'(') if c == b'*' && b.get(i + 1) == Some(&b')') => {
                blocks.pop();
                i += 2;
                continue;
            }
            Some(b'{') if c == b'}' => {
                blocks.pop();
                i += 1;
                continue;
            }
            _ => {}
        }
        if c == b'(' && b.get(i + 1) == Some(&b'*') {
            blocks.push(b'(');
            i += 2;
            continue;
        }
        if c == b'{' {
            blocks.push(b'{');
        } else if blocks.is_empty() {
            if c == b'"' {
                in_str = !in_str;
            } else if !in_str && (c == b'\'' || (c == b'/' && b.get(i + 1) == Some(&b'/'))) {
                break;
            }
        }
        i += 1;
    }
}

fn ends_asm(code: &str) -> bool {
    let low = code.trim().to_ascii_lowercase();
    let mut words = low.split(|c: char| c.is_whitespace() || c == '\'').filter(|w| !w.is_empty());
    words.next() == Some("end") && words.next() == Some("asm")
}

pub fn preprocess(file: u32, src: &str, defined: &mut HashSet<String>, diags: &mut Diagnostics) -> Preprocessed {
    let mut out = String::with_capacity(src.len());
    let mut options = Vec::new();
    let mut stack: Vec<Cond> = Vec::new();
    let mut in_asm = false;
    // Open block comments, innermost last: b'(' for `(*`, b'{' for `{`.
    let mut blocks: Vec<u8> = Vec::new();
    for (i, line) in src.lines().enumerate() {
        let span = Span { file, line: (i + 1) as u32, col: 1 };
        let active = stack.last().map(|c| c.active).unwrap_or(true);
        let trimmed = line.trim_start();
        let was_in_comment = !blocks.is_empty();
        if !in_asm {
            scan_block_comments(line, &mut blocks);
        }
        // Text inside a block comment is not code, so a directive there is not executed.
        let directive = if was_in_comment { None } else { trimmed.strip_prefix('#') };
        let directive = directive.filter(|r| r.chars().next().is_some_and(|c| c.is_ascii_alphabetic()));
        if in_asm {
            if ends_asm(line) {
                in_asm = false;
            }
            out.push_str(if active { line } else { "" });
            out.push('\n');
            continue;
        }
        let Some(rest) = directive else {
            if active && starts_asm(line) {
                in_asm = true;
            }
            out.push_str(if active { line } else { "" });
            out.push('\n');
            continue;
        };
        let rest = rest.split('\'').next().unwrap_or("").trim_end();
        let (name, arg) = match rest.find(char::is_whitespace) {
            Some(p) => (&rest[..p], rest[p..].trim()),
            None => (rest, ""),
        };
        let lname = name.to_ascii_lowercase();
        let key = arg.split_whitespace().next().unwrap_or("").to_ascii_lowercase();
        match lname.as_str() {
            "ifdef" | "ifndef" => {
                if key.is_empty() {
                    diags.error("E-PP", span, format!("#{lname} needs a name"));
                }
                let cond = defined.contains(&key) == (lname == "ifdef");
                stack.push(Cond { parent: active, taken: cond && active, active: cond && active, seen_else: false });
            }
            "else" => match stack.last_mut() {
                Some(c) if !c.seen_else => {
                    c.seen_else = true;
                    c.active = c.parent && !c.taken;
                    c.taken = true;
                }
                Some(_) => diags.error("E-PP", span, "#else after #else"),
                None => diags.error("E-PP", span, "#else without #ifdef/#ifndef"),
            },
            "endif" => {
                if stack.pop().is_none() {
                    diags.error("E-PP", span, "#endif without #ifdef/#ifndef");
                }
            }
            "if" | "elseif" | "constant" | "variable" => {
                if active || lname == "elseif" {
                    diags.error("E-PP-UNSUPPORTED", span, format!("#{lname} is not implemented yet (needs the compile-time expression evaluator)"));
                }
                if lname == "if" {
                    stack.push(Cond { parent: active, taken: false, active: false, seen_else: false });
                }
            }
            _ if !active => {}
            "define" => {
                if key.is_empty() {
                    diags.error("E-PP", span, "#define needs a name");
                } else {
                    defined.insert(key);
                }
            }
            "undefine" => {
                defined.remove(&key);
            }
            "error" => diags.error("E-PP-ERROR", span, format!("#error {arg}")),
            "warning" => diags.warn("W-PP-WARNING", span, format!("#warning {arg}")),
            "option" => match arg.split_once('=') {
                Some((n, v)) if !n.trim().is_empty() && !v.trim().is_empty() => {
                    options.push(OptionDirective { name: n.trim().to_ascii_lowercase(), value: v.trim().to_ascii_lowercase(), span });
                }
                _ => diags.error("E-PP", span, "#option needs the form `#option Name = value`"),
            },
            _ => diags.error("E-PP", span, format!("unknown directive #{name}")),
        }
        out.push('\n');
    }
    if !stack.is_empty() {
        diags.error("E-PP", Span { file, line: src.lines().count() as u32, col: 1 }, "#ifdef/#ifndef without #endif");
    }
    Preprocessed { text: out, options }
}
