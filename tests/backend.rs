//! Back-end tests (milestone M4).
//!
//! * Every program in `tests/valid` either compiles and assembles with pic-as without a single
//!   warning, or is rejected only with `E-BACKEND` (features scheduled for M5/M6).
//! * The reset vector is pinned at address 0 in the produced hex.
//! * With `BASIL_MDB=1` the programs in `tests/exec` are run in the MPLAB X simulator and their
//!   results checked (`scripts/exec-test.py`); that takes minutes, so it is opt-in.

use std::path::{Path, PathBuf};
use std::process::Command;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn basil() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_basil"))
}

fn scratch(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("basil-test-{}", std::process::id())).join(name);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn have_pic_as() -> bool {
    basil::driver::find_pic_as().is_some()
}

fn bas_files(dir: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).filter(|p| p.extension().is_some_and(|e| e == "bas")).collect();
    v.sort();
    v
}

/// Programs in `tests/valid` that use features scheduled for M5/M6; they must be rejected with
/// `E-BACKEND` and nothing else. Anything not listed here must build.
const DEFERRED: &[&str] = &[
    "conversions",
    "events", "float_math", "modifiers",
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
        let r = Command::new(basil()).arg(&f).arg("-o").arg(&hex).output().unwrap();
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
    std::fs::write(&src, "Program T\nDevice = 18F27Q10\nDim i As Byte\nDim j As Bit\nj = Bit(i)\n").unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(!r.status.success());
    assert!(String::from_utf8_lossy(&r.stderr).contains("E-BACKEND"));
}

#[test]
fn float_programs_build_with_the_float_module() {
    let out = scratch("floatbuild");
    let src = out.join("f.bas");
    std::fs::write(&src, "Program T\nDevice = 18F27Q10\nDim f As Float\nDim n As Byte\nf = 1.5\nf = f * 2 + 1\nn = Byte(f)\n").unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(out.join("f.S")).unwrap();
    assert!(asm.contains("FLOATLIB_FMUL") && asm.contains("FLOATLIB_FTOLONG"));
    assert!(!asm.contains("FLOATLIB_FDIV"), "unused Float routines must not be linked");
}

#[test]
fn float_work_in_a_handler_must_go_through_save() {
    let out = scratch("floatisr");
    let head = "Program T\nDevice = 18F27Q10\nDim f As Float\nDim g As Float\nFunction Work() As Float\n Result = f * 2\nEnd Function\n";
    let bad = format!("{head}Interrupt Hi(ipHigh)\n PIR0.0 = 0\n g = f * 2\nEnd Interrupt\nf = 1.5\n");
    let good = format!("{head}Interrupt Hi(ipHigh)\n PIR0.0 = 0\n Save(0, Work)\n  g = Work()\n Restore\nEnd Interrupt\nf = 1.5\n");
    let src = out.join("b.bas");
    std::fs::write(&src, bad).unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(!r.status.success());
    assert!(String::from_utf8_lossy(&r.stderr).contains("E-ISR-CALL"));
    std::fs::write(&src, good).unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
}

#[test]
fn structure_fields_picked_at_run_time_are_reported_not_miscompiled() {
    let out = scratch("structidx");
    let src = out.join("s.bas");
    let prog = "Program T\nDevice = 18F27Q10\nStructure TS\n Tag As String(4)\n V As Byte\n F As V.0\nEnd Structure\nDim a(3) As TS\nDim i As Byte\nDim s As String(8)\ni = 1\n";
    for stmt in ["a(i).Tag = \"x\"", "s = a(i).Tag + \"!\""] {
        std::fs::write(&src, format!("{prog}{stmt}\n")).unwrap();
        let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
        assert!(!r.status.success(), "{stmt} should be rejected");
        assert!(String::from_utf8_lossy(&r.stderr).contains("E-BACKEND"), "{stmt}");
    }
}

/// Word addresses of the `;SYM name 0xADDR` lines (byte addresses) in generated assembly.
fn sym_addrs(asm: &str) -> std::collections::HashMap<String, u32> {
    asm.lines()
        .filter_map(|l| {
            let mut w = l.strip_prefix(";SYM ")?.split_whitespace();
            Some((w.next()?.to_string(), u32::from_str_radix(w.next()?.strip_prefix("0x")?, 16).ok()?))
        })
        .collect()
}

#[test]
fn interrupt_vectors_are_pinned_and_frames_never_overlay_a_handler() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("vectors");
    // One handler: it sits right at the high vector, nothing at the low one.
    let one = root().join("tests/valid/single_interrupt.bas");
    let r = Command::new(basil()).arg(&one).arg("-o").arg(out.join("one.hex")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(out.join("one.S")).unwrap();
    assert_eq!(sym_addrs(&asm)["__ISR_H"], 0x08);
    assert!(!asm.contains("__v_lo"));
    assert!(asm.contains("bsf INTCON, 7") && !asm.contains("bsf INTCON, 5"), "IPEN stays off with one unprioritised handler");
    // Two priorities: both vectors jump, IPEN is switched on, only the high handler may use the
    // hardware shadow registers.
    let two = root().join("tests/valid/interrupts.bas");
    let r = Command::new(basil()).arg(&two).arg("-o").arg(out.join("two.hex")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(out.join("two.S")).unwrap();
    let a = sym_addrs(&asm);
    assert_eq!((a["__v_hi"], a["__v_lo"]), (0x08, 0x18));
    assert!(asm.contains("bsf INTCON, 5"), "IPEN");
    assert_eq!(asm.matches("retfie f").count(), 1);
    assert!(asm.contains("movff BSR, __ISV"), "the low handler saves BSR in software");
}

#[test]
fn handler_frames_are_never_shared() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("isrframes");
    let src = out.join("h.bas");
    // The handler's local and the sibling routines' locals must not overlay: the handler can run
    // at any time. (A and B are siblings and may share; H may not share with either.)
    let prog = "Program T\nDevice = 18F27Q10\nDim g As Byte\nSub A()\n Dim x As Byte\n x = 1\n g = x\nEnd Sub\nSub B()\n Dim y As Byte\n y = 2\n g = y\nEnd Sub\nInterrupt H()\n Dim z As Byte\n z = 3\n g = z\nEnd Interrupt\nA()\nB()\nEnable(H)\n";
    std::fs::write(&src, prog).unwrap();
    let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join("h.hex")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let a = data_addrs(&std::fs::read_to_string(out.join("h.S")).unwrap());
    assert_eq!(a["T_A__X"], a["T_B__Y"], "siblings should still overlay");
    assert_ne!(a["T_H__Z"], a["T_A__X"], "a handler frame overlays main-line storage");
}

#[test]
fn jumps_into_or_out_of_save_are_reported() {
    let out = scratch("savegoto");
    let src = out.join("g.bas");
    std::fs::write(&src, "Program T\nDevice = 18F27Q10\nDim g As Byte\nInterrupt H()\n Save(0)\n Goto done\n Restore\n done:\nEnd Interrupt\nEnable(H)\n").unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(!r.status.success());
    assert!(String::from_utf8_lossy(&r.stderr).contains("E-BACKEND"));
}

/// Every library module in one program builds, with no warning from the compiler or pic-as.
#[test]
fn library_modules_build_cleanly() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("library");
    let r = Command::new(basil())
        .arg(root().join("tests/programs/library_all.bas"))
        .arg("-L")
        .arg(root().join("lib"))
        .arg("-o")
        .arg(out.join("lib.hex"))
        .output()
        .unwrap();
    let text = String::from_utf8_lossy(&r.stderr).into_owned();
    assert!(r.status.success(), "{text}");
    assert!(!text.contains("warning"), "{text}");
}

#[test]
fn reentrant_routines_are_rejected() {
    let out = scratch("reentrant");
    let src = out.join("r.bas");
    std::fs::write(&src, "Program T\nDevice = 18F27Q10\nDim r As Word\nReentrant Function F(ByVal n As Byte) As Word\n If n <= 1 Then\n Result = 1\n Else\n Result = n * F(n - 1)\n End If\nEnd Function\nr = F(5)\n").unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(!r.status.success());
    assert!(String::from_utf8_lossy(&r.stderr).contains("E-BACKEND"));
}

/// Addresses of the one-byte `NAME equ 0x...` data lines in generated assembly.
fn data_addrs(asm: &str) -> std::collections::HashMap<String, u32> {
    asm.lines()
        .filter_map(|l| {
            let mut w = l.split_whitespace();
            let (name, kw, val) = (w.next()?, w.next()?, w.next()?);
            if kw != "equ" || name.starts_with("__") {
                return None;
            }
            Some((name.to_string(), u32::from_str_radix(val.strip_prefix("0x")?, 16).ok()?))
        })
        .collect()
}

#[test]
fn frames_overlay_only_when_never_live_together() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("overlay");
    let hex = out.join("overlay.hex");
    let r = Command::new(basil()).arg(root().join("tests/exec/overlay.bas")).arg("-S").arg("-o").arg(&hex).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let a = data_addrs(&std::fs::read_to_string(out.join("overlay.S")).unwrap());
    // Siblings (neither calls the other) share storage.
    assert_eq!(a["T_DIRTY__Q"], a["T_ZA__Q"], "sibling frames should overlay");
    // A routine and the routine it calls never do: Sum3 is live while F1 runs.
    let sum3 = ["T_SUM3__S", "T_SUM3__K", "T_SUM3__RESULT", "T_SUM3__H1"].map(|n| a[n]);
    let f1 = ["T_F1__X", "T_F1__RESULT", "T_F1__T"].map(|n| a[n]);
    for x in sum3 {
        assert!(!f1.contains(&x), "caller and callee frames overlap at {x:#x}");
    }
    // Nor do the chain Outer -> Mid -> Inner.
    let chain = [["T_OUTER__O", "T_OUTER__X", "T_OUTER__RESULT"], ["T_MID__M", "T_MID__X", "T_MID__RESULT"], ["T_INNER__T", "T_INNER__X", "T_INNER__RESULT"]];
    for i in 0..3 {
        for j in i + 1..3 {
            for x in chain[i] {
                assert!(!chain[j].iter().any(|y| a[*y] == a[x]), "{x} overlaps {}", chain[j].iter().find(|y| a[**y] == a[x]).unwrap());
            }
        }
    }
}

/// The simulator tests run twice: optimised, and as the `-O0` reference build the optimiser is
/// differential-tested against (PLAN §7A.1).
#[test]
fn exec_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files: Vec<PathBuf> = bas_files(&root().join("tests/exec"));
    for flags in ["", "-O0"] {
        let r = Command::new("python3")
            .arg(root().join("scripts/exec-test.py"))
            .arg("--basil")
            .arg(basil())
            .arg(format!("--flags={flags}"))
            .args(&files)
            .output()
            .unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
}

/// A chain of `n` nested subroutines called from the main program, plus an interrupt handler when
/// `isr` is set (its entry takes one more level of the 31-level hardware stack).
fn chain_program(n: u32, isr: bool) -> String {
    let mut s = String::from("Program T\nDevice = 18F27Q10\nDim g As Byte\n");
    for i in (1..=n).rev() {
        s += &format!("Sub S{i}()\n");
        s += &if i < n { format!(" S{}()\n", i + 1) } else { " g = g + 1\n".to_string() };
        s += "End Sub\n";
    }
    if isr {
        s += "Interrupt H()\n g = g + 1\nEnd Interrupt\nEnable(H)\n";
    }
    s + "S1()\n"
}

#[test]
fn hardware_stack_depth_is_checked() {
    let out = scratch("stackdepth");
    let src = out.join("s.bas");
    for (n, isr, ok) in [(31, false, true), (32, false, false), (30, true, true), (31, true, false)] {
        std::fs::write(&src, chain_program(n, isr)).unwrap();
        let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
        let err = String::from_utf8_lossy(&r.stderr).into_owned();
        assert_eq!(r.status.success(), ok, "chain {n}, isr {isr}: {err}");
        if !ok {
            assert!(err.contains("E-STACK"), "{err}");
        }
    }
}
