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
    /// Further places worth looking at ("declared here", "opened here"), or remarks with no place.
    pub notes: Vec<Note>,
    /// Suggested fixes, printed as `help:` lines under the source line.
    pub help: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct Note {
    pub span: Option<Span>,
    pub msg: String,
}

impl Diagnostic {
    /// Adds a note that points at another place in the source.
    pub fn note(&mut self, span: Span, msg: impl Into<String>) -> &mut Self {
        self.notes.push(Note { span: Some(span), msg: msg.into() });
        self
    }
    /// Adds a remark with no place of its own.
    pub fn remark(&mut self, msg: impl Into<String>) -> &mut Self {
        self.notes.push(Note { span: None, msg: msg.into() });
        self
    }
    /// Adds a suggested fix.
    pub fn help(&mut self, msg: impl Into<String>) -> &mut Self {
        self.help.push(msg.into());
        self
    }
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
    /// The text of every file loaded, as written (before preprocessing).
    pub fn texts(&self) -> impl Iterator<Item = &str> {
        self.files.iter().map(|f| f.1.as_str())
    }
    pub fn names(&self) -> impl Iterator<Item = &str> {
        self.files.iter().map(|f| f.0.as_str())
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
        self.push(Severity::Error, code, span, msg.into());
    }
    pub fn warn(&mut self, code: &'static str, span: Span, msg: impl Into<String>) {
        self.push(Severity::Warning, code, span, msg.into());
    }
    /// Records an error and returns it to take `.note(..)`, `.remark(..)` and `.help(..)`.
    pub fn error_with(&mut self, code: &'static str, span: Span, msg: impl Into<String>) -> &mut Diagnostic {
        self.push(Severity::Error, code, span, msg.into())
    }
    /// Records a warning and returns it to take `.note(..)`, `.remark(..)` and `.help(..)`.
    pub fn warn_with(&mut self, code: &'static str, span: Span, msg: impl Into<String>) -> &mut Diagnostic {
        self.push(Severity::Warning, code, span, msg.into())
    }
    fn push(&mut self, severity: Severity, code: &'static str, span: Span, msg: String) -> &mut Diagnostic {
        self.items.push(Diagnostic { severity, code, msg, span, notes: Vec::new(), help: Vec::new() });
        self.items.last_mut().unwrap()
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

/// Renders `file:line:col: error[CODE]: message`, the source line with the token at the column
/// underlined, `  = help:` lines, then each note (`file:line:col: note: ...` with its own source
/// line when it has a place, `  = note: ...` when it has none). Only the first line has the
/// `error[`/`warning[` shape that editors match on. Source lines are indented four spaces, so a
/// line starting `  = ` is always a help or a note, never program text.
pub struct Render<'a>(pub &'a Diagnostic, pub &'a SourceMap);

/// Width of the token that starts at 1-based `col` of `line`: a name or number, a quoted
/// string, or one character. Zero when the column is past the end of the line.
fn token_width(line: &str, col: u32) -> usize {
    let rest: Vec<char> = line.chars().skip(col.saturating_sub(1) as usize).collect();
    let Some(&c) = rest.first() else { return 0 };
    if c == '"' {
        return rest.iter().skip(1).position(|&x| x == '"').map_or(rest.len(), |p| p + 2);
    }
    let word = |x: &char| x.is_alphanumeric() || matches!(x, '_' | '$' | '%' | '#' | '.');
    if word(&c) {
        let n = rest.iter().take_while(|x| word(x)).count();
        // `a.b` underlines only `a`; a member is reported at its own column.
        let first = rest.iter().take(n).position(|&x| x == '.' ).filter(|&p| p > 0 && !c.is_ascii_digit()).unwrap_or(n);
        return first;
    }
    1
}

fn source_line(f: &mut fmt::Formatter<'_>, sm: &SourceMap, span: Span) -> fmt::Result {
    if let Some(line) = sm.line_text(span) {
        let line = line.replace('\t', " ");
        let pad = " ".repeat(span.col.saturating_sub(1) as usize);
        let marks = "^".repeat(token_width(&line, span.col).max(1));
        write!(f, "\n    {}\n    {pad}{marks}", line.trim_end())?;
    }
    Ok(())
}

impl fmt::Display for Render<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let (d, sm) = (self.0, self.1);
        let sev = match d.severity {
            Severity::Error => "error",
            Severity::Warning => "warning",
        };
        write!(f, "{}:{}:{}: {sev}[{}]: {}", sm.name(d.span.file), d.span.line, d.span.col, d.code, d.msg)?;
        source_line(f, sm, d.span)?;
        for h in &d.help {
            write!(f, "\n  = help: {h}")?;
        }
        for n in &d.notes {
            match n.span {
                Some(s) => {
                    write!(f, "\n{}:{}:{}: note: {}", sm.name(s.file), s.line, s.col, n.msg)?;
                    source_line(f, sm, s)?;
                }
                None => write!(f, "\n  = note: {}", n.msg)?,
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::token_width;

    #[test]
    fn token_widths() {
        assert_eq!(token_width("countr = 5", 1), 6);
        assert_eq!(token_width("x = \"abc\" + y", 5), 5);
        assert_eq!(token_width("If i = 3", 9), 0);
        assert_eq!(token_width("a = b + c", 7), 1);
        assert_eq!(token_width("PORTB.0 = 1", 1), 5);
        assert_eq!(token_width("x = 1.5", 5), 3);
    }
}
