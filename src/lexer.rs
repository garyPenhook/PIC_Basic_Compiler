//! Lexer. Keywords are case-insensitive (D10); identifiers keep their written spelling.

use crate::diag::{Diagnostics, Span};

#[derive(Clone, Debug, PartialEq)]
pub enum Tok {
    Int(u64),
    Float(f64),
    Str(String),
    /// `#13`: a Char by code.
    CharCode(u32),
    Ident(String),
    /// A reserved word, lower-cased.
    Kw(&'static str),
    Punct(&'static str),
    Colon,
    Newline,
    /// The raw body lines of an `Asm` block, passed through untouched.
    RawAsm(Vec<String>),
    Eof,
}

#[derive(Clone, Debug)]
pub struct Token {
    pub tok: Tok,
    pub span: Span,
}

/// Reserved words: the list in `GRAMMAR.md` plus the alternative spellings of `LANGUAGE.md` §14.
pub const KEYWORDS: &[&str] = &[
    "absolute", "access", "addressof", "and", "as", "asm", "bit", "bitof", "boolean", "bound", "break", "byref",
    "byrefconst", "byte", "byval", "case", "char", "clear", "clock", "compound", "config", "const", "continue", "dec",
    "delayms", "delayus", "device", "dim", "disable", "else", "elseif", "enable", "end", "endif", "endselect", "event",
    "exit", "false", "float", "for", "function", "goto", "high", "if", "inc", "include", "inline", "input", "integer",
    "interrupt", "longint", "longword", "low", "mod", "module", "next", "noinline", "not", "null", "or", "output",
    "private", "program", "public", "reentrant", "repeat", "restore", "result", "save", "select", "shortint", "static", "step",
    "string", "structure", "sub", "terminate", "then", "to", "toggle", "true", "type", "until", "volatile", "wend", "while",
    "word", "xor", // alternative-spelling aliases
    "declare", "do", "endproc", "exitproc", "loop", "proc", "symbol",
];

/// Alternative type names, read as the native type of the same width and signedness (`LANGUAGE.md` §14).
const TYPE_ALIASES: &[(&str, &str)] = &[("sbyte", "shortint"), ("sword", "integer"), ("dword", "longword"), ("long", "longint")];

pub fn keyword(lower: &str) -> Option<&'static str> {
    let lower = TYPE_ALIASES.iter().find(|(a, _)| *a == lower).map_or(lower, |(_, k)| k);
    KEYWORDS.iter().find(|k| **k == lower).copied()
}

/// Reserved words that name an intrinsic or a conversion and so can head a designator
/// (`Inc(x)`, `Byte(x)`).
pub const CALLABLE_KEYWORDS: &[&str] = &[
    "addressof", "bitof", "bound", "clear", "dec", "delayms", "delayus", "high", "inc", "input", "low", "output",
    "terminate", "toggle", "byte", "word", "integer", "longword", "longint", "shortint", "boolean", "bit", "float",
    "char", "string",
];

/// True when `line` closes an `Asm` block (`End Asm`, optionally followed by a comment).
pub fn is_end_asm(line: &str) -> bool {
    let low = line.trim().to_ascii_lowercase();
    let mut words = low.split(|c: char| c.is_whitespace() || c == '\'').filter(|w| !w.is_empty());
    words.next() == Some("end") && words.next() == Some("asm")
}

/// `0x` / `0b` at `i` followed by at least one digit of that radix.
fn prefixed_radix(chars: &[char], i: usize) -> Option<(u32, fn(char) -> bool)> {
    let (radix, ok): (u32, fn(char) -> bool) = match chars.get(i + 1)? {
        'x' | 'X' => (16, |d| d.is_ascii_hexdigit()),
        'b' | 'B' => (2, |d| d == '0' || d == '1'),
        _ => return None,
    };
    (chars.get(i) == Some(&'0') && chars.get(i + 2).is_some_and(|d| ok(*d))).then_some((radix, ok))
}

pub fn lex(file: u32, src: &str, diags: &mut Diagnostics) -> Vec<Token> {
    let chars: Vec<char> = src.chars().collect();
    let mut toks: Vec<Token> = Vec::new();
    let (mut i, mut line, mut col) = (0usize, 1u32, 1u32);
    let mut asm_pending = false;
    let mut block_depth: Vec<(char, Span)> = Vec::new();

    macro_rules! span {
        () => {
            Span { file, line, col }
        };
    }
    macro_rules! adv {
        () => {{
            if chars[i] == '\n' {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
            i += 1;
        }};
    }

    while i < chars.len() {
        let c = chars[i];
        let sp = span!();
        // Inside a block comment.
        if let Some(&(open, osp)) = block_depth.last() {
            if c == '*' && chars.get(i + 1) == Some(&')') && open == '(' {
                adv!();
                adv!();
                block_depth.pop();
            } else if c == '}' && open == '{' {
                adv!();
                block_depth.pop();
            } else if c == '(' && chars.get(i + 1) == Some(&'*') {
                block_depth.push(('(', sp));
                adv!();
                adv!();
            } else if c == '{' {
                block_depth.push(('{', sp));
                adv!();
            } else {
                adv!();
            }
            let _ = osp;
            continue;
        }
        match c {
            ' ' | '\t' | '\r' => adv!(),
            '\n' => {
                adv!();
                toks.push(Token { tok: Tok::Newline, span: sp });
                if asm_pending {
                    asm_pending = false;
                    // Collect raw lines up to (not including) the `End Asm` line.
                    let start = span!();
                    let mut lines = Vec::new();
                    let mut closed = false;
                    while i < chars.len() {
                        let mut j = i;
                        while j < chars.len() && chars[j] != '\n' {
                            j += 1;
                        }
                        let text: String = chars[i..j].iter().collect();
                        if is_end_asm(&text) {
                            closed = true;
                            break;
                        }
                        lines.push(text.trim_end_matches('\r').to_string());
                        while i < j {
                            adv!();
                        }
                        if i < chars.len() {
                            adv!();
                        }
                    }
                    if !closed {
                        diags.error("E-LEX", start, "Asm block is not closed by `End Asm`");
                    }
                    toks.push(Token { tok: Tok::RawAsm(lines), span: start });
                }
            }
            '\'' => {
                while i < chars.len() && chars[i] != '\n' {
                    adv!();
                }
            }
            '/' if chars.get(i + 1) == Some(&'/') => {
                while i < chars.len() && chars[i] != '\n' {
                    adv!();
                }
            }
            '(' if chars.get(i + 1) == Some(&'*') => {
                block_depth.push(('(', sp));
                adv!();
                adv!();
            }
            '{' => {
                block_depth.push(('{', sp));
                adv!();
            }
            '_' if (i == 0 || chars[i - 1] == ' ' || chars[i - 1] == '\t') && continuation(&chars, i) => {
                // Line continuation: skip to and past the newline.
                while i < chars.len() && chars[i] != '\n' {
                    adv!();
                }
                if i < chars.len() {
                    adv!();
                }
            }
            c if c.is_ascii_alphabetic() || c == '_' => {
                let st = i;
                while i < chars.len() && (chars[i].is_ascii_alphanumeric() || chars[i] == '_') {
                    adv!();
                }
                let word: String = chars[st..i].iter().collect();
                let low = word.to_ascii_lowercase();
                match keyword(&low) {
                    Some(k) => {
                        let at_start = matches!(toks.last().map(|t| &t.tok), None | Some(Tok::Newline) | Some(Tok::Colon));
                        if k == "asm" && at_start {
                            asm_pending = true;
                        }
                        toks.push(Token { tok: Tok::Kw(k), span: sp });
                    }
                    None => toks.push(Token { tok: Tok::Ident(word), span: sp }),
                }
            }
            '0' if prefixed_radix(&chars, i).is_some() => {
                let (radix, ok) = prefixed_radix(&chars, i).unwrap();
                adv!();
                adv!();
                let st = i;
                while i < chars.len() && ok(chars[i]) {
                    adv!();
                }
                let text: String = chars[st..i].iter().collect();
                match u64::from_str_radix(&text, radix) {
                    Ok(v) => toks.push(Token { tok: Tok::Int(v), span: sp }),
                    Err(_) => diags.error("E-LEX", sp, format!("integer `0{}{text}` is too large", if radix == 16 { 'x' } else { 'b' })),
                }
            }
            c if c.is_ascii_digit() => {
                let st = i;
                while i < chars.len() && chars[i].is_ascii_digit() {
                    adv!();
                }
                let mut is_float = false;
                if chars.get(i) == Some(&'.') && chars.get(i + 1).is_some_and(|d| d.is_ascii_digit()) {
                    is_float = true;
                    adv!();
                    while i < chars.len() && chars[i].is_ascii_digit() {
                        adv!();
                    }
                    if matches!(chars.get(i), Some('e') | Some('E')) {
                        let mut j = i + 1;
                        if matches!(chars.get(j), Some('+') | Some('-')) {
                            j += 1;
                        }
                        if chars.get(j).is_some_and(|d| d.is_ascii_digit()) {
                            while i < j {
                                adv!();
                            }
                            while i < chars.len() && chars[i].is_ascii_digit() {
                                adv!();
                            }
                        }
                    }
                }
                let text: String = chars[st..i].iter().collect();
                if is_float {
                    match text.parse::<f64>() {
                        Ok(v) => toks.push(Token { tok: Tok::Float(v), span: sp }),
                        Err(_) => diags.error("E-LEX", sp, format!("bad number `{text}`")),
                    }
                } else {
                    match text.parse::<u64>() {
                        Ok(v) => toks.push(Token { tok: Tok::Int(v), span: sp }),
                        Err(_) => diags.error("E-LEX", sp, format!("integer `{text}` is too large")),
                    }
                }
            }
            '$' | '%' => {
                let (radix, ok): (u32, fn(char) -> bool) =
                    if c == '$' { (16, |d| d.is_ascii_hexdigit()) } else { (2, |d| d == '0' || d == '1') };
                if chars.get(i + 1).is_some_and(|d| ok(*d)) {
                    adv!();
                    let st = i;
                    while i < chars.len() && ok(chars[i]) {
                        adv!();
                    }
                    let text: String = chars[st..i].iter().collect();
                    match u64::from_str_radix(&text, radix) {
                        Ok(v) => toks.push(Token { tok: Tok::Int(v), span: sp }),
                        Err(_) => diags.error("E-LEX", sp, format!("integer `{c}{text}` is too large")),
                    }
                } else {
                    diags.error("E-LEX", sp, format!("`{c}` must be followed by {} digits", if c == '$' { "hexadecimal" } else { "binary" }));
                    adv!();
                }
            }
            '#' => {
                adv!();
                let radix_start = i;
                let (radix, digit_ok): (u32, fn(char) -> bool) = match chars.get(i) {
                    Some('$') => {
                        adv!();
                        (16, |d| d.is_ascii_hexdigit())
                    }
                    Some('%') => {
                        adv!();
                        (2, |d| d == '0' || d == '1')
                    }
                    Some('0') if prefixed_radix(&chars, i).is_some() => {
                        let r = prefixed_radix(&chars, i).unwrap();
                        adv!();
                        adv!();
                        r
                    }
                    _ => (10, |d| d.is_ascii_digit()),
                };
                let st = i;
                while i < chars.len() && digit_ok(chars[i]) {
                    adv!();
                }
                let text: String = chars[st..i].iter().collect();
                match u32::from_str_radix(&text, radix) {
                    Ok(v) if v <= 255 => toks.push(Token { tok: Tok::CharCode(v), span: sp }),
                    Ok(v) => diags.error("E-LEX", sp, format!("character code {v} is outside 0..255")),
                    Err(_) => {
                        diags.error("E-LEX", sp, "`#` must be followed by a character code");
                        let _ = radix_start;
                    }
                }
            }
            '"' => {
                adv!();
                let st = i;
                while i < chars.len() && chars[i] != '"' && chars[i] != '\n' {
                    adv!();
                }
                if chars.get(i) == Some(&'"') {
                    let text: String = chars[st..i].iter().collect();
                    adv!();
                    toks.push(Token { tok: Tok::Str(text), span: sp });
                } else {
                    diags.error("E-LEX", sp, "string is not closed before the end of the line");
                }
            }
            ':' => {
                adv!();
                toks.push(Token { tok: Tok::Colon, span: sp });
            }
            _ => {
                let two: String = chars[i..(i + 2).min(chars.len())].iter().collect();
                let p2 = ["<>", "<=", ">=", "<<", ">>"].iter().find(|p| **p == two).copied();
                if let Some(p) = p2 {
                    adv!();
                    adv!();
                    toks.push(Token { tok: Tok::Punct(p), span: sp });
                } else if let Some(p) = ["(", ")", ",", ".", "=", "<", ">", "+", "-", "*", "/", "@"].iter().find(|p| p.starts_with(c)) {
                    adv!();
                    toks.push(Token { tok: Tok::Punct(p), span: sp });
                } else {
                    diags.error("E-LEX", sp, format!("unexpected character `{c}`"));
                    adv!();
                }
            }
        }
    }
    for (open, osp) in block_depth.iter().rev() {
        let close = if *open == '(' { "*)" } else { "}" };
        diags.error("E-LEX", *osp, format!("block comment is not closed (expected `{close}`)"));
    }
    toks.push(Token { tok: Tok::Newline, span: Span { file, line, col } });
    toks.push(Token { tok: Tok::Eof, span: Span { file, line, col } });
    toks
}

/// A lone `_` followed only by blanks or a comment up to the end of the line.
fn continuation(chars: &[char], at: usize) -> bool {
    let mut j = at + 1;
    while j < chars.len() && chars[j] != '\n' {
        match chars[j] {
            ' ' | '\t' | '\r' => j += 1,
            '\'' => return true,
            '/' if chars.get(j + 1) == Some(&'/') => return true,
            _ => return false,
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ints(src: &str) -> (Vec<u64>, bool) {
        let mut d = Diagnostics::default();
        let v = lex(0, src, &mut d)
            .into_iter()
            .filter_map(|t| if let Tok::Int(n) = t.tok { Some(n) } else { None })
            .collect();
        (v, d.has_errors())
    }

    #[test]
    fn radix_prefixes_agree() {
        let (v, err) = ints("$A5 0xA5 0Xa5 %101 0b101 0B101 10");
        assert!(!err);
        assert_eq!(v, [0xA5, 0xA5, 0xA5, 5, 5, 5, 10]);
    }

    #[test]
    fn char_codes_take_prefixes() {
        let mut d = Diagnostics::default();
        let codes: Vec<u32> = lex(0, "#$41 #0x41 #0b1000001 #65", &mut d)
            .into_iter()
            .filter_map(|t| if let Tok::CharCode(n) = t.tok { Some(n) } else { None })
            .collect();
        assert!(!d.has_errors());
        assert_eq!(codes, [65; 4]);
    }

    #[test]
    fn bare_prefix_is_zero_then_identifier() {
        let (v, err) = ints("0x 0b 0b2 0xg");
        assert!(!err);
        assert_eq!(v, [0, 0, 0, 0]);
    }

    #[test]
    fn oversized_literals_are_errors() {
        assert!(ints("0x1FFFFFFFFFFFFFFFF").1);
        assert!(ints(&format!("0b{}", "1".repeat(65))).1);
    }
}
