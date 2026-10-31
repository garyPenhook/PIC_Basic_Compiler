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
}

const DECL_STARTERS: &[&str] =
    &["public", "private", "const", "dim", "static", "volatile", "structure", "type", "sub", "function", "proc", "inline", "noinline", "reentrant", "interrupt", "symbol"];

const TYPE_KEYWORDS: &[&str] = &["boolean", "bit", "byte", "shortint", "word", "integer", "longword", "longint", "float", "char", "string"];

pub fn parse_unit(file: u32, toks: Vec<Token>, diags: &mut Diagnostics, next_id: &mut NodeId) -> Unit {
    let mut p = Parser { toks, pos: 0, file, diags, next_id };
    p.unit()
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
        if !lexed {
            self.diags.error(code, sp, msg);
        }
        Err(())
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
                    _ => return Some(("end", 1)),
                };
                Some((w, 2))
            }
            _ => None,
        }
    }
    fn expect_block_end(&mut self, word: &str) -> PResult<()> {
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

    // ---- compilation unit ----------------------------------------------------------------

    fn unit(&mut self) -> Unit {
        let mut unit = Unit { kind: UnitKind::Program, name: None, file: self.file, headers: vec![], includes: vec![], decls: vec![], stmts: vec![] };
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
                    self.bump();
                    self.skip_blank();
                    if !self.at_eof() {
                        let found = self.describe();
                        self.diags.error("E-SYNTAX", self.span(), format!("unexpected {found} after the final `End`"));
                    }
                    self.pos = self.toks.len() - 1;
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
        Ok(if up.starts_with("PIC") { up } else { format!("PIC{up}") })
    }

    // ---- declarations --------------------------------------------------------------------

    fn decl(&mut self) -> PResult<Decl> {
        let span = self.span();
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
    fn body(&mut self, end: &str) -> PResult<Body> {
        let mut decls = Vec::new();
        let mut stmts = Vec::new();
        loop {
            self.skip_blank();
            if self.at_eof() {
                return self.expected(&format!("`{}`", pretty_word(end)));
            }
            if matches!(self.block_word(), Some((w, _)) if w == end) {
                break;
            }
            let start = self.pos;
            let sp = self.span();
            let r: PResult<()> = (|| {
                if let Some((w, _)) = self.block_word() {
                    let msg = format!("unexpected `{}`", pretty_word(w));
                    self.diags.error("E-SYNTAX", sp, msg);
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
    fn block(&mut self, stops: &[&str]) -> PResult<Vec<Stmt>> {
        let mut out = Vec::new();
        loop {
            self.skip_blank();
            if self.at_eof() {
                let want = stops.iter().map(|s| format!("`{}`", pretty_word(s))).collect::<Vec<_>>().join(" or ");
                return self.fail("E-SYNTAX", format!("block is not closed: expected {want} before the end of the file"));
            }
            let start = self.pos;
            let sp = self.span();
            if let Some((w, _)) = self.block_word() {
                if stops.contains(&w) {
                    return Ok(out);
                }
                self.diags.error("E-SYNTAX", sp, format!("unexpected `{}`", pretty_word(w)));
                self.sync();
                continue;
            }
            match self.stmt() {
                Ok(s) => out.push(s),
                Err(()) => {
                    self.sync();
                    if self.pos == start {
                        self.bump();
                    }
                }
            }
        }
    }

    fn stmt(&mut self) -> PResult<Stmt> {
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
                self.end_stmt()?;
                StmtKind::Exit
            }
            Tok::Kw("goto") => {
                self.bump();
                let l = self.ident()?;
                self.end_stmt()?;
                StmtKind::GoTo(l)
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
        let mut arms = Vec::new();
        let mut otherwise = None;
        self.expect_kw("then")?;
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
                    self.expect_kw("then")?;
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

    fn select_stmt(&mut self) -> PResult<StmtKind> {
        self.bump();
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
            Tok::Punct("=") => Some(BinOp::Eq),
            Tok::Punct("<>") => Some(BinOp::Ne),
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
        let bottom = if self.eat_kw("until") {
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
        let mut lhs = self.binary_level(level + 1)?;
        loop {
            let op = match (level, self.peek()) {
                (0, Tok::Kw("or")) => BinOp::Or,
                (0, Tok::Kw("xor")) => BinOp::Xor,
                (1, Tok::Kw("and")) => BinOp::And,
                (2, Tok::Punct("=")) => BinOp::Eq,
                (2, Tok::Punct("<>")) => BinOp::Ne,
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
            lhs = Expr { id: self.id(), span, kind: ExprKind::Binary(op, Box::new(lhs), Box::new(rhs)) };
            // The relational level is not associative: `a < b < c` is rejected.
            if level == 2 && matches!(self.peek(), Tok::Punct("=" | "<>" | "<" | ">" | "<=" | ">=")) {
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
