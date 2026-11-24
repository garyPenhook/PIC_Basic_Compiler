//! Recursive-descent parser for the grammar in `docs/GRAMMAR.md`.
//!
//! Errors are reported through `Diagnostics`; a failed statement or declaration is skipped to the
//! next line so that one run reports several problems.

use crate::ast::*;
use crate::diag::{Diagnostics, Span};
use crate::lexer::{CALLABLE_KEYWORDS, Tok, Token};

type PResult<T> = Result<T, ()>;

pub struct Parser<'a> {
    toks: Vec<Token>,
    pos: usize,
    file: u32,
    diags: &'a mut Diagnostics,
    next_id: &'a mut NodeId,
    bare_not_cmp: Vec<NodeId>,
    /// The statement blocks open at the cursor, outermost first: the opening word as written
    /// in messages (`For`), where it starts, and the words that may close it.
    open: Vec<Open>,
    /// Where the declaration being parsed starts, for "the `Sub` starts here".
    decl_start: Span,
    /// Set when a closing word for an outer block was met inside an inner one: the inner
    /// blocks give up quietly (no further errors, no skipping) until the block it closes
    /// takes it.
    unwinding: bool,
    /// Set when the wrong closing word (`Next` for a `While`) was taken as the innermost
    /// block's end: its `expect_block_end` then succeeds once without another error.
    substituted: bool,
}

struct Open {
    word: &'static str,
    span: Span,
    stops: Vec<&'static str>,
}

/// The line a designator starts on.
fn span_line(d: &Designator) -> u32 {
    d.head.span.line
}

/// The closing word used here for a spelling of other languages (`End While` is `Wend`).
fn native_closer(w: &str) -> Option<&'static str> {
    match w {
        "endwhile" => Some("wend"),
        "endfor" => Some("next"),
        "enddo" => Some("loop"),
        "endrepeat" => Some("until"),
        _ => None,
    }
}

/// The block a closing word belongs to: `Next` closes a `For`.
fn opener_of(closer: &str) -> &'static str {
    match closer {
        "next" => "For",
        "wend" | "endwhile" => "While",
        "endfor" => "For",
        "enddo" => "Do",
        "endrepeat" => "Repeat",
        "until" => "Repeat",
        "loop" => "Do",
        "endif" | "else" | "elseif" => "If",
        "endselect" | "case" => "Select",
        "restore" => "Save",
        "endsub" => "Sub",
        "endfunction" => "Function",
        "endproc" => "Proc",
        "endinterrupt" => "Interrupt",
        "endevent" => "Event",
        "endstructure" => "Structure",
        "endasm" => "Asm",
        _ => "block",
    }
}

const DECL_STARTERS: &[&str] =
    &["public", "private", "const", "dim", "static", "volatile", "structure", "type", "sub", "function", "proc", "inline", "noinline", "reentrant", "interrupt", "symbol"];

const TYPE_KEYWORDS: &[&str] = &["boolean", "bit", "byte", "shortint", "word", "integer", "longword", "longint", "float", "char", "string"];

pub fn parse_unit(file: u32, toks: Vec<Token>, diags: &mut Diagnostics, next_id: &mut NodeId) -> Unit {
    let mut p = Parser { toks, pos: 0, file, diags, next_id, bare_not_cmp: Vec::new(), open: Vec::new(), decl_start: Span::default(), unwinding: false, substituted: false };
    let mut unit = p.unit();
    unit.bare_not_cmp = std::mem::take(&mut p.bare_not_cmp);
    unit
}

impl<'a> Parser<'a> {
    // ---- token helpers -------------------------------------------------------------------

    fn peek(&self) -> &Tok {
        &self.toks[self.pos.min(self.toks.len() - 1)].tok
    }
    fn peek_at(&self, n: usize) -> &Tok {
        &self.toks[(self.pos + n).min(self.toks.len() - 1)].tok
    }
    fn span(&self) -> Span {
        self.toks[self.pos.min(self.toks.len() - 1)].span
    }
    fn bump(&mut self) -> Token {
        let t = self.toks[self.pos.min(self.toks.len() - 1)].clone();
        if self.pos < self.toks.len() - 1 {
            self.pos += 1;
        }
        t
    }
    fn id(&mut self) -> NodeId {
        *self.next_id += 1;
        *self.next_id
    }
    fn at_ident(&self, word: &str) -> bool {
        matches!(self.peek(), Tok::Ident(n) if n.eq_ignore_ascii_case(word))
    }

    fn at_kw(&self, k: &str) -> bool {
        matches!(self.peek(), Tok::Kw(x) if *x == k)
    }
    fn eat_kw(&mut self, k: &str) -> bool {
        if self.at_kw(k) {
            self.bump();
            true
        } else {
            false
        }
    }
    fn at_punct(&self, p: &str) -> bool {
        matches!(self.peek(), Tok::Punct(x) if *x == p)
    }
    fn eat_punct(&mut self, p: &str) -> bool {
        if self.at_punct(p) {
            self.bump();
            true
        } else {
            false
        }
    }
    fn at_eof(&self) -> bool {
        matches!(self.peek(), Tok::Eof)
    }

    fn describe(&self) -> String {
        match self.peek() {
            Tok::Int(v) => format!("`{v}`"),
            Tok::Float(v) => format!("`{v}`"),
            Tok::Str(s) => format!("\"{s}\""),
            Tok::CharCode(c) => format!("`#{c}`"),
            Tok::Ident(s) => format!("`{s}`"),
            Tok::Kw(k) => format!("`{k}`"),
            Tok::Punct(p) => format!("`{p}`"),
            Tok::Colon => "`:`".into(),
            Tok::Newline => "end of line".into(),
            Tok::RawAsm(_) => "assembler text".into(),
            Tok::Eof => "end of file".into(),
        }
    }

    fn fail<T>(&mut self, code: &'static str, msg: impl Into<String>) -> PResult<T> {
        let sp = self.span();
        // A lexical error on this line already explains the problem; do not pile a syntax error on it.
        let lexed = self.diags.items.iter().any(|d| d.code == "E-LEX" && d.span.file == sp.file && d.span.line == sp.line);
        // While unwinding to an outer block the closing word has been reported already.
        if !lexed && !self.unwinding {
            self.diags.error(code, sp, msg);
        }
        Err(())
    }
    /// An E-SYNTAX error with a suggested fix, unless the line already has a lexical error
    /// (which explains it) or the parser is unwinding to an outer block.
    fn hint(&mut self, sp: Span, msg: impl Into<String>, help: impl Into<String>) {
        let lexed = self.diags.items.iter().any(|d| d.code == "E-LEX" && d.span.file == sp.file && d.span.line == sp.line);
        if !lexed && !self.unwinding {
            self.diags.error_with("E-SYNTAX", sp, msg).help(help);
        }
    }
    fn expected<T>(&mut self, what: &str) -> PResult<T> {
        let found = self.describe();
        self.fail("E-SYNTAX", format!("expected {what}, found {found}"))
    }
    fn expect_kw(&mut self, k: &str) -> PResult<()> {
        if self.eat_kw(k) { Ok(()) } else { self.expected(&format!("`{k}`")) }
    }
    fn expect_punct(&mut self, p: &str) -> PResult<()> {
        if self.eat_punct(p) { Ok(()) } else { self.expected(&format!("`{p}`")) }
    }
    fn ident(&mut self) -> PResult<Ident> {
        match self.peek().clone() {
            Tok::Ident(name) => {
                let span = self.bump().span;
                Ok(Ident { name, span })
            }
            Tok::Kw(k) => {
                let msg = format!("`{k}` is a reserved word and cannot be used as a name");
                self.fail("E-RESERVED", msg)
            }
            _ => self.expected("a name"),
        }
    }
    /// A name or any reserved word, used where reserved words are legitimate names (device
    /// registers and configuration settings).
    fn name_or_kw(&mut self) -> PResult<Ident> {
        match self.peek().clone() {
            Tok::Ident(name) => {
                let span = self.bump().span;
                Ok(Ident { name, span })
            }
            Tok::Kw(k) => {
                let span = self.bump().span;
                Ok(Ident { name: k.to_ascii_uppercase(), span })
            }
            _ => self.expected("a name"),
        }
    }

    fn at_eol(&self) -> bool {
        matches!(self.peek(), Tok::Newline | Tok::Colon | Tok::Eof)
    }
    /// Ends a statement or declaration.
    fn end_stmt(&mut self) -> PResult<()> {
        if self.unwinding {
            return Ok(());
        }
        if self.at_eol() {
            if !self.at_eof() {
                self.bump();
            }
            Ok(())
        } else {
            let found = self.describe();
            self.fail("E-SYNTAX", format!("unexpected {found} at the end of the statement"))
        }
    }
    fn skip_blank(&mut self) {
        while matches!(self.peek(), Tok::Newline | Tok::Colon) {
            self.bump();
        }
    }
    /// Skips to the end of the current line after an error.
    fn sync(&mut self) {
        while !matches!(self.peek(), Tok::Newline | Tok::Eof) {
            self.bump();
        }
    }
    fn at_line_start(&self) -> bool {
        self.pos == 0 || matches!(self.toks[self.pos - 1].tok, Tok::Newline)
    }

    /// The block-ending word at the cursor, with the number of tokens it spans. `End If` and
    /// `EndIf` are the same word.
    fn block_word(&self) -> Option<(&'static str, usize)> {
        let Tok::Kw(k) = self.peek() else { return None };
        match *k {
            "endif" | "endselect" | "endproc" | "else" | "elseif" | "case" | "wend" | "until" | "next" | "restore" | "loop" => Some((k, 1)),
            "end" => {
                let w = match self.peek_at(1) {
                    Tok::Kw("if") => "endif",
                    Tok::Kw("select") => "endselect",
                    Tok::Kw("sub") => "endsub",
                    Tok::Kw("function") => "endfunction",
                    Tok::Kw("structure") => "endstructure",
                    Tok::Kw("interrupt") => "endinterrupt",
                    Tok::Kw("event") => "endevent",
                    Tok::Kw("asm") => "endasm",
                    // Not a closing word here (`Wend` is); recognised so that it is reported as such.
                    Tok::Kw("while") => "endwhile",
                    Tok::Kw("for") => "endfor",
                    Tok::Kw("do") => "enddo",
                    Tok::Kw("repeat") => "endrepeat",
                    _ => return Some(("end", 1)),
                };
                Some((w, 2))
            }
            _ => None,
        }
    }
    fn expect_block_end(&mut self, word: &str) -> PResult<()> {
        if self.unwinding {
            return Ok(());
        }
        if self.substituted {
            self.substituted = false;
            return Ok(());
        }
        match self.block_word() {
            Some((w, n)) if w == word => {
                for _ in 0..n {
                    self.bump();
                }
                Ok(())
            }
            _ => {
                let found = self.describe();
                self.fail("E-SYNTAX", format!("expected `{}`, found {found}", pretty_word(word)))
            }
        }
    }

    /// True when `w` closes a block outside the innermost open one (or is the program's
    /// final `End`), so that the innermost block was left unclosed.
    fn closes_outer(&self, w: &str) -> bool {
        // Only a bare `End` is the final one; `End Foo` with an unknown word is not.
        (w == "end" && matches!(self.peek_at(1), Tok::Newline | Tok::Eof | Tok::Colon)) || self.open.iter().rev().skip(1).any(|o| o.stops.contains(&w))
    }

    /// A closing word `w` at `sp` that the innermost open block does not take. When it closes
    /// an outer block, the inner one is reported as unclosed and the parser unwinds to the
    /// outer block; otherwise the word is reported as having no block to close.
    fn stray_closer(&mut self, w: &'static str, sp: Span) {
        let found = pretty_word(w);
        let inner = self.open.last().map(|o| (o.word, o.span, *o.stops.last().unwrap()));
        match inner {
            Some((word, at, closer)) if self.closes_outer(w) => {
                let close = pretty_word(closer);
                self.diags
                    .error_with("E-SYNTAX", sp, format!("`{found}` found while the `{word}` on line {} is still open", at.line))
                    .note(at, format!("this `{word}` needs its `{close}` before the `{found}`"));
                self.unwinding = true;
            }
            Some((word, at, closer)) => {
                let close = pretty_word(closer);
                let owner = opener_of(w);
                // A final closing word of the wrong kind (`Next` for a `While`) is most likely
                // meant to close the innermost block: take it as that, so the block's own end
                // does not give a second error. `Until` is left alone (a condition follows it).
                // A `Select` is never closed this way: its `Case` arms go on after a body.
                let ends = ["next", "wend", "loop", "endif", "restore"];
                let native = native_closer(w);
                let take = closer != "until" && ((owner != word && ends.contains(&w) && ends.contains(&closer)) || native == Some(closer));
                let msg = if let Some(n) = native.filter(|n| *n == closer) {
                    format!("`{found}` is written `{}` here", pretty_word(n))
                } else if let Some(n) = native {
                    format!("`{found}` has no `{owner}` to close (a `{owner}` ends with `{}`): the innermost open block is the `{word}` on line {}, closed by `{close}`", pretty_word(n), at.line)
                } else if owner == word {
                    format!("unexpected `{found}`")
                } else { format!("`{found}` has no `{owner}` to close: the innermost open block is the `{word}` on line {}, closed by `{close}`", at.line) };
                let d = self.diags.error_with("E-SYNTAX", sp, msg);
                d.note(at, format!("the `{word}` starts here"));
                if take {
                    d.help(format!("write `{close}` here to close the `{word}`"));
                    self.substituted = true;
                }
            }
            None => {
                let owner = opener_of(w);
                self.diags.error("E-SYNTAX", sp, format!("`{found}` has no `{owner}` to close"));
            }
        }
    }

    /// True while unwinding with the cursor on the closing word (or the end of the file) that
    /// started it, so a loop may go round again without skipping. Anywhere else unwinding is
    /// given up, so that a loop never spins on a token it cannot read.
    fn unwinding_here(&mut self) -> bool {
        if self.unwinding && (self.at_eof() || self.block_word().is_some()) {
            return true;
        }
        self.unwinding = false;
        false
    }

    /// The end of the file inside a block that needs one of `stops`.
    fn unclosed_at_eof(&mut self, stops: &[&str]) -> PResult<()> {
        // `If` waits for `ElseIf`, `Else` or `End If`; only the last one closes it.
        let want = stops.last().map(|s| format!("`{}`", pretty_word(s))).unwrap_or_default();
        let sp = self.span();
        match self.open.last().map(|o| (o.word, o.span)) {
            Some((word, at)) if !self.unwinding => {
                self.diags
                    .error_with("E-SYNTAX", sp, format!("the `{word}` on line {} is not closed: expected {want} before the end of the file", at.line))
                    .note(at, format!("the `{word}` starts here"));
                // One report for the innermost block; the outer ones are unclosed for the same reason.
                self.unwinding = true;
                Err(())
            }
            Some(_) => Err(()),
            None => self.fail("E-SYNTAX", format!("block is not closed: expected {want} before the end of the file")),
        }
    }

    // ---- compilation unit ----------------------------------------------------------------

    fn unit(&mut self) -> Unit {
        let mut unit = Unit { kind: UnitKind::Program, name: None, file: self.file, headers: vec![], includes: vec![], decls: vec![], stmts: vec![], bare_not_cmp: vec![] };
        self.skip_blank();
        if self.at_kw("module") || self.at_kw("program") {
            unit.kind = if self.at_kw("module") { UnitKind::Module } else { UnitKind::Program };
            self.bump();
            match self.peek() {
                Tok::Ident(_) => {
                    unit.name = self.ident().ok();
                }
                _ if unit.kind == UnitKind::Module => {
                    let _: PResult<()> = self.expected("the module name");
                }
                _ => {}
            }
            if self.end_stmt().is_err() {
                self.sync();
            }
        }
        // 0 headers, 1 includes, 2 declarations, 3 statements
        let mut phase = 0;
        loop {
            self.skip_blank();
            if self.at_eof() {
                break;
            }
            let start = self.pos;
            let sp = self.span();
            let r: PResult<()> = (|| {
                if self.at_ident("cfile") && matches!(self.peek_at(1), Tok::Str(_)) {
                    if phase > 0 {
                        self.diags.error("E-ORDER", sp, "CFile must come before includes and declarations");
                    }
                    self.bump();
                    let Tok::Str(name) = self.bump().tok else { unreachable!() };
                    self.end_stmt()?;
                    unit.headers.push(Header { kind: HeaderKind::CFile(name), span: sp });
                } else if self.at_ident("edata") && !matches!(self.peek_at(1), Tok::Punct(_)) {
                    if phase > 0 {
                        self.diags.error("E-ORDER", sp, "EData must come before includes and declarations");
                    }
                    self.bump();
                    let mut at = None;
                    if self.at_ident("at") {
                        self.bump();
                        at = Some(self.expr()?);
                        self.expect_punct(",")?;
                    }
                    let mut items = vec![self.expr()?];
                    while self.eat_punct(",") {
                        items.push(self.expr()?);
                    }
                    self.end_stmt()?;
                    unit.headers.push(Header { kind: HeaderKind::EData { at, items }, span: sp });
                } else if matches!(self.peek(), Tok::Kw("device" | "clock" | "config")) || (self.at_kw("declare") && !self.forward_ahead()) {
                    if phase > 0 {
                        self.diags.error("E-ORDER", sp, "Device, Clock and Config must come before includes and declarations");
                    }
                    let h = self.header()?;
                    unit.headers.push(h);
                } else if self.at_kw("include") {
                    if phase >= 2 {
                        self.diags.error("E-ORDER", sp, "Include must come before declarations");
                    }
                    phase = phase.max(1);
                    self.bump();
                    let name = match self.peek().clone() {
                        Tok::Str(s) => {
                            self.bump();
                            s
                        }
                        _ => return self.expected("a quoted module name"),
                    };
                    self.end_stmt()?;
                    unit.includes.push(Include { name, span: sp });
                } else if self.at_kw("end") && self.block_word().is_some_and(|(w, _)| w == "end") {
                    self.unwinding = false;
                    self.bump();
                    self.skip_blank();
                    if !self.at_eof() {
                        let found = self.describe();
                        self.diags.error("E-SYNTAX", self.span(), format!("unexpected {found} after the final `End`"));
                    }
                    self.pos = self.toks.len() - 1;
                } else if let Some((w, _)) = self.block_word().filter(|(w, _)| *w != "end") {
                    // A closing word with no block open (`Next` with no `For`).
                    self.stray_closer(w, sp);
                    return Err(());
                } else if self.starts_decl() {
                    if phase == 3 {
                        self.diags.error("E-ORDER", sp, "declarations must come before the first executable statement");
                    }
                    phase = 2;
                    let d = self.decl()?;
                    unit.decls.push(d);
                } else {
                    phase = 3;
                    let s = self.stmt()?;
                    unit.stmts.push(s);
                }
                Ok(())
            })();
            if r.is_err() {
                if self.unwinding_here() {
                    // Unwound to here: the closing word is read again by this loop.
                    if self.at_eof() || self.block_word().is_some_and(|(w, _)| w == "end") {
                        continue;
                    }
                    self.unwinding = false;
                }
                self.sync();
                if self.pos == start {
                    self.bump();
                }
            }
        }
        unit
    }

    /// True at `Declare` when a routine follows (a forward declaration), not `Xtal`.
    fn forward_ahead(&self) -> bool {
        matches!(self.peek_at(1), Tok::Kw("sub" | "function" | "proc" | "inline" | "noinline" | "reentrant"))
    }

    fn starts_decl(&self) -> bool {
        match self.peek() {
            Tok::Kw("declare") => self.forward_ahead(),
            Tok::Kw(k) if DECL_STARTERS.contains(k) => true,
            Tok::Ident(n) if n.eq_ignore_ascii_case("extern") || n.eq_ignore_ascii_case("export") => matches!(self.peek_at(1), Tok::Kw("sub" | "function")),
            Tok::Kw("event") => matches!(self.peek_at(1), Tok::Ident(_)),
            _ => false,
        }
    }

    fn header(&mut self) -> PResult<Header> {
        let span = self.span();
        let Tok::Kw(k) = self.bump().tok else { unreachable!() };
        let kind = match k {
            "device" => {
                self.expect_punct("=")?;
                HeaderKind::Device(self.device_name()?)
            }
            "clock" => {
                self.expect_punct("=")?;
                HeaderKind::Clock(self.expr()?)
            }
            "declare" => {
                match self.peek().clone() {
                    Tok::Ident(n) if n.eq_ignore_ascii_case("xtal") => {
                        self.bump();
                    }
                    _ => return self.fail("E-UNSUPPORTED", "only `Declare Xtal = n` is supported; other global Declare switches are library constants (PLAN §4.2)"),
                }
                self.expect_punct("=")?;
                HeaderKind::Clock(self.expr()?)
            }
            _ => {
                let mut items = Vec::new();
                loop {
                    let name = self.name_or_kw()?;
                    self.expect_punct("=")?;
                    let value = match self.peek().clone() {
                        Tok::Int(v) => {
                            let sp = self.bump().span;
                            ConfigValue::Int(v, sp)
                        }
                        _ => ConfigValue::Name(self.name_or_kw()?),
                    };
                    items.push(ConfigItem { name, value });
                    if !self.eat_punct(",") {
                        break;
                    }
                }
                HeaderKind::Config(items)
            }
        };
        self.end_stmt()?;
        Ok(Header { kind, span })
    }

    /// `18F27Q10`, `PIC18F27Q10`: a number glued to a name, or a name.
    fn device_name(&mut self) -> PResult<String> {
        let mut text = String::new();
        let mut last_end: Option<(u32, u32)> = None;
        loop {
            let sp = self.span();
            if let Some((line, col)) = last_end
                && (sp.line != line || sp.col != col)
            {
                break;
            }
            match self.peek().clone() {
                Tok::Int(v) => {
                    let s = v.to_string();
                    last_end = Some((sp.line, sp.col + s.len() as u32));
                    text.push_str(&s);
                    self.bump();
                }
                Tok::Ident(n) => {
                    last_end = Some((sp.line, sp.col + n.len() as u32));
                    text.push_str(&n);
                    self.bump();
                }
                _ => break,
            }
        }
        if text.is_empty() {
            return self.expected("a device name such as 18F27Q10");
        }
        let up = text.to_ascii_uppercase();
        // dsPIC33 parts keep their own prefix: `dsPIC33CK64MC105` and `33CK64MC105` both name DSPIC33CK64MC105.
        Ok(if up.starts_with("PIC") || up.starts_with("DSPIC") { up } else if up.starts_with("33") { format!("DSPIC{up}") } else { format!("PIC{up}") })
    }

    // ---- declarations --------------------------------------------------------------------

    fn decl(&mut self) -> PResult<Decl> {
        let span = self.span();
        self.decl_start = span;
        let vis = if self.eat_kw("public") {
            Some(Vis::Public)
        } else if self.eat_kw("private") {
            Some(Vis::Private)
        } else {
            None
        };
        let (mut is_static, mut is_volatile) = (false, false);
        loop {
            let (flag, word) = match self.peek() {
                Tok::Kw("static") => (&mut is_static, "Static"),
                Tok::Kw("volatile") => (&mut is_volatile, "Volatile"),
                _ => break,
            };
            if std::mem::replace(flag, true) {
                self.diags.error("E-SYNTAX", self.span(), format!("`{word}` is written twice"));
            }
            self.bump();
        }
        if (is_static || is_volatile) && !matches!(self.peek(), Tok::Kw("dim")) {
            return self.expected("`Dim` after `Static` or `Volatile`");
        }
        let kind = match self.peek().clone() {
            Tok::Kw("const") => {
                self.bump();
                let mut items = vec![self.const_item()?];
                while self.eat_punct(",") {
                    items.push(self.const_item()?);
                }
                self.end_stmt()?;
                DeclKind::Const(items)
            }
            Tok::Kw("dim") => {
                self.bump();
                let mut d = self.dim_decl()?;
                d.is_static = is_static;
                d.is_volatile = is_volatile;
                self.end_stmt()?;
                DeclKind::Dim(d)
            }
            Tok::Kw("structure") => {
                self.bump();
                DeclKind::Structure(self.struct_decl()?)
            }
            Tok::Kw("type") => {
                self.bump();
                let name = self.ident()?;
                self.expect_punct("=")?;
                self.expect_kw("event")?;
                let params = self.event_params()?;
                self.end_stmt()?;
                DeclKind::EventType(name, params)
            }
            Tok::Kw("symbol") => {
                self.bump();
                let name = self.ident()?;
                self.eat_punct("=");
                let value = self.expr()?;
                self.end_stmt()?;
                DeclKind::Symbol(name, value)
            }
            Tok::Kw("interrupt") => {
                self.bump();
                let name = self.ident()?;
                self.expect_punct("(")?;
                let priority = if self.at_punct(")") { None } else { Some(self.expr()?) };
                self.expect_punct(")")?;
                self.end_stmt()?;
                let body = self.body("endinterrupt")?;
                DeclKind::Interrupt(InterruptDecl { name, priority, body })
            }
            Tok::Kw("event") => {
                self.bump();
                let name = self.ident()?;
                let params = self.event_params()?;
                self.end_stmt()?;
                let body = self.body("endevent")?;
                DeclKind::Event(EventDecl { name, params, body })
            }
            Tok::Kw("sub" | "function" | "proc" | "inline" | "noinline" | "reentrant" | "declare") => DeclKind::Routine(self.routine()?),
            Tok::Ident(n) if n.eq_ignore_ascii_case("extern") || n.eq_ignore_ascii_case("export") => DeclKind::Routine(self.routine()?),
            _ => return self.expected("a declaration"),
        };
        Ok(Decl { vis, span, kind })
    }

    fn const_item(&mut self) -> PResult<ConstItem> {
        let name = self.ident()?;
        let size = if self.eat_punct("(") {
            let e = self.expr()?;
            self.expect_punct(")")?;
            Some(e)
        } else {
            None
        };
        let ty = if self.eat_kw("as") { Some(self.type_spec()?) } else { None };
        self.expect_punct("=")?;
        let init = if self.at_punct("(") {
            // A parenthesised list `(1, 2, 3)` or just a parenthesised expression.
            let save = self.pos;
            self.bump();
            let first = self.expr()?;
            if self.at_punct(",") {
                let mut items = vec![first];
                while self.eat_punct(",") {
                    items.push(self.expr()?);
                }
                self.expect_punct(")")?;
                ConstInit::List(items)
            } else {
                self.pos = save;
                ConstInit::Scalar(self.expr()?)
            }
        } else {
            ConstInit::Scalar(self.expr()?)
        };
        Ok(ConstItem { name, size, ty, init })
    }

    fn dim_decl(&mut self) -> PResult<DimDecl> {
        let mut items = Vec::new();
        loop {
            let name = self.ident()?;
            let mut more_dims = Vec::new();
            let size = if self.eat_punct("(") {
                let e = self.expr()?;
                while self.eat_punct(",") {
                    more_dims.push(self.expr()?);
                }
                self.expect_punct(")")?;
                Some(e)
            } else {
                None
            };
            let (init, list) = if self.eat_punct("=") { self.dim_init()? } else { (None, None) };
            items.push(DimItem { name, size, more_dims, init, list });
            if !self.eat_punct(",") {
                break;
            }
        }
        let as_clause = if self.eat_kw("as") { Some(self.as_clause()?) } else { None };
        let (trailing_init, trailing_list) = if as_clause.is_some() && self.eat_punct("=") { self.dim_init()? } else { (None, None) };
        Ok(DimDecl { is_static: false, is_volatile: false, items, as_clause, trailing_init, trailing_list })
    }

    /// The value after `=` in a `Dim`: an expression, or a list `(1, 2, 3)` for an array.
    fn dim_init(&mut self) -> PResult<(Option<Expr>, Option<Vec<Expr>>)> {
        if self.at_punct("(") {
            let save = self.pos;
            self.bump();
            let first = self.expr()?;
            if self.at_punct(",") {
                let mut items = vec![first];
                while self.eat_punct(",") {
                    items.push(self.expr()?);
                }
                self.expect_punct(")")?;
                return Ok((None, Some(items)));
            }
            self.pos = save;
        }
        Ok((Some(self.expr()?), None))
    }

    fn as_clause(&mut self) -> PResult<AsClause> {
        if matches!(self.peek(), Tok::Kw(k) if TYPE_KEYWORDS.contains(k)) {
            Ok(AsClause::Type(self.type_spec()?))
        } else {
            Ok(AsClause::Designator(self.designator()?))
        }
    }

    fn type_spec(&mut self) -> PResult<TypeSpec> {
        let t = match self.peek().clone() {
            Tok::Kw(k) => {
                let t = match k {
                    "boolean" => TypeSpec::Boolean,
                    "bit" => TypeSpec::Bit,
                    "byte" => TypeSpec::Byte,
                    "shortint" => TypeSpec::ShortInt,
                    "word" => TypeSpec::Word,
                    "integer" => TypeSpec::Integer,
                    "longword" => TypeSpec::LongWord,
                    "longint" => TypeSpec::LongInt,
                    "float" => TypeSpec::Float,
                    "char" => TypeSpec::Char,
                    "string" => {
                        self.bump();
                        let size = if self.eat_punct("(") {
                            let e = self.expr()?;
                            self.expect_punct(")")?;
                            Some(Box::new(e))
                        } else if self.at_punct("*") {
                            // `String * 8` is the fixed-length form of other BASICs: report it with
                            // the spelling here and read it as `String(8)`, so the variable exists.
                            let sp = self.span();
                            self.bump();
                            let e = self.primary()?;
                            let n = match &e.kind {
                                ExprKind::Int(v) => v.to_string(),
                                _ => "n".to_string(),
                            };
                            self.hint(sp, "a string's size is written in parentheses", format!("write `String({n})`"));
                            Some(Box::new(e))
                        } else {
                            None
                        };
                        return Ok(TypeSpec::String(size));
                    }
                    _ => return self.expected("a type"),
                };
                self.bump();
                t
            }
            Tok::Ident(_) => TypeSpec::Named(self.ident()?),
            _ => return self.expected("a type"),
        };
        Ok(t)
    }

    fn struct_decl(&mut self) -> PResult<StructDecl> {
        let name = self.ident()?;
        self.end_stmt()?;
        let mut fields = Vec::new();
        loop {
            self.skip_blank();
            if matches!(self.block_word(), Some(("endstructure", _))) {
                break;
            }
            if self.at_eof() {
                return self.expected("`End Structure`");
            }
            let r: PResult<()> = (|| {
                let fname = self.ident()?;
                let size = if self.eat_punct("(") {
                    let e = self.expr()?;
                    self.expect_punct(")")?;
                    Some(e)
                } else {
                    None
                };
                self.expect_kw("as")?;
                let as_clause = self.as_clause()?;
                self.end_stmt()?;
                fields.push(Field { name: fname, size, as_clause });
                Ok(())
            })();
            if r.is_err() {
                self.sync();
            }
        }
        self.expect_block_end("endstructure")?;
        self.end_stmt()?;
        Ok(StructDecl { name, fields })
    }

    fn routine(&mut self) -> PResult<Routine> {
        let forward = self.eat_kw("declare");
        let mut inlining = Inlining::Default;
        let mut reentrant = false;
        let ext = self.at_ident("extern");
        let export = self.at_ident("export");
        if ext || export {
            self.bump();
            if !matches!(self.peek(), Tok::Kw("sub" | "function")) {
                return self.expected(if ext { "`Sub` or `Function` after `Extern`" } else { "`Sub` or `Function` after `Export`" });
            }
        }
        loop {
            if self.eat_kw("inline") {
                inlining = Inlining::Inline;
            } else if self.eat_kw("noinline") {
                inlining = Inlining::NoInline;
            } else if self.eat_kw("reentrant") {
                reentrant = true;
            } else {
                break;
            }
        }
        let (is_function, is_proc) = match self.peek() {
            Tok::Kw("sub") => (false, false),
            Tok::Kw("function") => (true, false),
            Tok::Kw("proc") => (false, true),
            _ => return self.expected("`Sub`, `Function` or `Proc`"),
        };
        self.bump();
        let name = self.ident()?;
        self.expect_punct("(")?;
        let mut params = Vec::new();
        if !self.at_punct(")") {
            loop {
                params.push(self.param()?);
                if !self.eat_punct(",") {
                    break;
                }
            }
        }
        self.expect_punct(")")?;
        let mut ret = None;
        let mut is_function = is_function;
        if is_function {
            self.expect_kw("as")?;
            ret = Some(self.type_spec()?);
        } else if is_proc && self.eat_punct(",") {
            ret = Some(self.type_spec()?);
            is_function = true;
        }
        self.end_stmt()?;
        if ext || forward {
            return Ok(Routine { name, is_function, inlining, reentrant, ext, export, forward, params, ret, body: Body { decls: Vec::new(), stmts: Vec::new() } });
        }
        let end = if is_proc {
            "endproc"
        } else if is_function {
            "endfunction"
        } else {
            "endsub"
        };
        let body = self.body(end)?;
        Ok(Routine { name, is_function, inlining, reentrant, ext, export, forward, params, ret, body })
    }

    /// `( [param {, param}] )` of an event type or handler.
    fn event_params(&mut self) -> PResult<Vec<Param>> {
        self.expect_punct("(")?;
        let mut params = Vec::new();
        if !self.at_punct(")") {
            loop {
                params.push(self.param()?);
                if !self.eat_punct(",") {
                    break;
                }
            }
        }
        self.expect_punct(")")?;
        Ok(params)
    }

    fn param(&mut self) -> PResult<Param> {
        let (mode, mode_explicit) = if self.eat_kw("byval") {
            (ParamMode::ByVal, true)
        } else if self.eat_kw("byrefconst") {
            (ParamMode::ByRefConst, true)
        } else if self.eat_kw("byref") {
            (ParamMode::ByRef, true)
        } else {
            (ParamMode::ByVal, false)
        };
        let name = self.ident()?;
        let is_array = if self.at_punct("(") && matches!(self.peek_at(1), Tok::Punct(")")) {
            self.bump();
            self.bump();
            true
        } else {
            false
        };
        self.expect_kw("as")?;
        let ty = self.type_spec()?;
        let default = if self.eat_punct("=") { Some(self.expr()?) } else { None };
        Ok(Param { mode, mode_explicit, name, is_array, ty, default })
    }

    /// Local declarations, then statements, up to and including the block-ending word.
    fn body(&mut self, end: &'static str) -> PResult<Body> {
        let word = opener_of(end);
        self.open.push(Open { word, span: self.decl_start, stops: vec![end] });
        let r = self.body_inner(end);
        self.open.pop();
        r
    }

    fn body_inner(&mut self, end: &'static str) -> PResult<Body> {
        let mut decls = Vec::new();
        let mut stmts = Vec::new();
        loop {
            self.skip_blank();
            if self.at_eof() {
                self.unclosed_at_eof(&[end])?;
            }
            if matches!(self.block_word(), Some((w, _)) if w == end) {
                self.unwinding = false;
                break;
            }
            if self.unwinding && self.block_word().is_some_and(|(w, _)| self.closes_outer(w)) {
                // The final `End` of the program: this routine was never closed. Keep what was read.
                return Ok(Body { decls, stmts });
            }
            let start = self.pos;
            let sp = self.span();
            let r: PResult<()> = (|| {
                if let Some((w, _)) = self.block_word() {
                    self.stray_closer(w, sp);
                    return Err(());
                }
                if self.starts_decl() {
                    if matches!(self.peek(), Tok::Kw("public" | "private")) {
                        self.diags.error("E-VIS", sp, "local declarations cannot be Public or Private");
                    }
                    if matches!(self.peek(), Tok::Kw("sub" | "function" | "proc" | "inline" | "noinline" | "reentrant" | "interrupt" | "type" | "event" | "symbol")) {
                        self.diags.error("E-NESTED", sp, "routines, interrupts, events and types cannot be declared inside a routine");
                    } else if !stmts.is_empty() {
                        self.diags.error("E-ORDER", sp, "declarations must come before the first executable statement");
                    }
                    let d = self.decl()?;
                    decls.push(d);
                } else {
                    let s = self.stmt()?;
                    stmts.push(s);
                }
                Ok(())
            })();
            if r.is_err() {
                if self.unwinding_here() {
                    continue;
                }
                self.sync();
                if self.pos == start {
                    self.bump();
                }
            }
        }
        self.expect_block_end(end)?;
        self.end_stmt()?;
        Ok(Body { decls, stmts })
    }

    // ---- statements ----------------------------------------------------------------------

    /// Statements up to (not including) one of the `stops` words.
    fn block(&mut self, stops: &[&'static str]) -> PResult<Vec<Stmt>> {
        // A wrong closing word is taken only by the block it was met in.
        self.substituted = false;
        // The innermost open block (pushed by `stmt`) now waits for these words.
        if let Some(o) = self.open.last_mut() {
            o.stops = stops.to_vec();
        }
        let mut out = Vec::new();
        loop {
            self.skip_blank();
            if self.at_eof() {
                self.unclosed_at_eof(stops)?;
            }
            let start = self.pos;
            let sp = self.span();
            if let Some((w, _)) = self.block_word() {
                if stops.contains(&w) {
                    self.unwinding = false;
                    return Ok(out);
                }
                if self.unwinding {
                    // Closed by an outer block's word: keep the statements read so far.
                    return Ok(out);
                }
                self.stray_closer(w, sp);
                if self.unwinding {
                    return Ok(out);
                }
                self.sync();
                if self.substituted {
                    return Ok(out);
                }
                continue;
            }
            match self.stmt() {
                Ok(s) => out.push(s),
                Err(()) => {
                    if self.unwinding_here() {
                        continue;
                    }
                    self.sync();
                    if self.pos == start {
                        self.bump();
                    }
                }
            }
        }
    }

    fn stmt(&mut self) -> PResult<Stmt> {
        let word = match self.peek() {
            Tok::Kw("if") => Some("If"),
            Tok::Kw("select") => Some("Select"),
            Tok::Kw("while") => Some("While"),
            Tok::Kw("repeat") => Some("Repeat"),
            Tok::Kw("do") => Some("Do"),
            Tok::Kw("for") => Some("For"),
            Tok::Kw("save") => Some("Save"),
            _ => None,
        };
        let Some(word) = word else { return self.stmt_inner() };
        let depth = self.open.len();
        self.open.push(Open { word, span: self.span(), stops: Vec::new() });
        let r = self.stmt_inner();
        self.open.truncate(depth);
        r
    }

    fn stmt_inner(&mut self) -> PResult<Stmt> {
        let span = self.span();
        let kind = match self.peek().clone() {
            Tok::Kw("if") => self.if_stmt()?,
            Tok::Kw("select") => self.select_stmt()?,
            Tok::Kw("while") => {
                self.bump();
                let cond = self.expr()?;
                self.end_stmt()?;
                let body = self.block(&["wend"])?;
                self.expect_block_end("wend")?;
                self.end_stmt()?;
                StmtKind::While { cond, body }
            }
            Tok::Kw("repeat") => {
                self.bump();
                self.end_stmt()?;
                let body = self.block(&["until"])?;
                self.expect_block_end("until")?;
                let until = self.expr()?;
                self.end_stmt()?;
                StmtKind::Repeat { body, until }
            }
            Tok::Kw("do") => self.do_loop()?,
            Tok::Kw("for") => {
                self.bump();
                let var = self.designator()?;
                self.expect_punct("=")?;
                let from = self.expr()?;
                self.expect_kw("to")?;
                let to = self.expr()?;
                let step = if self.eat_kw("step") { Some(self.expr()?) } else { None };
                self.end_stmt()?;
                let body = self.block(&["next"])?;
                self.expect_block_end("next")?;
                if !self.unwinding && !self.at_eol() && matches!(self.peek(), Tok::Ident(_)) {
                    let sp = self.span();
                    self.hint(sp, "`Next` is written without the loop variable", format!("write `Next` alone; it closes the `For` on line {}", span_line(&var)));
                    self.sync();
                }
                self.end_stmt()?;
                StmtKind::For { var, from, to, step, body }
            }
            Tok::Kw("break") => {
                self.bump();
                self.end_stmt()?;
                StmtKind::Break
            }
            Tok::Kw("continue") => {
                self.bump();
                self.end_stmt()?;
                StmtKind::Continue
            }
            Tok::Kw("exit" | "exitproc") => {
                self.bump();
                if let Tok::Kw(k @ ("for" | "do" | "while" | "sub" | "function")) = self.peek().clone() {
                    let sp = self.span();
                    self.bump();
                    let (fix, why) = if matches!(k, "for" | "do" | "while") { ("Break", "`Break` leaves the innermost loop; `Exit` leaves the whole routine") } else { ("Exit", "`Exit` alone leaves the current routine") };
                    self.hint(sp, format!("`Exit {}` is not a statement here", crate::suggest::pretty(k)), format!("write `{fix}`: {why}"));
                    self.end_stmt()?;
                    return Ok(Stmt { span, kind: if fix == "Break" { StmtKind::Break } else { StmtKind::Exit } });
                }
                self.end_stmt()?;
                StmtKind::Exit
            }
            Tok::Kw("goto") => {
                self.bump();
                if matches!(self.peek(), Tok::Int(_)) {
                    let sp = self.span();
                    self.hint(sp, "`GoTo` needs a label name, not a line number", "put a label on its own line (`Again:`) and write `GoTo Again`");
                    return Err(());
                }
                let l = self.ident()?;
                self.end_stmt()?;
                StmtKind::GoTo(l)
            }
            Tok::Kw("gosub") => {
                self.bump();
                let l = self.ident()?;
                self.end_stmt()?;
                StmtKind::GoSub(l)
            }
            Tok::Kw("return") => {
                self.bump();
                self.end_stmt()?;
                StmtKind::SubReturn
            }
            Tok::Kw(k @ ("enable" | "disable")) => {
                self.bump();
                self.expect_punct("(")?;
                let n = self.ident()?;
                self.expect_punct(")")?;
                self.end_stmt()?;
                if k == "enable" { StmtKind::Enable(n) } else { StmtKind::Disable(n) }
            }
            Tok::Kw("save") => {
                self.bump();
                self.expect_punct("(")?;
                let mut items = Vec::new();
                loop {
                    match self.peek().clone() {
                        Tok::Int(v) => {
                            let sp = self.bump().span;
                            items.push(SaveItem::Int(v, sp));
                        }
                        _ => items.push(SaveItem::Designator(self.designator()?)),
                    }
                    if !self.eat_punct(",") {
                        break;
                    }
                }
                self.expect_punct(")")?;
                self.end_stmt()?;
                let body = self.block(&["restore"])?;
                self.expect_block_end("restore")?;
                self.end_stmt()?;
                StmtKind::Save { items, body }
            }
            Tok::Kw("asm") => {
                self.bump();
                let mut preserves = Vec::new();
                if matches!(self.peek(), Tok::Ident(n) if n.eq_ignore_ascii_case("preserves")) {
                    self.bump();
                    self.expect_punct("(")?;
                    loop {
                        preserves.push(self.name_or_kw()?);
                        if !self.eat_punct(",") {
                            break;
                        }
                    }
                    self.expect_punct(")")?;
                }
                self.end_stmt()?;
                let lines = match self.peek().clone() {
                    Tok::RawAsm(l) => {
                        self.bump();
                        l
                    }
                    _ => return self.expected("assembler text"),
                };
                self.skip_blank();
                self.expect_block_end("endasm")?;
                self.end_stmt()?;
                StmtKind::Asm { preserves, lines }
            }
            // `On n GoTo a, b, c` and `Branch n, a, b, c`: a jump to the n-th label (counting from 0); other values fall through.
            Tok::Ident(w) if (w.eq_ignore_ascii_case("on") && !matches!(self.peek_at(1), Tok::Punct("=" | ".")) && self.goto_on_line()) || (w.eq_ignore_ascii_case("branch") && !matches!(self.peek_at(1), Tok::Punct(_) | Tok::Colon | Tok::Newline | Tok::Eof)) => {
                let on = w.eq_ignore_ascii_case("on");
                self.bump();
                let subject = self.expr()?;
                let mut sub = false;
                if on {
                    sub = self.eat_kw("gosub");
                    if !sub {
                        self.expect_kw("goto")?;
                    }
                } else {
                    self.expect_punct(",")?;
                }
                let mut cases = Vec::new();
                loop {
                    let sp = self.span();
                    let l = self.ident()?;
                    let value = Expr { id: self.id(), span: sp, kind: ExprKind::Int(cases.len() as u64) };
                    cases.push(Case { conds: vec![CaseCond::Value(value)], body: vec![Stmt { span: sp, kind: if sub { StmtKind::GoSub(l) } else { StmtKind::GoTo(l) } }], span: sp });
                    if !self.eat_punct(",") {
                        break;
                    }
                }
                self.end_stmt()?;
                StmtKind::Select { subject, cases, otherwise: None }
            }
            // `Let x = 1`: report it and read the assignment.
            Tok::Ident(w) if w.eq_ignore_ascii_case("let") && matches!(self.peek_at(1), Tok::Ident(_)) && matches!(self.peek_at(2), Tok::Punct("=" | "(" | ".")) => {
                let sp = self.span();
                self.bump();
                self.hint(sp, "`Let` is not used here", "leave it out: an assignment is written `x = 1`");
                return self.stmt_inner();
            }
            // `Call Name(args)`: the same as `Name(args)`. `Call` is not reserved: a variable or routine of that name still works.
            Tok::Ident(w) if w.eq_ignore_ascii_case("call") && matches!(self.peek_at(1), Tok::Ident(_)) => {
                self.bump();
                let d = self.designator()?;
                self.end_stmt()?;
                StmtKind::Call(d)
            }
            Tok::Ident(_) if self.at_line_start() && matches!(self.peek_at(1), Tok::Colon) && matches!(self.peek_at(2), Tok::Newline | Tok::Eof) => {
                let l = self.ident()?;
                self.bump(); // the colon
                StmtKind::Label(l)
            }
            Tok::Ident(_) | Tok::Kw(_) if self.starts_designator() => {
                let d = self.designator()?;
                if self.eat_punct("=") {
                    let value = self.expr()?;
                    self.end_stmt()?;
                    StmtKind::Assign { target: d, value }
                } else {
                    // A hint explains the line; the statement is dropped so it gives no second error.
                    if !self.at_eol() && !self.unwinding && self.statement_shape_hint(&d) {
                        return Err(());
                    }
                    self.end_stmt()?;
                    StmtKind::Call(d)
                }
            }
            Tok::Kw(k) => {
                let msg = if DECL_STARTERS.contains(&k) || k == "event" {
                    format!("declarations must come before the first executable statement (found `{k}`)")
                } else {
                    format!("`{k}` cannot start a statement")
                };
                return self.fail(if DECL_STARTERS.contains(&k) { "E-ORDER" } else { "E-SYNTAX" }, msg);
            }
            _ => return self.expected("a statement"),
        };
        Ok(Stmt { span, kind })
    }

    /// After a designator statement that is followed by more than the end of the line: the
    /// forms other languages use for `x += 1`, `x++` and `Print x`, reported with the spelling
    /// here; true when one was given. The caller's `end_stmt` reports anything else.
    fn statement_shape_hint(&mut self, d: &Designator) -> bool {
        let name = d.head.name.clone();
        let sp = self.span();
        let op = match (self.peek(), self.peek_at(1)) {
            (Tok::Punct(o @ ("+" | "-" | "*" | "/")), Tok::Punct("=")) => Some(*o),
            _ => None,
        };
        if let Some(o) = op {
            let extra = match o {
                "+" => format!(" (or `Inc({name}, …)`)"),
                "-" => format!(" (or `Dec({name}, …)`)"),
                _ => String::new(),
            };
            self.hint(sp, format!("`{o}=` is not an operator here"), format!("write `{name} = {name} {o} …`{extra}"));
            self.sync();
            return true;
        }
        if let (Tok::Punct(o @ ("+" | "-")), Tok::Punct(o2)) = (self.peek(), self.peek_at(1))
            && o == o2
        {
            let f = if *o == "+" { "Inc" } else { "Dec" };
            self.hint(sp, format!("`{o}{o}` is not an operator here"), format!("write `{f}({name})`"));
            self.sync();
            return true;
        }
        // `High 1`, `Print x`: a call with its arguments not in parentheses.
        if d.parts.is_empty() && matches!(self.peek(), Tok::Ident(_) | Tok::Int(_) | Tok::Float(_) | Tok::Str(_) | Tok::CharCode(_)) {
            let shown = match crate::lexer::keyword(&name.to_ascii_lowercase()) {
                Some(k) => crate::suggest::pretty(k),
                None => name.clone(),
            };
            self.hint(sp, format!("unexpected {} after `{shown}`", self.describe()), format!("a call puts its arguments in parentheses: `{shown}(…)`"));
            self.sync();
            return true;
        }
        false
    }

    /// Whether a `GoTo` comes before the end of the line (`On n GoTo ...`, where `On` may be followed by a parenthesis).
    fn goto_on_line(&self) -> bool {
        let mut n = 1;
        loop {
            match self.peek_at(n) {
                Tok::Kw("goto" | "gosub") => return true,
                Tok::Newline | Tok::Eof | Tok::Colon => return false,
                _ => n += 1,
            }
            if self.pos + n >= self.toks.len() {
                return false;
            }
        }
    }

    fn starts_designator(&self) -> bool {
        match self.peek() {
            Tok::Ident(_) => true,
            Tok::Kw(k) => CALLABLE_KEYWORDS.contains(k) || *k == "result",
            _ => false,
        }
    }

    fn if_stmt(&mut self) -> PResult<StmtKind> {
        self.bump();
        let cond = self.expr()?;
        if self.eat_kw("goto") {
            let label = self.ident()?;
            self.end_stmt()?;
            return Ok(StmtKind::IfGoto { cond, label });
        }
        // `If cond GoSub label` is an `If` whose only statement is the `GoSub`.
        if self.peek() == &Tok::Kw("gosub") {
            let sp = self.span();
            self.bump();
            let label = self.ident()?;
            self.end_stmt()?;
            return Ok(StmtKind::If { arms: vec![(cond, vec![Stmt { span: sp, kind: StmtKind::GoSub(label) }])], otherwise: None });
        }
        let mut arms = Vec::new();
        let mut otherwise = None;
        self.then_or_eol()?;
        if !self.at_eol() {
            return self.fail("E-SYNTAX", "a single-line `If … Then statement` is not supported; put the statements on their own lines, or use `If … GoTo label`");
        }
        self.end_stmt()?;
        let mut cur = cond;
        loop {
            let body = self.block(&["elseif", "else", "endif"])?;
            arms.push((cur, body));
            match self.block_word() {
                Some(("elseif", _)) => {
                    self.bump();
                    cur = self.expr()?;
                    self.then_or_eol()?;
                    self.end_stmt()?;
                }
                Some(("else", _)) if matches!(self.peek_at(1), Tok::Kw("if")) => {
                    // `Else If` as two words: read it as `ElseIf`, which is what it means.
                    let sp = self.span();
                    self.bump();
                    self.bump();
                    self.hint(sp, "`Else If` is written as one word here", "write `ElseIf`; two words would open a second `If` that needs its own `End If`");
                    cur = self.expr()?;
                    self.then_or_eol()?;
                    self.end_stmt()?;
                }
                Some(("else", _)) => {
                    self.bump();
                    self.end_stmt()?;
                    otherwise = Some(self.block(&["endif"])?);
                    self.expect_block_end("endif")?;
                    break;
                }
                _ => {
                    self.expect_block_end("endif")?;
                    break;
                }
            }
        }
        self.end_stmt()?;
        Ok(StmtKind::If { arms, otherwise })
    }

    /// `Then` after an `If` or `ElseIf` condition. A missing `Then` at the end of the line is
    /// reported and the `If` read on as if it were there, so its body and `End If` do not
    /// give errors of their own.
    fn then_or_eol(&mut self) -> PResult<()> {
        if self.eat_kw("then") {
            return Ok(());
        }
        if self.at_eol() && !self.unwinding {
            let sp = self.span();
            self.hint(sp, "expected `Then` at the end of the condition", "an `If` condition ends with `Then`: `If x = 3 Then`, with the statements on the lines below and `End If` after them");
            return Ok(());
        }
        self.expected("`Then`")
    }

    fn select_stmt(&mut self) -> PResult<StmtKind> {
        self.bump();
        if self.at_kw("case") {
            let sp = self.span();
            self.bump();
            self.hint(sp, "`Select` is followed by the value itself", "write `Select x`, without `Case`; each branch below still starts with `Case`");
        }
        let subject = self.expr()?;
        self.end_stmt()?;
        let mut cases = Vec::new();
        let mut otherwise = None;
        self.skip_blank();
        if !matches!(self.block_word(), Some(("case" | "else" | "endselect", _))) {
            return self.expected("`Case`");
        }
        loop {
            self.skip_blank();
            let sp = self.span();
            match self.block_word() {
                Some(("case", _)) => {
                    self.bump();
                    if self.eat_kw("else") {
                        self.end_stmt()?;
                        otherwise = Some(self.block(&["endselect"])?);
                        break;
                    }
                    let mut conds = Vec::new();
                    loop {
                        conds.push(self.case_cond()?);
                        if !self.eat_punct(",") {
                            break;
                        }
                    }
                    self.end_stmt()?;
                    let body = self.block(&["case", "else", "endselect"])?;
                    cases.push(Case { conds, body, span: sp });
                }
                Some(("else", _)) => {
                    self.bump();
                    self.end_stmt()?;
                    otherwise = Some(self.block(&["endselect"])?);
                    break;
                }
                _ => break,
            }
        }
        self.expect_block_end("endselect")?;
        self.end_stmt()?;
        Ok(StmtKind::Select { subject, cases, otherwise })
    }

    fn case_cond(&mut self) -> PResult<CaseCond> {
        let op = match self.peek() {
            Tok::Punct("=" | "==") => Some(BinOp::Eq),
            Tok::Punct("<>" | "!=") => Some(BinOp::Ne),
            Tok::Punct("<") => Some(BinOp::Lt),
            Tok::Punct(">") => Some(BinOp::Gt),
            Tok::Punct("<=") => Some(BinOp::Le),
            Tok::Punct(">=") => Some(BinOp::Ge),
            _ => None,
        };
        if let Some(op) = op {
            self.bump();
            return Ok(CaseCond::Rel(op, self.expr()?));
        }
        let lo = self.expr()?;
        if self.eat_kw("to") { Ok(CaseCond::Range(lo, self.expr()?)) } else { Ok(CaseCond::Value(lo)) }
    }

    /// `Do … Loop` forms, rewritten into the core loops: `Do … Loop` is `While True`,
    /// `Do While c` is `While c`, `Do Until c` is `While Not c`, `Loop Until c` is
    /// `Repeat … Until c` and `Loop While c` is `Repeat … Until Not c`.
    fn do_loop(&mut self) -> PResult<StmtKind> {
        let do_span = self.span();
        self.bump();
        let top = if self.eat_kw("while") {
            Some((false, self.expr()?))
        } else if self.eat_kw("until") {
            Some((true, self.expr()?))
        } else {
            None
        };
        self.end_stmt()?;
        let body = self.block(&["loop"])?;
        self.expect_block_end("loop")?;
        // While unwinding, an `Until` here closes an outer `Repeat`, not this loop.
        let bottom = if self.unwinding {
            None
        } else if self.eat_kw("until") {
            Some((true, self.expr()?))
        } else if self.eat_kw("while") {
            Some((false, self.expr()?))
        } else {
            None
        };
        self.end_stmt()?;
        let negate = |me: &mut Self, e: Expr| Expr { id: me.id(), span: e.span, kind: ExprKind::Unary(UnOp::Not, Box::new(e)) };
        match (top, bottom) {
            (Some(_), Some(_)) => {
                self.diags.error("E-SYNTAX", do_span, "a Do loop can test at the top or at the bottom, not both");
                Err(())
            }
            (Some((until, c)), None) => {
                let cond = if until { negate(self, c) } else { c };
                Ok(StmtKind::While { cond, body })
            }
            (None, Some((until, c))) => {
                let until_cond = if until { c } else { negate(self, c) };
                Ok(StmtKind::Repeat { body, until: until_cond })
            }
            (None, None) => {
                let cond = Expr { id: self.id(), span: do_span, kind: ExprKind::Bool(true) };
                Ok(StmtKind::While { cond, body })
            }
        }
    }

    // ---- expressions ---------------------------------------------------------------------

    pub fn expr(&mut self) -> PResult<Expr> {
        self.binary_level(0)
    }

    fn binary_level(&mut self, level: usize) -> PResult<Expr> {
        // Lowest precedence first: Or/Xor, And, relational, shifts, additive, multiplicative.
        const LEVELS: usize = 6;
        if level == LEVELS {
            return self.unary();
        }
        let lhs_starts_not = matches!(self.peek(), Tok::Kw("not"));
        let mut lhs = self.binary_level(level + 1)?;
        let mut first = true;
        loop {
            let op = match (level, self.peek()) {
                (0, Tok::Kw("or")) => BinOp::Or,
                (0, Tok::Kw("xor")) => BinOp::Xor,
                (1, Tok::Kw("and")) => BinOp::And,
                (2, Tok::Punct("=" | "==")) => BinOp::Eq,
                (2, Tok::Punct("<>" | "!=")) => BinOp::Ne,
                (2, Tok::Punct("<")) => BinOp::Lt,
                (2, Tok::Punct(">")) => BinOp::Gt,
                (2, Tok::Punct("<=")) => BinOp::Le,
                (2, Tok::Punct(">=")) => BinOp::Ge,
                (3, Tok::Punct("<<")) => BinOp::Shl,
                (3, Tok::Punct(">>")) => BinOp::Shr,
                (4, Tok::Punct("+")) => BinOp::Add,
                (4, Tok::Punct("-")) => BinOp::Sub,
                (5, Tok::Punct("*")) => BinOp::Mul,
                (5, Tok::Punct("/")) => BinOp::Div,
                (5, Tok::Kw("mod")) => BinOp::Mod,
                _ => return Ok(lhs),
            };
            let span = self.bump().span;
            let rhs = self.binary_level(level + 1)?;
            // `Not x = 5` (no parentheses) is `(Not x) = 5`: remember it for W-NOTCMP. A `(Not x)`
            // starts with `(`, so the first token tells the two apart.
            let bare_not = level == 2 && first && lhs_starts_not && matches!(lhs.kind, ExprKind::Unary(UnOp::Not, _));
            first = false;
            lhs = Expr { id: self.id(), span, kind: ExprKind::Binary(op, Box::new(lhs), Box::new(rhs)) };
            if bare_not {
                self.bare_not_cmp.push(lhs.id);
            }
            // The relational level is not associative: `a < b < c` is rejected.
            if level == 2 && matches!(self.peek(), Tok::Punct("=" | "==" | "<>" | "!=" | "<" | ">" | "<=" | ">=")) {
                return self.fail("E-SYNTAX", "comparisons cannot be chained; use `And` to combine them");
            }
        }
    }

    fn unary(&mut self) -> PResult<Expr> {
        let op = match self.peek() {
            Tok::Punct("-") => Some(UnOp::Neg),
            Tok::Punct("+") => Some(UnOp::Plus),
            Tok::Kw("not") => Some(UnOp::Not),
            Tok::Punct("@") => Some(UnOp::AddressOf),
            _ => None,
        };
        if let Some(op) = op {
            let span = self.bump().span;
            let inner = self.unary()?;
            return Ok(Expr { id: self.id(), span, kind: ExprKind::Unary(op, Box::new(inner)) });
        }
        self.primary()
    }

    fn primary(&mut self) -> PResult<Expr> {
        let span = self.span();
        let kind = match self.peek().clone() {
            Tok::Int(v) => {
                self.bump();
                ExprKind::Int(v)
            }
            Tok::Float(v) => {
                self.bump();
                ExprKind::Float(v)
            }
            Tok::Str(s) => {
                self.bump();
                ExprKind::Str(s)
            }
            Tok::CharCode(c) => {
                self.bump();
                ExprKind::Char(c)
            }
            Tok::Kw("true") => {
                self.bump();
                ExprKind::Bool(true)
            }
            Tok::Kw("false") => {
                self.bump();
                ExprKind::Bool(false)
            }
            Tok::Kw("null") => {
                self.bump();
                ExprKind::Null
            }
            Tok::Punct("(") => {
                self.bump();
                let e = self.expr()?;
                self.expect_punct(")")?;
                return Ok(e);
            }
            _ if self.starts_designator() => ExprKind::Designator(self.designator()?),
            _ => return self.expected("an expression"),
        };
        Ok(Expr { id: self.id(), span, kind })
    }

    pub fn designator(&mut self) -> PResult<Designator> {
        let span = self.span();
        let head = match self.peek().clone() {
            Tok::Ident(_) => self.ident()?,
            Tok::Kw(k) if CALLABLE_KEYWORDS.contains(&k) || k == "result" => {
                let sp = self.bump().span;
                Ident { name: k.to_string(), span: sp }
            }
            _ => return self.expected("a name"),
        };
        let mut parts = Vec::new();
        loop {
            if self.at_punct(".") {
                self.bump();
                match self.peek().clone() {
                    Tok::Int(v) => {
                        let sp = self.bump().span;
                        parts.push(Part::BitIndex(v, sp));
                    }
                    _ => parts.push(Part::Member(self.name_or_kw()?)),
                }
            } else if self.at_punct("(") {
                let sp = self.bump().span;
                let mut args = Vec::new();
                if !self.at_punct(")") {
                    loop {
                        args.push(self.expr()?);
                        if !self.eat_punct(",") {
                            break;
                        }
                    }
                }
                self.expect_punct(")")?;
                parts.push(Part::Args(args, sp));
            } else {
                break;
            }
        }
        Ok(Designator { id: self.id(), span, head, parts })
    }
}

fn pretty_word(w: &str) -> String {
    if w == "elseif" {
        return "ElseIf".into();
    }
    match w.strip_prefix("end") {
        Some(rest) if !rest.is_empty() && w != "end" => {
            let mut c = rest.chars();
            let first = c.next().unwrap().to_ascii_uppercase();
            format!("End {first}{}", c.as_str())
        }
        _ => {
            let mut c = w.chars();
            match c.next() {
                Some(f) => format!("{}{}", f.to_ascii_uppercase(), c.as_str()),
                None => String::new(),
            }
        }
    }
}
