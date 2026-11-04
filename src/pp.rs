//! Line-based preprocessor: `#define`, `#undefine`, `#ifdef`, `#ifndef`, `#else`, `#endif`,
//! `#error`, `#warning`, `#option`, `#if` and `#elseif`. Removed lines are replaced by empty lines
//! so that line numbers in later diagnostics stay correct. `#constant` defines a value the program
//! can use as a `Const` and `#if` can test; `#variable` is reported as unsupported for now.
//!
//! `#if` / `#elseif` take a compile-time expression over numbers, the predefined `_clock` and
//! `_device`, names given a value by `#define NAME value` or `#constant NAME = expr`, the arithmetic
//! `+ - * / mod << >>` (precedence as in the language), the comparisons `= <> < > <= >=`, `in (a, b, ...)`, `not`, `and`, `or` and
//! parentheses. `_clock` and `_device` come from the program's `Clock` and `Device` lines
//! (`Predef`), so a library module can check them before it declares anything.

use crate::diag::{Diagnostics, Span};
use std::collections::{HashMap, HashSet};

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
    /// The program asked for the I2C peripheral with `#option I2c = Hardware`. Libraries see it here, like the
    /// clock: `#define` names are file-scoped, so they could not. `_i2chw` is this and the part having `I2C1CON0`.
    pub i2c_hw: bool,
    /// Values of the other predefined names (`_core`, `_maxram`, `_maxrom`, `_ports`, `_adc`, `_usart`, `_mssp`,
    /// `_ccp`, `_comparator`, `_flash_write`), derived from the device description; empty without one.
    pub extra: std::collections::HashMap<&'static str, Pre>,
}

/// A predefined value other than the clock and device name.
#[derive(Debug, Clone, PartialEq)]
pub enum Pre {
    Num(f64),
    Bool(bool),
    Str(String),
}

/// Reads `Clock = n` (or `Declare Xtal = n`), `Device = name` and `#option I2c = Hardware` from the
/// program text. The header must come before any include or declaration, so the first match is the
/// one that counts for `Clock` and `Device`; the last `#option I2c` line counts, as for the other options
/// (`sema::read_options`). The scan is of the raw text, so the option must be a plain line of the main
/// program, not inside an `#if` block.
pub fn scan_header(text: &str) -> Predef {
    let mut p = Predef::default();
    for line in text.lines() {
        let code = line.split('\'').next().unwrap_or("").trim().to_ascii_lowercase();
        let (word, rest) = match code.find(|c: char| c.is_whitespace() || c == '=') {
            Some(i) => (&code[..i], code[i..].trim_start()),
            None => (code.as_str(), ""),
        };
        if word == "#option" {
            if let Some((name, value)) = rest.split_once('=') {
                if name.trim() == "i2c" {
                    p.i2c_hw = value.trim() == "hardware";
                }
            }
            continue;
        }
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
pub enum Val {
    Num(f64),
    Str(String),
    Bool(bool),
}

struct Eval<'a> {
    toks: Vec<String>,
    pos: usize,
    predef: &'a Predef,
    /// Names given a value with `#define NAME value` or `#constant`, in lower case.
    values: &'a HashMap<String, Val>,
    /// Names defined with no value (`#define NAME`, `-D NAME`): true in a condition.
    defined: &'a HashSet<String>,
}

/// The directive text up to a `'` comment; a `'` inside a quoted text value is part of the text.
fn strip_comment(s: &str) -> &str {
    let mut in_text = false;
    for (i, c) in s.char_indices() {
        match c {
            '"' => in_text = !in_text,
            '\'' if !in_text => return &s[..i],
            _ => {}
        }
    }
    s
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
                // `1e-3`, `2.5E+4`: the sign belongs to the exponent of a number.
                if i < b.len()
                    && (b[i] == '-' || b[i] == '+')
                    && b[st].is_ascii_digit()
                    && (b[i - 1] == 'e' || b[i - 1] == 'E')
                    && b[st..i - 1].iter().all(|c| c.is_ascii_digit() || *c == '.')
                    && b.get(i + 1).is_some_and(|c| c.is_ascii_digit())
                {
                    i += 1;
                }
            }
            out.push(b[st..i].iter().collect::<String>().to_ascii_lowercase());
        } else if c == '"' {
            // A text value, kept as written.
            let st = i;
            i += 1;
            while i < b.len() && b[i] != '"' {
                i += 1;
            }
            if i >= b.len() {
                return Err("a text value in the expression is missing its closing quote".into());
            }
            i += 1;
            out.push(b[st..i].iter().collect::<String>());
        } else if "(),=+-*/%".contains(c) {
            out.push(c.to_string());
            i += 1;
        } else if c == '<' || c == '>' {
            if i + 1 < b.len() && (b[i + 1] == c && c != '=' || b[i + 1] == '=' || (c == '<' && b[i + 1] == '>')) {
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
        let l = self.shift()?;
        if self.eat("in") {
            if !self.eat("(") {
                return Err("`in` needs a parenthesised list".into());
            }
            let mut hit = false;
            loop {
                let item = self.shift()?;
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
        let r = self.shift()?;
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
    fn number(v: Val, what: &str) -> Result<f64, String> {
        match v {
            Val::Num(n) => Ok(n),
            _ => Err(format!("`{what}` works on numbers")),
        }
    }
    /// `a << b >> c`: below `+ -`, as in the language, so `1 << 3 + 1` is `1 << 4`.
    fn shift(&mut self) -> Result<Val, String> {
        let mut v = self.sum()?;
        while let Some(op) = self.peek().filter(|t| *t == "<<" || *t == ">>").map(str::to_string) {
            self.pos += 1;
            let r = self.sum()?;
            let (a, b) = (Self::number(v, &op)?, Self::number(r, &op)?);
            if a.fract() != 0.0 || b.fract() != 0.0 || !(0.0..=62.0).contains(&b) || a.abs() > 9e15 {
                return Err(format!("`{op}` needs whole numbers and a shift of 0 to 62"));
            }
            v = Val::Num(if op == "<<" { ((a as i64) << (b as u32)) as f64 } else { ((a as i64) >> (b as u32)) as f64 });
        }
        Ok(v)
    }
    /// `a + b - c ...`
    fn sum(&mut self) -> Result<Val, String> {
        let mut v = self.term()?;
        while let Some(op) = self.peek().filter(|t| *t == "+" || *t == "-").map(str::to_string) {
            self.pos += 1;
            let r = self.term()?;
            let (a, b) = (Self::number(v, &op)?, Self::number(r, &op)?);
            v = Val::Num(if op == "+" { a + b } else { a - b });
        }
        Ok(v)
    }
    /// `a * b / c mod d ...`
    fn term(&mut self) -> Result<Val, String> {
        let mut v = self.unary()?;
        while let Some(op) = self.peek().filter(|t| ["*", "/", "%", "mod"].contains(t)).map(str::to_string) {
            self.pos += 1;
            let r = self.unary()?;
            let (a, b) = (Self::number(v, &op)?, Self::number(r, &op)?);
            v = Val::Num(match op.as_str() {
                "*" => a * b,
                "/" | "%" | "mod" if b == 0.0 => return Err("division by zero in the expression".into()),
                // Whole numbers divide as in the language (`7 / 2` is 3); anything fractional divides exactly.
                "/" if a.fract() == 0.0 && b.fract() == 0.0 => (a / b).trunc(),
                "/" => a / b,
                _ => a % b,
            });
        }
        Ok(v)
    }
    fn unary(&mut self) -> Result<Val, String> {
        if self.eat("-") {
            let v = self.unary()?;
            return Ok(Val::Num(-Self::number(v, "-")?));
        }
        self.atom()
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
            // Asked for and the part has the peripheral: on a part with an MSSP the option changes nothing.
            "_i2chw" => Ok(Val::Bool(self.predef.i2c_hw && self.predef.registers.as_ref().is_some_and(|r| r.contains("i2c1con0")))),
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
            _ if t.starts_with('_') && self.predef.extra.contains_key(t.as_str()) => Ok(match &self.predef.extra[t.as_str()] {
                Pre::Num(n) => Val::Num(*n),
                Pre::Bool(b) => Val::Bool(*b),
                Pre::Str(s) => Val::Str(s.clone()),
            }),
            _ if matches!(t.as_str(), "_core" | "_maxram" | "_maxrom" | "_ports" | "_adc" | "_usart" | "_mssp" | "_ccp" | "_comparator" | "_flash_write") => {
                Err(format!("{t} is used but the device description could not be loaded (is there a `Device = name` line?)"))
            }
            "_device" => self
                .predef
                .device
                .as_ref()
                .map(|d| Val::Str(d.to_ascii_lowercase()))
                .ok_or_else(|| "_device is used but the program has no `Device = name` line".into()),
            _ if t.starts_with('"') => Ok(Val::Str(t[1..t.len() - 1].to_string())),
            _ if self.values.contains_key(&t) => Ok(self.values[&t].clone()),
            _ if self.defined.contains(&t) => Ok(Val::Bool(true)),
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
                    Err(format!("`{t}` is not a number, a name given a value by #define or #constant, or a predefined constant (_clock, _device, _core, _ram, _maxram, _maxrom, _eeprom, _ports, _adc, _usart, _mssp, _ccp, _comparator, _flash_write, _has, _i2chw)"))
                }
            }
        }
    }
}

type DeclareConst = Option<(String, Val, String, String)>;

/// `Declare Name = expression` where `Name` is not `Xtal` (that one is the clock, read by the parser).
/// `None`: the line is not such a declaration. `Some(None)`: it is, but is wrong (error reported).
/// `Some(Some((lower-case name, value, literal, name)))`: it becomes `Const Name = literal`.
fn declare_const(line: &str, predef: &Predef, values: &HashMap<String, Val>, defined: &HashSet<String>, span: Span, diags: &mut Diagnostics) -> Option<DeclareConst> {
    let rest = line.trim();
    let word = rest.get(..7)?;
    if !word.eq_ignore_ascii_case("declare") || !rest[7..].starts_with(|c: char| c.is_whitespace()) {
        return None;
    }
    let (n, expr) = rest[7..].split_once('=').map(|(n, e)| (n.trim(), e.trim()))?;
    let valid = !n.is_empty() && n.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') && !n.starts_with(|c: char| c.is_ascii_digit());
    if !valid || n.eq_ignore_ascii_case("xtal") {
        return None;
    }
    match eval_value(expr, predef, values, defined).and_then(|v| const_literal(&v).map(|lit| (v, lit))) {
        Ok((v, lit)) => Some(Some((n.to_ascii_lowercase(), v, lit, n.to_string()))),
        Err(_) => {
            diags.error("E-UNSUPPORTED", span, format!("`Declare {n}` needs a number, text or True/False value; other switches are library options, see the module's documentation"));
            Some(None)
        }
    }
}

/// Evaluates the argument of `#if` / `#elseif`.
fn eval_condition(arg: &str, predef: &Predef, values: &HashMap<String, Val>, defined: &HashSet<String>) -> Result<bool, String> {
    Eval::truth(&eval_value(arg, predef, values, defined)?)
}

/// Evaluates an expression to a value: the argument of `#if`, `#constant` or `#define NAME value`.
fn eval_value(arg: &str, predef: &Predef, values: &HashMap<String, Val>, defined: &HashSet<String>) -> Result<Val, String> {
    let toks = tokenize_expr(arg)?;
    if toks.is_empty() {
        return Err("an expression is needed here".into());
    }
    let mut e = Eval { toks, pos: 0, predef, values, defined };
    let v = e.or()?;
    if e.pos != e.toks.len() {
        return Err(format!("unexpected `{}` in the expression", e.toks[e.pos]));
    }
    Ok(v)
}

/// The text of a value as a `Const` initialiser: a whole number, a decimal number, `True` / `False` or a quoted text.
fn const_literal(v: &Val) -> Result<String, String> {
    match v {
        Val::Num(n) if n.fract() == 0.0 && n.abs() < 9e15 => Ok(format!("{}", *n as i64)),
        // A huge whole value stays a Float: `1.0e18`, not an integer no type can hold.
        Val::Num(n) if n.fract() == 0.0 => Ok(format!("{n:.1e}")),
        Val::Num(n) => Ok(format!("{n}")),
        Val::Bool(b) => Ok(if *b { "True" } else { "False" }.into()),
        Val::Str(t) if !t.contains('"') => Ok(format!("\"{t}\"")),
        Val::Str(_) => Err("a text value cannot contain a double quote".into()),
    }
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
    // Values of `#constant NAME = expr` and `#define NAME value`, by lower-case name. File-scoped like `#define`.
    let mut values: HashMap<String, Val> = HashMap::new();
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
            if active && !was_in_comment {
                if let Some(text) = declare_const(strip_comment(trimmed), predef, &values, defined, span, diags) {
                    // `Declare Name = value` (not `Xtal`): a `Const`, and a value `#if` can use, like `#constant`.
                    if let Some((lname, v, lit, n)) = text {
                        values.insert(lname.clone(), v);
                        defined.insert(lname);
                        out.push_str(&format!("Const {n} = {lit}\n"));
                    } else {
                        out.push('\n');
                    }
                    continue;
                }
            }
            if active && starts_asm(line) {
                in_asm = true;
            }
            out.push_str(if active { line } else { "" });
            out.push('\n');
            continue;
        };
        let rest = strip_comment(rest).trim_end();
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
                    && eval_condition(arg, predef, &values, defined).unwrap_or_else(|m| {
                        diags.error("E-PP", span, m);
                        false
                    });
                stack.push(Cond { parent: active, taken: cond, active: cond, seen_else: false });
            }
            "elseif" => match stack.last_mut() {
                Some(c) if !c.seen_else => {
                    let cond = c.parent
                        && !c.taken
                        && eval_condition(arg, predef, &values, defined).unwrap_or_else(|m| {
                            diags.error("E-PP", span, m);
                            false
                        });
                    c.active = cond;
                    c.taken |= cond;
                }
                Some(_) => diags.error("E-PP", span, "#elseif after #else"),
                None => diags.error("E-PP", span, "#elseif without #if"),
            },
            "variable" => {
                // `#variable NAME = expr`: like `#constant`, but the name may be given a new value later
                // (`#variable N = N + 1`) and no `Const` line is written: it exists for `#if` only.
                if active {
                    let (n, expr) = arg.split_once('=').map_or((arg, ""), |(n, e)| (n.trim(), e.trim()));
                    let valid = !n.is_empty() && n.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') && !n.starts_with(|c: char| c.is_ascii_digit());
                    if !valid || expr.is_empty() {
                        diags.error("E-PP", span, "#variable needs the form `#variable Name = expression`");
                    } else {
                        match eval_value(expr, predef, &values, defined) {
                            Ok(v) => {
                                let lname = n.to_ascii_lowercase();
                                values.insert(lname.clone(), v);
                                defined.insert(lname);
                            }
                            Err(m) => diags.error("E-PP", span, m),
                        }
                    }
                }
            }
            "constant" => {
                // `#constant NAME = expr`: the value is known to `#if` and the line becomes `Const NAME = value`.
                if active {
                    let (n, expr) = arg.split_once('=').map_or((arg, ""), |(n, e)| (n.trim(), e.trim()));
                    let valid = !n.is_empty() && n.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') && !n.starts_with(|c: char| c.is_ascii_digit());
                    if !valid || expr.is_empty() {
                        diags.error("E-PP", span, "#constant needs the form `#constant Name = expression`");
                    } else {
                        let lname = n.to_ascii_lowercase();
                        match eval_value(expr, predef, &values, defined).and_then(|v| const_literal(&v).map(|lit| (v, lit))) {
                            Ok((v, lit)) => {
                                if values.get(&lname).is_some_and(|old| *old != v) {
                                    diags.error("E-PP", span, format!("#constant `{n}` is already defined with another value"));
                                } else {
                                    values.insert(lname.clone(), v);
                                    defined.insert(lname);
                                    out.push_str(&format!("Const {n} = {lit}\n"));
                                    continue;
                                }
                            }
                            Err(m) => diags.error("E-PP", span, m),
                        }
                    }
                }
            }
            _ if !active => {}
            "define" => {
                if key.is_empty() {
                    diags.error("E-PP", span, "#define needs a name");
                } else {
                    // `#define NAME value`: the value is an expression `#if` can use.
                    // Anything else (`#define LED RB3`) is not an error: the name is just defined, as before.
                    let value = arg.trim_start().get(key.len()..).unwrap_or("").trim();
                    values.remove(&key);
                    if !value.is_empty()
                        && let Ok(v) = eval_value(value, predef, &values, defined)
                    {
                        values.insert(key.clone(), v);
                    }
                    defined.insert(key);
                }
            }
            "undefine" => {
                defined.remove(&key);
                values.remove(&key);
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

#[cfg(test)]
mod tests {
    use super::*;

    fn run(src: &str, predef: &Predef) -> (String, usize) {
        let mut diags = Diagnostics::default();
        let mut defined = HashSet::new();
        let out = preprocess(0, src, &mut defined, predef, &mut diags);
        (out.text, diags.error_count())
    }

    #[test]
    fn header_scan_reads_the_i2c_option() {
        assert!(scan_header("Device = 18F16Q41\n#option I2c = Hardware\n").i2c_hw);
        assert!(scan_header("  #OPTION  i2C=HARDWARE ' trailing comment\n").i2c_hw);
        assert!(!scan_header("#option I2c = Software\n").i2c_hw);
        assert!(!scan_header("#option Optimize = Size\n").i2c_hw);
        assert!(!scan_header("Device = 18F16Q41\n").i2c_hw);
        // The other header values are still read when the option is present.
        let p = scan_header("Device = 18F16Q41\n#option I2c = Hardware\nClock = 64\n");
        assert_eq!(p.clock, Some(64.0));
        assert_eq!(p.device.as_deref(), Some("18f16q41"));
    }

    #[test]
    fn i2chw_selects_the_branch() {
        let src = "#if _i2chw\nA\n#else\nB\n#endif\n#if not _i2chw\nC\n#endif\n";
        let regs = |names: &[&str]| Some(names.iter().map(|n| n.to_string()).collect::<HashSet<String>>());
        let off = Predef { registers: regs(&["i2c1con0"]), ..Predef::default() };
        let on = Predef { i2c_hw: true, registers: regs(&["i2c1con0"]), ..Predef::default() };
        // asked for, but the part has an MSSP and no I2C1: the option changes nothing
        let mssp = Predef { i2c_hw: true, registers: regs(&["ssp1con1"]), ..Predef::default() };
        let (t, errs) = run(src, &mssp);
        assert_eq!(errs, 0);
        assert!(t.contains('B') && !t.contains('A'), "{t:?}");
        let (t, errs) = run(src, &off);
        assert_eq!(errs, 0);
        assert!(t.contains('B') && !t.contains('A') && t.contains('C'), "{t:?}");
        let (t, errs) = run(src, &on);
        assert_eq!(errs, 0);
        assert!(t.contains('A') && !t.contains('B') && !t.contains('C'), "{t:?}");
    }

    #[test]
    fn variable_changes_and_extra_predefined_names() {
        let mut p = Predef::default();
        p.extra.insert("_mssp", Pre::Num(2.0));
        p.extra.insert("_core", Pre::Str("pic18".into()));
        p.extra.insert("_flash_write", Pre::Bool(true));
        let (t, errs) = run("#variable N = 1\n#variable N = N + 2\n#if N = 3 and _mssp = 2 and _core = \"pic18\" and _flash_write\nYES\n#endif\n", &p);
        assert_eq!(errs, 0, "{t:?}");
        assert!(t.contains("YES") && !t.contains("Const"), "{t:?}");
        // no description: a clear error, not "not a number"
        let (_, errs) = run("#if _ccp > 1\n#endif\n", &Predef::default());
        assert_eq!(errs, 1);
    }

    #[test]
    fn constants_and_arithmetic_in_conditions() {
        let p = Predef { clock: Some(16.0), ..Predef::default() };
        let (t, errs) = run("#constant W = 8\n#constant S = W * 5 - 2 * (3 + 1)\n#if S = 32 and W << 1 = 16 and 17 mod 5 = 2 and -W < 0\nYES\n#else\nNO\n#endif\n", &p);
        assert_eq!(errs, 0, "{t:?}");
        assert!(t.starts_with("Const W = 8\nConst S = 32\n"), "{t:?}");
        assert!(t.contains("YES") && !t.contains("NO"), "{t:?}");
        // text and truth values, a #define value, and #undefine forgetting it
        let (t, errs) = run("#constant Name = \"abc\"\n#constant Ok = _clock > 8\n#define K 3\n#if Name = \"abc\" and Ok and K = 3\nYES\n#endif\n#undefine K\n#if K\nBAD\n#endif\n", &p);
        assert_eq!(errs, 1, "{t:?}");
        assert!(t.contains("Const Name = \"abc\"") && t.contains("Const Ok = True") && t.contains("YES") && !t.contains("BAD"), "{t:?}");
        // a constant in an inactive block is not defined
        let (t, errs) = run("#if false\n#constant X = 1\n#endif\n#ifdef x\nBAD\n#endif\n", &p);
        assert_eq!(errs, 0);
        assert!(!t.contains("BAD") && !t.contains("Const"), "{t:?}");
    }

    #[test]
    fn precedence_division_exponents_and_free_form_defines() {
        let p = Predef::default();
        // shifts bind looser than + - (as in the language); whole numbers divide as integers
        let (t, errs) = run("#constant A = 1 << 3 + 1\n#constant B = 7 / 2\n#constant C = 7.5 / 2\n#constant D = 1e-3 * 1000\n#constant E = 1e17 * 10\n", &p);
        assert_eq!(errs, 0, "{t:?}");
        assert!(t.contains("Const A = 16") && t.contains("Const B = 3") && t.contains("Const C = 3.75") && t.contains("Const D = 1\n"), "{t:?}");
        assert!(t.contains("Const E = 1.0e18"), "{t:?}");
        // a text value may hold an apostrophe; a trailing comment is still removed
        let (t, errs) = run("#constant S = \"it's\" 'comment\n", &p);
        assert_eq!(errs, 0, "{t:?}");
        assert!(t.contains("Const S = \"it's\""), "{t:?}");
        // a free-form #define value is not an error, and a bare #define forgets an earlier value
        let (t, errs) = run("#define LED RB3\n#define Msg hello world\n#define A 3\n#define A\n#if A = 3\nBAD\n#endif\n#ifdef led\nYES\n#endif\n", &p);
        assert_eq!(errs, 1, "only the comparison of the valueless A: {t:?}");
        assert!(t.contains("YES") && !t.contains("BAD"), "{t:?}");
    }
}
