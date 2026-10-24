//! Diagnostics: source positions, error/warning records and their rendering.

use std::fmt;

/// A position in a source file. `file` indexes `SourceMap`; `line` and `col` are 1-based.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Span {
    pub file: u32,
    pub line: u32,
    pub col: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
}

#[derive(Clone, Debug)]
pub struct Diagnostic {
    pub severity: Severity,
    /// Stable identifier such as `E-TYPE` or `W-NARROW`; tests match on it.
    pub code: &'static str,
    pub msg: String,
    pub span: Span,
}

#[derive(Default)]
pub struct SourceMap {
    files: Vec<(String, String)>,
}

impl SourceMap {
    pub fn add(&mut self, name: String, text: String) -> u32 {
        self.files.push((name, text));
        (self.files.len() - 1) as u32
    }
    pub fn name(&self, file: u32) -> &str {
        self.files.get(file as usize).map(|f| f.0.as_str()).unwrap_or("<unknown>")
    }
    pub fn line_text(&self, span: Span) -> Option<&str> {
        let text = &self.files.get(span.file as usize)?.1;
        text.lines().nth(span.line.checked_sub(1)? as usize)
    }
}

#[derive(Default)]
pub struct Diagnostics {
    pub items: Vec<Diagnostic>,
}

impl Diagnostics {
    pub fn error(&mut self, code: &'static str, span: Span, msg: impl Into<String>) {
        self.items.push(Diagnostic { severity: Severity::Error, code, msg: msg.into(), span });
    }
    pub fn warn(&mut self, code: &'static str, span: Span, msg: impl Into<String>) {
        self.items.push(Diagnostic { severity: Severity::Warning, code, msg: msg.into(), span });
    }
    pub fn has_errors(&self) -> bool {
        self.items.iter().any(|d| d.severity == Severity::Error)
    }
    pub fn error_count(&self) -> usize {
        self.items.iter().filter(|d| d.severity == Severity::Error).count()
    }
    pub fn codes(&self) -> Vec<&'static str> {
        self.items.iter().map(|d| d.code).collect()
    }
    pub fn has_code(&self, code: &str) -> bool {
        self.items.iter().any(|d| d.code == code)
    }
}

/// Renders `file:line:col: error[CODE]: message` followed by the source line and a caret.
pub struct Render<'a>(pub &'a Diagnostic, pub &'a SourceMap);

impl fmt::Display for Render<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let (d, sm) = (self.0, self.1);
        let sev = match d.severity {
            Severity::Error => "error",
            Severity::Warning => "warning",
        };
        write!(f, "{}:{}:{}: {sev}[{}]: {}", sm.name(d.span.file), d.span.line, d.span.col, d.code, d.msg)?;
        if let Some(line) = sm.line_text(d.span) {
            let pad = " ".repeat(d.span.col.saturating_sub(1) as usize);
            write!(f, "\n    {line}\n    {pad}^")?;
        }
        Ok(())
    }
}
