//! Back-end tests (milestone M4).
//!
//! * Every program in `tests/valid` either compiles and assembles with pic-as without a single
//!   warning, or is rejected only with `E-BACKEND` (features scheduled for M5/M6).
//! * The reset vector is pinned at address 0 in the produced hex.
//! * With `BASICC_MDB=1` the programs in `tests/exec` are run in the MPLAB X simulator and their
//!   results checked (`scripts/exec-test.py`); that takes minutes, so it is opt-in.

use std::path::{Path, PathBuf};
use std::process::Command;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn basicc() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_basicc"))
}

fn scratch(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("basicc-test-{}", std::process::id())).join(name);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn have_pic_as() -> bool {
    basicc::driver::find_pic_as().is_some()
}

fn bas_files(dir: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).filter(|p| p.extension().is_some_and(|e| e == "bas")).collect();
    v.sort();
    v
}

/// Programs in `tests/valid` that use features scheduled for M5/M6; they must be rejected with
/// `E-BACKEND` and nothing else. Anything not listed here must build.
const DEFERRED: &[&str] = &[
    "arrays_and_strings", "bit_array_warning", "byref_parameters", "byrefconst_string_any_size", "constants", "conversions",
    "disable_frees_priority", "events", "float_math", "interrupts", "modifiers", "single_interrupt", "structures_and_unions",
];

#[test]
fn valid_programs_assemble_or_are_deferred() {
    if !have_pic_as() {
        eprintln!("pic-as not installed; skipping");
        return;
    }
    let out = scratch("valid");
    let mut built = 0;
    let mut failures = Vec::new();
    for f in bas_files(&root().join("tests/valid")) {
        let name = f.file_stem().unwrap().to_string_lossy().into_owned();
        let hex = out.join(format!("{name}.hex"));
        let r = Command::new(basicc()).arg(&f).arg("-o").arg(&hex).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        if r.status.success() {
            built += 1;
            if text.lines().any(|l| l.starts_with("pic-as:")) {
                failures.push(format!("{name}: pic-as complained:\n{text}"));
            }
            let h = std::fs::read_to_string(&hex).unwrap();
            // Reset vector: the first record starts at address 0000.
            if !h.lines().any(|l| l.starts_with(":") && l.len() > 9 && &l[3..7] == "0000" && &l[7..9] == "00") {
                failures.push(format!("{name}: nothing at the reset vector"));
            }
        } else {
            let errs: Vec<&str> = text.lines().filter(|l| l.contains(": error[")).collect();
            if !DEFERRED.contains(&name.as_str()) {
                failures.push(format!("{name}: should build but failed:\n{text}"));
            } else if errs.is_empty() || !errs.iter().all(|l| l.contains("error[E-BACKEND]")) {
                failures.push(format!("{name}: unexpected failure:\n{text}"));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
    assert!(built >= 25, "only {built} programs built");
}

#[test]
fn unsupported_features_are_reported_not_miscompiled() {
    let out = scratch("unsupported");
    let src = out.join("u.bas");
    std::fs::write(&src, "Program T\nDevice = 18F27Q10\nDim f As Float\nf = 1.5\n").unwrap();
    let r = Command::new(basicc()).arg(&src).arg("-S").output().unwrap();
    assert!(!r.status.success());
    assert!(String::from_utf8_lossy(&r.stderr).contains("E-BACKEND"));
}

#[test]
fn reentrant_routines_are_rejected() {
    let out = scratch("reentrant");
    let src = out.join("r.bas");
    std::fs::write(&src, "Program T\nDevice = 18F27Q10\nDim r As Word\nReentrant Function F(ByVal n As Byte) As Word\n If n <= 1 Then\n Result = 1\n Else\n Result = n * F(n - 1)\n End If\nEnd Function\nr = F(5)\n").unwrap();
    let r = Command::new(basicc()).arg(&src).arg("-S").output().unwrap();
    assert!(!r.status.success());
    assert!(String::from_utf8_lossy(&r.stderr).contains("E-BACKEND"));
}

#[test]
fn exec_programs_in_simulator() {
    if std::env::var("BASICC_MDB").is_err() {
        eprintln!("set BASICC_MDB=1 to run the simulator tests");
        return;
    }
    let files: Vec<PathBuf> = bas_files(&root().join("tests/exec"));
    let r = Command::new("python3")
        .arg(root().join("scripts/exec-test.py"))
        .arg("--basicc")
        .arg(basicc())
        .args(&files)
        .output()
        .unwrap();
    let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
    assert!(r.status.success(), "{text}");
}
