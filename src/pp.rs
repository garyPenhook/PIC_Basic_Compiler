//! Line-based preprocessor: `#define`, `#undefine`, `#ifdef`, `#ifndef`, `#else`, `#endif`,
//! `#error`, `#warning`, `#option`, `#if` and `#elseif`. Removed lines are replaced by empty lines
//! so that line numbers in later diagnostics stay correct. `#constant` and `#variable` are
//! reported as unsupported for now.
//!
//! `#if` / `#elseif` take a compile-time expression over numbers, the predefined `_clock` and
//! `_device`, the comparisons `= <> < > <= >=`, `in (a, b, ...)`, `not`, `and`, `or` and
//! parentheses. `_clock` and `_device` come from the program's `Clock` and `Device` lines
//! (`Predef`), so a library module can check them before it declares anything.

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

/// Values the preprocessor knows from the program header (`Clock = n`, `Device = name`).
#[derive(Debug, Clone, Default)]
pub struct Predef {
    pub clock: Option<f64>,
    pub device: Option<String>,
    /// Lower-case names of the registers (and their aliases) the device description defines;
    /// `None` when no description could be loaded. `_has(NAME)` tests this set. Bit fields are listed as `reg.field`.
    pub registers: Option<std::collections::HashSet<String>>,
    /// Usable data RAM and data EEPROM of the device in bytes (`_ram`, `_eeprom`); `None` without a description.
    pub ram: Option<u32>,
    pub eeprom: Option<u32>,
}

/// Reads `Clock = n` (or `Declare Xtal = n`) and `Device = name` from the program text. The header
/// must come before any include or declaration, so the first match is the one that counts.
pub fn scan_header(text: &str) -> Predef {
    let mut p = Predef::default();
    for line in text.lines() {
        let code = line.split('\'').next().unwrap_or("").trim().to_ascii_lowercase();
        let (word, rest) = match code.find(|c: char| c.is_whitespace() || c == '=') {
            Some(i) => (&code[..i], code[i..].trim_start()),
            None => (code.as_str(), ""),
        };
        let (word, rest) = if word == "declare" {
            match rest.strip_prefix("xtal") {
                Some(r) => ("clock", r.trim_start()),
                None => continue,
            }
        } else {
            (word, rest)
        };
        let Some(value) = rest.strip_prefix('=').map(str::trim) else { continue };
        match word {
            "clock" if p.clock.is_none() => p.clock = value.parse().ok(),
            "device" if p.device.is_none() => p.device = Some(value.strip_prefix("pic").unwrap_or(value).to_string()),
            _ => {}
        }
    }
    p
}

#[derive(Debug, Clone, PartialEq)]
enum Val {
    Num(f64),
    Str(String),
    Bool(bool),
}

struct Eval<'a> {
    toks: Vec<String>,
    pos: usize,
    predef: &'a Predef,
}

fn tokenize_expr(s: &str) -> Result<Vec<String>, String> {
    let b: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c.is_whitespace() {
            i += 1;
        } else if c.is_ascii_alphanumeric() || c == '_' || c == '.' {
            let st = i;
            while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == '_' || b[i] == '.') {
                i += 1;
            }
            out.push(b[st..i].iter().collect::<String>().to_ascii_lowercase());
        } else if "(),=".contains(c) {
            out.push(c.to_string());
            i += 1;
        } else if c == '<' || c == '>' {
            if i + 1 < b.len() && (b[i + 1] == '=' || (c == '<' && b[i + 1] == '>')) {
                out.push(format!("{c}{}", b[i + 1]));
                i += 2;
            } else {
                out.push(c.to_string());
                i += 1;
            }
        } else {
            return Err(format!("unexpected `{c}` in the #if expression"));
        }
    }
    Ok(out)
}

impl Eval<'_> {
    fn peek(&self) -> Option<&str> {
        self.toks.get(self.pos).map(String::as_str)
    }
    fn eat(&mut self, t: &str) -> bool {
        if self.peek() == Some(t) {
            self.pos += 1;
            true
        } else {
            false
        }
    }
    fn truth(v: &Val) -> Result<bool, String> {
        match v {
            Val::Bool(b) => Ok(*b),
            Val::Num(n) => Ok(*n != 0.0),
            Val::Str(_) => Err("a device name cannot be used as a condition by itself".into()),
        }
    }
    fn or(&mut self) -> Result<Val, String> {
        let mut v = self.and()?;
        while self.eat("or") {
            let r = self.and()?;
            v = Val::Bool(Self::truth(&v)? | Self::truth(&r)?);
        }
        Ok(v)
    }
    fn and(&mut self) -> Result<Val, String> {
        let mut v = self.not()?;
        while self.eat("and") {
            let r = self.not()?;
            v = Val::Bool(Self::truth(&v)? & Self::truth(&r)?);
        }
        Ok(v)
    }
    fn not(&mut self) -> Result<Val, String> {
        if self.eat("not") {
            let v = self.not()?;
            return Ok(Val::Bool(!Self::truth(&v)?));
        }
        self.cmp()
    }
    fn cmp(&mut self) -> Result<Val, String> {
        let l = self.atom()?;
        if self.eat("in") {
            if !self.eat("(") {
                return Err("`in` needs a parenthesised list".into());
            }
            let mut hit = false;
            loop {
                let item = self.atom()?;
                hit |= Self::equal(&l, &item)?;
                if self.eat(")") {
                    break;
                }
                if !self.eat(",") {
                    return Err("expected `,` or `)` in the `in` list".into());
                }
            }
            return Ok(Val::Bool(hit));
        }
        let Some(op) = self.peek().filter(|t| ["=", "<>", "<", ">", "<=", ">="].contains(t)).map(str::to_string) else { return Ok(l) };
        self.pos += 1;
        let r = self.atom()?;
        match (&l, &r, op.as_str()) {
            (Val::Num(a), Val::Num(b), _) => Ok(Val::Bool(match op.as_str() {
                "=" => (a - b).abs() < 1e-9,
                "<>" => (a - b).abs() >= 1e-9,
                "<" => a < b,
                ">" => a > b,
                "<=" => a <= b,
                _ => a >= b,
            })),
            (_, _, "=") => Ok(Val::Bool(Self::equal(&l, &r)?)),
            (_, _, "<>") => Ok(Val::Bool(!Self::equal(&l, &r)?)),
            _ => Err("device names can only be compared with `=`, `<>` or `in`".into()),
        }
    }
    fn equal(a: &Val, b: &Val) -> Result<bool, String> {
        match (a, b) {
            (Val::Num(x), Val::Num(y)) => Ok((x - y).abs() < 1e-9),
            (Val::Str(x), Val::Str(y)) => Ok(x == y),
            (Val::Bool(x), Val::Bool(y)) => Ok(x == y),
            _ => Err("a number and a device name cannot be compared".into()),
        }
    }
    fn atom(&mut self) -> Result<Val, String> {
        let Some(t) = self.peek().map(str::to_string) else { return Err("the #if expression ends too early".into()) };
        self.pos += 1;
        match t.as_str() {
            "(" => {
                let v = self.or()?;
                if !self.eat(")") {
                    return Err("missing `)` in the #if expression".into());
                }
                Ok(v)
            }
            "true" => Ok(Val::Bool(true)),
            "false" => Ok(Val::Bool(false)),
            "_clock" => self.predef.clock.map(Val::Num).ok_or_else(|| "_clock is used but the program has no `Clock = n` line".into()),
            "_ram" => self.predef.ram.map(|n| Val::Num(f64::from(n))).ok_or_else(|| "_ram is used but the device description could not be loaded (is there a `Device = name` line?)".into()),
            "_eeprom" => self.predef.eeprom.map(|n| Val::Num(f64::from(n))).ok_or_else(|| "_eeprom is used but the device description could not be loaded (is there a `Device = name` line?)".into()),
            "_has" => {
                if !self.eat("(") {
                    return Err("`_has` needs a register name in parentheses: `_has(ANSELB)`".into());
                }
                let Some(name) = self.peek().map(str::to_string) else { return Err("`_has(` needs a register name".into()) };
                self.pos += 1;
                if !self.eat(")") {
                    return Err("missing `)` after the register name in `_has`".into());
                }
                match &self.predef.registers {
                    Some(set) => Ok(Val::Bool(set.contains(&name))),
                    None => Err("_has is used but the device description could not be loaded (is there a `Device = name` line?)".into()),
                }
            }
            "_device" => self
                .predef
                .device
                .as_ref()
                .map(|d| Val::Str(d.to_ascii_lowercase()))
                .ok_or_else(|| "_device is used but the program has no `Device = name` line".into()),
            _ => {
                let numeric = t.starts_with(|c: char| c.is_ascii_digit() || c == '.');
                if let (true, Ok(n)) = (numeric, t.parse::<f64>()) {
                    Ok(Val::Num(n))
                } else if t.starts_with(|c: char| c.is_ascii_digit()) {
                    // A device name such as 18F27Q10.
                    Ok(Val::Str(t))
                } else if t.starts_with("pic18") {
                    Ok(Val::Str(t[3..].to_string()))
                } else {
                    Err(format!("`{t}` is not a number or a predefined constant (_clock, _device, _ram, _eeprom, _has)"))
                }
            }
        }
    }
}

/// Evaluates the argument of `#if` / `#elseif`.
fn eval_condition(arg: &str, predef: &Predef) -> Result<bool, String> {
    let toks = tokenize_expr(arg)?;
    if toks.is_empty() {
        return Err("#if needs an expression".into());
    }
    let mut e = Eval { toks, pos: 0, predef };
    let v = e.or()?;
    if e.pos != e.toks.len() {
        return Err(format!("unexpected `{}` in the #if expression", e.toks[e.pos]));
    }
    Eval::truth(&v)
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

pub fn preprocess(file: u32, src: &str, defined: &mut HashSet<String>, predef: &Predef, diags: &mut Diagnostics) -> Preprocessed {
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
        let (name, arg) = match rest.find(|c: char| !c.is_ascii_alphanumeric() && c != '_') {
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
                None => diags.error("E-PP", span, "#else without #if/#ifdef/#ifndef"),
            },
            "endif" => {
                if stack.pop().is_none() {
                    diags.error("E-PP", span, "#endif without #if/#ifdef/#ifndef");
                }
            }
            "if" => {
                let cond = active
                    && eval_condition(arg, predef).unwrap_or_else(|m| {
                        diags.error("E-PP", span, m);
                        false
                    });
                stack.push(Cond { parent: active, taken: cond, active: cond, seen_else: false });
            }
            "elseif" => match stack.last_mut() {
                Some(c) if !c.seen_else => {
                    let cond = c.parent
                        && !c.taken
                        && eval_condition(arg, predef).unwrap_or_else(|m| {
                            diags.error("E-PP", span, m);
                            false
                        });
                    c.active = cond;
                    c.taken |= cond;
                }
                Some(_) => diags.error("E-PP", span, "#elseif after #else"),
                None => diags.error("E-PP", span, "#elseif without #if"),
            },
            "constant" | "variable" => {
                if active {
                    diags.error("E-PP-UNSUPPORTED", span, format!("#{lname} is not implemented yet (needs the compile-time expression evaluator)"));
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
        diags.error("E-PP", Span { file, line: src.lines().count() as u32, col: 1 }, "#if/#ifdef/#ifndef without #endif");
    }
    Preprocessed { text: out, options }
}
