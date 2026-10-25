//! Corpus tests for the front end (milestone M3).
//!
//! Every `.bas` file under `tests/valid` must check without errors and produce exactly the
//! warnings named on its `' warn:` line. Every file under `tests/negative` must produce exactly
//! the error codes named on its `' expect:` line. Directories under `tests/projects` are
//! multi-file programs (`main.bas` plus modules) judged the same way.

use basil::diag::{Diagnostics, Render, Severity};
use basil::project::{LoadConfig, load};
use basil::sema::{Analysis, SemaConfig, analyze};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

struct Outcome {
    errors: BTreeSet<String>,
    warnings: BTreeSet<String>,
    rendered: String,
    analysis: Analysis,
}

fn check(path: &Path) -> Outcome {
    let mut diags = Diagnostics::default();
    let dir = path.parent().unwrap().to_path_buf();
    let proj = load(path, &LoadConfig { lib_dirs: vec![dir, root().join("lib")], defines: vec![] }, &mut diags);
    let analysis = analyze(&proj, &SemaConfig { devices_dirs: vec![root().join("devices")] }, &mut diags);
    let mut out = Outcome { errors: BTreeSet::new(), warnings: BTreeSet::new(), rendered: String::new(), analysis };
    for d in &diags.items {
        match d.severity {
            Severity::Error => out.errors.insert(d.code.to_string()),
            Severity::Warning => out.warnings.insert(d.code.to_string()),
        };
        out.rendered.push_str(&format!("{}\n", Render(d, &proj.sources)));
    }
    out
}

fn header(path: &Path, key: &str) -> BTreeSet<String> {
    let text = std::fs::read_to_string(path).unwrap();
    let mut set = BTreeSet::new();
    for line in text.lines().take_while(|l| l.starts_with('\'')) {
        if let Some(rest) = line.trim_start_matches('\'').trim().strip_prefix(key) {
            set.extend(rest.split_whitespace().map(str::to_string));
        }
    }
    set
}

fn bas_files(dir: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).filter(|p| p.extension().is_some_and(|e| e == "bas")).collect();
    v.sort();
    v
}

#[test]
fn valid_programs_check_cleanly() {
    let mut failures = Vec::new();
    let files = bas_files(&root().join("tests/valid"));
    assert!(files.len() >= 20, "corpus went missing");
    for f in &files {
        let o = check(f);
        let want = header(f, "warn:");
        if !o.errors.is_empty() || o.warnings != want {
            failures.push(format!("{}: errors {:?}, warnings {:?} (wanted {:?})\n{}", f.display(), o.errors, o.warnings, want, o.rendered));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn negative_programs_report_the_expected_errors() {
    let mut failures = Vec::new();
    let files = bas_files(&root().join("tests/negative"));
    assert!(files.len() >= 50, "corpus went missing");
    for f in &files {
        let o = check(f);
        let want = header(f, "expect:");
        assert!(!want.is_empty(), "{} has no `' expect:` line", f.display());
        if o.errors != want {
            failures.push(format!("{}: got {:?}, wanted {:?}\n{}", f.display(), o.errors, want, o.rendered));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn multi_file_projects() {
    let dir = root().join("tests/projects");
    let mut n = 0;
    let mut failures = Vec::new();
    for e in std::fs::read_dir(&dir).unwrap() {
        let p = e.unwrap().path();
        let main = p.join("main.bas");
        if !main.is_file() {
            continue;
        }
        n += 1;
        let o = check(&main);
        let want = header(&main, "expect:");
        if o.errors != want || (want.is_empty() && o.warnings != header(&main, "warn:")) {
            failures.push(format!("{}: errors {:?} (wanted {:?}), warnings {:?}\n{}", p.display(), o.errors, want, o.warnings, o.rendered));
        }
    }
    assert!(n >= 4, "project corpus went missing");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn analysis_records_types_and_widths() {
    let o = check(&root().join("tests/valid/widths.bas"));
    let a = &o.analysis;
    assert!(a.device.as_ref().is_some_and(|d| d.device.name == "PIC18F27Q10"));
    // `w = b1 * b2` is evaluated at 16 bits: some arithmetic node carries width 16.
    assert!(a.widths.values().any(|w| *w == 16), "no 16-bit evaluation width recorded: {:?}", a.widths);
    assert!(a.widths.values().any(|w| *w == 8));
    assert!(!a.types.is_empty());
}

#[test]
fn config_settings_are_resolved_against_the_device() {
    let o = check(&root().join("tests/valid/blink.bas"));
    let c = &o.analysis.config;
    assert_eq!(c.len(), 4);
    let rst = c.iter().find(|s| s.field == "RSTOSC").expect("RSTOSC resolved");
    // Data sheet Table 5-1: HFINTOSC_64MHZ is encoded 000 (docs/PROGRESS.md, M2).
    assert_eq!(rst.value, 0);
    assert_eq!(o.analysis.clock_mhz, Some(64.0));
}

/// No input, however broken, may make the front end panic or hang: feed it every prefix of
/// every valid program, and every program with one line removed.
#[test]
fn damaged_input_never_panics() {
    use basil::project::load_text;
    let mut runs = 0;
    for f in bas_files(&root().join("tests/valid")).into_iter().chain(bas_files(&root().join("tests/negative"))) {
        let text = std::fs::read_to_string(&f).unwrap();
        let mut variants: Vec<String> = Vec::new();
        for (i, _) in text.char_indices().step_by(3) {
            variants.push(text[..i].to_string());
        }
        let lines: Vec<&str> = text.lines().collect();
        for skip in 0..lines.len() {
            let v: Vec<&str> = lines.iter().enumerate().filter(|(i, _)| *i != skip).map(|(_, l)| *l).collect();
            variants.push(v.join("\n"));
        }
        for v in variants {
            let mut diags = Diagnostics::default();
            let proj = load_text("damaged.bas", &v, &mut diags);
            let _ = analyze(&proj, &SemaConfig { devices_dirs: vec![root().join("devices")] }, &mut diags);
            runs += 1;
        }
    }
    assert!(runs > 1000);
}
