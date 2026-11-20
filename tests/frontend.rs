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
    let proj = load(path, &LoadConfig { lib_dirs: vec![dir, root().join("lib")], defines: vec![], devices_dirs: vec![root().join("devices")], optimise: true }, &mut diags);
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

/// The text of every `' says:` header line: each must appear somewhere in the rendered
/// diagnostics, so that help lines and notes are tested and not just codes.
fn says(path: &Path) -> Vec<String> {
    let text = std::fs::read_to_string(path).unwrap();
    text.lines().take_while(|l| l.starts_with('\'')).filter_map(|l| l.trim_start_matches('\'').trim().strip_prefix("says:")).map(|r| r.trim().to_string()).collect()
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
        for line in says(f) {
            if !o.rendered.contains(&line) {
                failures.push(format!("{}: output does not contain {line:?}\n{}", f.display(), o.rendered));
            }
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

/// Every example of `basil --explain`: the wrong program raises its code, the right one compiles
/// without errors and without that code.
#[test]
fn explain_examples() {
    let dir = std::env::temp_dir().join(format!("basil-explain-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let mut failures = Vec::new();
    for (i, e) in basil::explain::ENTRIES.iter().enumerate() {
        for (text, want) in [(e.wrong, true), (e.right, false)] {
            let prog = format!("Program T\nDevice = 18F27Q10\n{text}\nEnd\n");
            let path = dir.join(format!("x{i}_{want}.bas"));
            std::fs::write(&path, &prog).unwrap();
            let o = check(&path);
            let has = o.errors.contains(e.code) || o.warnings.contains(e.code);
            if has != want || (!want && !o.errors.is_empty()) {
                failures.push(format!("{} ({}):\n{prog}\n{}", e.code, if want { "wrong" } else { "right" }, o.rendered));
            }
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// A project `lib/` holding a byte-identical copy of a built-in module must not make that module load twice:
/// `oled` (found in the built-in folder) includes the built-in `i2c`, the program includes the copy.
#[test]
fn identical_module_copy_is_loaded_once() {
    let dir = std::env::temp_dir().join(format!("basil_dup_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("lib")).unwrap();
    std::fs::copy(root().join("lib/i2c.bas"), dir.join("lib/i2c.bas")).unwrap();
    let main = dir.join("main.bas");
    std::fs::write(&main, "Device = 18F25K22\nClock = 16\nInclude \"i2c\"\nInclude \"oled\"\nDim x As Byte\nx = 1\n").unwrap();
    let mut diags = Diagnostics::default();
    let proj = load(&main, &LoadConfig { lib_dirs: vec![dir.join("lib"), root().join("lib")], defines: vec![], devices_dirs: vec![root().join("devices")], optimise: true }, &mut diags);
    let copies = proj.units.iter().filter(|u| u.path.file_name().is_some_and(|f| f == "i2c.bas")).count();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(copies, 1, "i2c.bas was loaded {copies} times");
}

/// Two files with the same name and text whose includes resolve to different modules are not the same module.
#[test]
fn same_text_module_with_different_includes_is_loaded_twice() {
    let dir = std::env::temp_dir().join(format!("basil_dup2_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    for d in ["a", "b"] {
        std::fs::create_dir_all(dir.join(d)).unwrap();
        std::fs::write(dir.join(d).join("mid.bas"), "Module mid\nInclude \"leaf\"\nEnd Module\n").unwrap();
    }
    std::fs::write(dir.join("a/leaf.bas"), "Module leaf\nDim la As Byte\nEnd Module\n").unwrap();
    std::fs::write(dir.join("b/leaf.bas"), "Module leaf\nDim lb As Byte\nEnd Module\n").unwrap();
    std::fs::write(dir.join("b/wrap.bas"), "Module wrap\nInclude \"mid\"\nEnd Module\n").unwrap();
    std::fs::write(dir.join("a/main.bas"), "Device = 18F25K22\nClock = 16\nInclude \"mid\"\nInclude \"wrap\"\n").unwrap();
    let mut diags = Diagnostics::default();
    let proj = load(&dir.join("a/main.bas"), &LoadConfig { lib_dirs: vec![dir.join("b"), root().join("lib")], defines: vec![], devices_dirs: vec![root().join("devices")], optimise: true }, &mut diags);
    let mids = proj.units.iter().filter(|u| u.path.file_name().is_some_and(|f| f == "mid.bas")).count();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(mids, 2, "mid.bas copies with different leaf modules were merged");
}
