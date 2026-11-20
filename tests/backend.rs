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
    // under target/tmp (cargo's CARGO_TARGET_TMPDIR), not the /tmp tmpfs: nothing tears these down after a run
    let d = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(format!("basil-test-{}", std::process::id())).join(name);
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
    "float_math", "modifiers",
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
    assert!(asm.contains("FLOATLIB_FSCALE") && asm.contains("FLOATLIB_FTOLONG"));
    assert!(!asm.contains("FLOATLIB_FMUL") && !asm.contains("FLOATLIB_FDIV"), "unused Float routines must not be linked");
}

/// The Float special cases (`FScale`, `FSign`, `FFromByte`) add a routine each, so a program only gets one when its
/// call sites save more than the routine costs, or when it lets the general routine drop out.
#[test]
fn float_special_cases_are_used_only_when_they_save_space() {
    let out = scratch("floatplan");
    let src = out.join("p.bas");
    let head = "Program T\nDevice = 18F27Q10\nDim f As Float\nDim g As Float\nDim h As Float\nDim b As Byte\nDim n As Byte\nf = 1.5\ng = 2.5\nb = 7\n";
    let build = |body: &str| {
        std::fs::write(&src, format!("{head}{body}")).unwrap();
        let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
        assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
        std::fs::read_to_string(out.join("p.S")).unwrap()
    };
    // One doubling next to a general multiply: FScale would only add 53 words.
    let asm = build("h = f * g\nh = f * 2.0\n");
    assert!(asm.contains("FLOATLIB_FMUL") && !asm.contains("FLOATLIB_FSCALE"));
    // Doublings only: FMul drops out.
    let asm = build("h = f * 2.0\nh = f / 4.0\n");
    assert!(asm.contains("FLOATLIB_FSCALE") && !asm.contains("FLOATLIB_FMUL") && !asm.contains("FLOATLIB_FDIV"));
    // A compare with zero next to a general compare, and alone.
    let asm = build("If f > g Then\n n = 1\nEnd If\nIf f > 0.0 Then\n n = 2\nEnd If\n");
    assert!(asm.contains("FLOATLIB_CMP") && !asm.contains("FLOATLIB_FSIGN"));
    let asm = build("If f > 0.0 Then\n n = 2\nEnd If\n");
    assert!(asm.contains("FLOATLIB_FSIGN") && !asm.contains("FLOATLIB_CMP"));
    // One Byte source next to a LongInt one keeps the general conversion.
    let asm = build("h = b\nh = Float(LongInt(n) - 1000)\n");
    assert!(asm.contains("FLOATLIB_FFROMLONG") && !asm.contains("FLOATLIB_FFROMBYTE"));
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
fn string_fields_and_elements_picked_at_run_time_build() {
    let out = scratch("structidx");
    let src = out.join("s.bas");
    let prog = "Program T\nDevice = 18F27Q10\nStructure TS\n Tag As String(4)\n V As Byte\n F As V.0\nEnd Structure\nDim a(3) As TS\nDim n(3) As String(8)\nDim k(3) As Byte\nDim i As Byte\nDim s As String(8)\ni = 1\n";
    for stmt in ["a(i).Tag = \"x\"", "s = a(i).Tag + \"!\"", "n(i) = s", "s = n(i)"] {
        std::fs::write(&src, format!("{prog}{stmt}\n")).unwrap();
        let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
        assert!(r.status.success(), "{stmt}: {}", String::from_utf8_lossy(&r.stderr));
    }
    // An index that itself reads an array is worked out first, in an assignment and in a comparison.
    std::fs::write(&src, format!("{prog}n(k(i)) = s\ns = n(k(i))\nIf n(k(i)) = s Then\n i = 2\nEnd If\n")).unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
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
    // -O0: the optimiser folds these toy locals away, and the test is about frame layout.
    let r = Command::new(basil()).arg(&src).arg("-O0").arg("-o").arg(out.join("h.hex")).output().unwrap();
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

/// Every program under `examples/` (any depth) builds, with no warning from the compiler or pic-as.
#[test]
fn examples_build() {
    if !have_pic_as() {
        return;
    }
    fn walk(dir: &Path, v: &mut Vec<PathBuf>) {
        for e in std::fs::read_dir(dir).unwrap() {
            let p = e.unwrap().path();
            if p.is_dir() {
                walk(&p, v);
            } else if p.extension().is_some_and(|e| e == "bas") {
                v.push(p);
            }
        }
    }
    let mut files = Vec::new();
    walk(&root().join("examples"), &mut files);
    files.sort();
    assert!(!files.is_empty(), "no programs under examples/");
    let out = scratch("examples");
    let mut failures = Vec::new();
    for f in &files {
        let name = f.strip_prefix(root().join("examples")).unwrap().to_string_lossy().replace(['/', '\\'], "_");
        let r = Command::new(basil()).arg(f).arg("-o").arg(out.join(format!("{name}.hex"))).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        if !r.status.success() || text.contains("warning") {
            failures.push(format!("{}:\n{text}", f.display()));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// A global that every reachable store sets to a constant (`opt::global_value_sets`): a comparison that cannot
/// be true for any of those values goes with its `If` arm, so a mode only an uncalled routine sets costs nothing.
/// Each case writes $A5 to PORTA in the arm that tests for that mode; the arm must stay whenever the values are
/// not all known.
#[test]
fn a_mode_no_reachable_code_sets_drops_its_branch() {
    let out = scratch("valuesets");
    let src = out.join("v.bas");
    let asm = |decl: &str, extra: &str, body: &str| -> String {
        let prog = format!(
            "Program T\nDevice = 18F27Q10\n{decl}\nSub StartB()\n mode = 2\nEnd Sub\nSub StartA()\n mode = 1\nEnd Sub\n{extra}\nStartA()\n{body}\nIf mode = 2 Then\n PORTA = $A5\nElseIf mode = 1 Then\n PORTA = $3C\nEnd If\n"
        );
        std::fs::write(&src, prog).unwrap();
        let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
        assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
        std::fs::read_to_string(out.join("v.S")).unwrap().to_lowercase()
    };
    let byte = "Dim mode As Byte";
    // StartB is never called: mode is 0 or 1, the test for 2 goes, the one for 1 stays.
    let a = asm(byte, "", "");
    assert!(!a.contains("0xa5") && a.contains("0x3c"), "{a}");
    // Called: 2 is a value it can hold.
    assert!(asm(byte, "", "StartB()").contains("0xa5"));
    // Volatile, a store that is not a constant (here from a handler), Inc, an address taken, or a name in Asm: unknown.
    assert!(asm("Volatile Dim mode As Byte", "", "").contains("0xa5"));
    assert!(asm(byte, "Interrupt H()\n mode = PORTB\nEnd Interrupt\n", "Enable(H)").contains("0xa5"));
    assert!(asm(byte, "", "Inc(mode)").contains("0xa5"));
    assert!(asm(&format!("{byte}\nDim p As Word"), "", "p = AddressOf(mode)").contains("0xa5"));
    assert!(asm(byte, "", "Asm\n movlw 2\n movwf T_MODE, c\nEnd Asm").contains("0xa5"));
    // Linked with C (here an `Export` routine C may call): C code may write any global by name.
    assert!(asm(byte, "Export Sub Poke()\n mode = 1\nEnd Sub\n", "").contains("0xa5"));
}

/// A helper that answers with `retlw` (the PIC16 string compare) moved into its only caller (`Acc`, called twice so it
/// stays a routine) by
/// `codegen::inline_single_calls` must not return from the caller: before the fix the `If` after the compare was lost and
/// `hits` was never set.
#[test]
fn an_inlined_retlw_helper_does_not_return_from_its_caller() {
    let out = scratch("inline_retlw");
    let src = out.join("r.bas");
    std::fs::write(&src, "Program T\nDevice = 16F17146\nClock = 32\nDim hits As Byte\nSub Acc(ByRefConst s As String(16))\n If s = \"hello\" Then\n  hits = 1\n End If\nEnd Sub\nAcc(\"hello\")\nAcc(\"hi\")\nPORTA = hits\n").unwrap();
    let r = Command::new(basil()).arg(&src).arg("--keep-vars").arg("-S").output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(out.join("r.S")).unwrap();
    let body: String = asm.lines().skip_while(|l| !l.starts_with("T_ACC:")).skip(1).take_while(|l| !l.starts_with("__") && !l.trim_start().starts_with("; helper") && !l.trim_start().starts_with("; Sub/Function")).collect::<Vec<_>>().join("\n");
    assert!(!body.contains("retlw"), "{body}");
    assert!(body.contains("movwf T_HITS"), "{body}");
}

#[test]
fn reentrant_routines_use_a_software_stack_and_only_then() {
    let out = scratch("reentrant");
    let src = out.join("r.bas");
    let prog = |attr: &str| format!("Program T\nDevice = 18F27Q10\nDim r As Word\n{attr}Function F(ByVal n As Byte) As Word\n If n <= 1 Then\n Result = 1\n Else\n Result = n * F(n - 1)\n End If\nEnd Function\nr = F(5)\n");
    std::fs::write(&src, prog("Reentrant ")).unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(out.join("r.S")).unwrap();
    assert!(asm.contains("__SWSTK") && asm.contains("PREINC2") && asm.contains("POSTDEC2"));
    // Without the attribute recursion is still refused, and a program that does not recurse has no stack.
    std::fs::write(&src, prog("")).unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(!r.status.success() && String::from_utf8_lossy(&r.stderr).contains("E-RECURSION"));
    let plain = root().join("tests/exec/funcs.bas");
    let r = Command::new(basil()).arg(&plain).arg("-S").arg("-o").arg(out.join("plain.hex")).output().unwrap();
    assert!(r.status.success());
    assert!(!std::fs::read_to_string(out.join("plain.S")).unwrap().contains("__SWSTK"));
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
    let r = Command::new(basil()).arg(root().join("tests/exec/overlay.bas")).arg("-O0").arg("-S").arg("-o").arg(&hex).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let a = data_addrs(&std::fs::read_to_string(out.join("overlay.S")).unwrap());
    // Siblings (neither calls the other) share storage.
    assert_eq!(a["T_DIRTY__Q"], a["T_ZA__Q"], "sibling frames should overlay");
    // A routine and the routine it calls never do: Sum3 is live while F1 runs.
    let sum3 = ["T_SUM3__S", "T_SUM3__K", "T_SUM3__RESULT"].map(|n| a[n]);
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

/// The RTCC drivers (`rtcc`, `rtccspi`) against software models of the chips: the folder holds test doubles for `I2c`, `Spi` and
/// `Pinio` next to the programs, and symlinks to the modules under test, so the programs run the real driver logic. Optimised, and as the
/// `-O0` reference build.
#[test]
fn rtcc_models_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files: Vec<PathBuf> = bas_files(&root().join("tests/exec_rtcc")).into_iter().filter(|p| p.file_name().unwrap().to_string_lossy().starts_with("lib_")).collect();
    assert_eq!(files.len(), 3);
    // `lib_rtcc_model_hw` uses `#option I2c = Hardware`, which only a part with the I2C1 peripheral honours: it runs on the PIC18F16Q41 (the
    // harness carries the included test double with the program), the others on the default PIC18F27Q10.
    let (hw, sw): (Vec<PathBuf>, Vec<PathBuf>) = files.into_iter().partition(|p| p.file_stem().unwrap().to_string_lossy().ends_with("_hw"));
    assert_eq!(hw.len(), 1);
    for flags in ["", "-O0"] {
        for (device, list) in [("18F27Q10", &sw), ("18F16Q41", &hw)] {
            let r = Command::new("python3")
                .arg(root().join("scripts/exec-test.py"))
                .arg("--basil")
                .arg(basil())
                .arg(format!("--flags={flags}"))
                .arg("--device")
                .arg(device)
                .args(list)
                .output()
                .unwrap();
            let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
            assert!(r.status.success(), "flags `{flags}`, {device}:\n{text}");
        }
    }
}

/// The graphic LCD module `glcd` against software models of the three controllers (KS0108, T6963C, ST7920): each folder holds a
/// `pinio.bas` test double that carries the chip model, and a symlink to `lib/glcd.bas`, so the programs run the real driver logic
/// (pixels, lines, boxes, circles, bytes, text, the controller initialisation). Optimised, and as the `-O0` reference build.
#[test]
fn glcd_models_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    for dir in ["tests/exec_glcd_ks", "tests/exec_glcd_t69", "tests/exec_glcd_st79"] {
        let files: Vec<PathBuf> = bas_files(&root().join(dir)).into_iter().filter(|p| p.file_name().unwrap().to_string_lossy().starts_with("lib_")).collect();
        assert_eq!(files.len(), 1, "{dir}");
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
            assert!(r.status.success(), "{dir}, flags `{flags}`:\n{text}");
        }
    }
}

/// The e-paper module `epaper` against a software model of the SSD1680 (`tests/exec_epaper/pinio.bas` and `spi.bas` replace `Pinio` and
/// `Spi`; `epaper.bas` is a symlink to `lib/epaper.bas`). Optimised, and as the `-O0` reference build.
#[test]
fn epaper_model_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files: Vec<PathBuf> = bas_files(&root().join("tests/exec_epaper")).into_iter().filter(|p| p.file_name().unwrap().to_string_lossy().starts_with("lib_")).collect();
    assert_eq!(files.len(), 1);
    for flags in ["", "-O0"] {
        let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).args(&files).output().unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
}

/// The `pulse`, `irremote` and `x10` routines against a model of the pins: `tests/exec_pins/pinio.bas` replaces `Pinio` (a poll of the
/// pin steps a waveform, X-10 bursts are recorded and played back), and the modules under test are symlinked next to the program.
/// Optimised, and as the `-O0` reference build.
#[test]
fn pin_models_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files: Vec<PathBuf> = bas_files(&root().join("tests/exec_pins")).into_iter().filter(|p| p.file_name().unwrap().to_string_lossy().starts_with("lib_")).collect();
    assert_eq!(files.len(), 1);
    for flags in ["", "-O0"] {
        let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).args(&files).output().unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
}

/// The DMA model that gives the simulator tests a DMA engine (`scripts/dma_sim.py`) against the data sheet's rules.
#[test]
fn dma_model_unit_tests() {
    let r = Command::new("python3").arg(root().join("scripts/test_dma_sim.py")).output().unwrap();
    let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
    assert!(r.status.success(), "{text}");
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

/// A main program of `n` nested `GoSub`s: each subroutine adds one level of the hardware stack.
fn gosub_chain_program(n: u32) -> String {
    let mut s = String::from("Program T\nDevice = 18F27Q10\nDim g As Byte\nGoSub S1\nGoTo Done\n");
    for i in 1..=n {
        s += &format!("S{i}:\n");
        s += &if i < n { format!("GoSub S{}\n", i + 1) } else { "g = g + 1\n".to_string() };
        s += "Return\n";
    }
    s + "Done:\n"
}

#[test]
fn gosub_levels_count_towards_the_hardware_stack() {
    let out = scratch("gosubdepth");
    let src = out.join("s.bas");
    for (n, ok) in [(31, true), (32, false)] {
        std::fs::write(&src, gosub_chain_program(n)).unwrap();
        let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
        let err = String::from_utf8_lossy(&r.stderr).into_owned();
        assert_eq!(r.status.success(), ok, "{n} nested GoSubs: {err}");
        if !ok {
            assert!(err.contains("E-STACK"), "{err}");
        }
    }
}

/// A constant baud rate and a literal passed to one routine fold away: no run-time divide, no RAM
/// copy of the string, and the transmit-ready wait is a bit test rather than a compare.
#[test]
fn constant_arguments_fold_into_the_callee() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("constfold");
    let src = out.join("c.bas");
    let prog = "Program T\nDevice = 18F27Q10\nClock = 64\nInclude \"serial\"\nSerial.SerialInit(115200)\nSerial.SerialWrite(\"tick\")\n";
    std::fs::write(&src, prog).unwrap();
    let r = Command::new(basil()).arg(&src).arg("-L").arg(root().join("lib")).arg("-o").arg(out.join("c.hex")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(out.join("c.S")).unwrap();
    assert!(!asm.contains("__div4"), "the baud divisor is a constant");
    assert!(!asm.contains("__strf1") && !asm.contains("__STRLIT"), "the literal is read from flash");
    assert!(asm.contains("movlw 0x8A"), "SP1BRGL holds the folded divisor");
    assert!(asm.contains("btfss PIR3, 4"), "TxIf = 0 is a bit test");
}

/// Several different literals passed to one routine share one flash table: still no RAM copies.
#[test]
fn several_literals_share_a_flash_table() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("lits");
    let src = out.join("l.bas");
    let prog = "Program T\nDevice = 18F27Q10\nClock = 64\nInclude \"serial\"\nSerial.SerialInit(9600)\nSerial.SerialWrite(\"one\")\nSerial.SerialWrite(\"three\")\nSerial.SerialWrite(\"one\")\n";
    std::fs::write(&src, prog).unwrap();
    let r = Command::new(basil()).arg(&src).arg("-L").arg(root().join("lib")).arg("-o").arg(out.join("l.hex")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(out.join("l.S")).unwrap();
    assert!(!asm.contains("__STRLIT") && !asm.contains("__strf1"), "no RAM copy of any literal");
    // "one\0three\0": one table, one copy of the repeated literal.
    assert!(asm.contains("db 0x6F, 0x6E, 0x65, 0x00, 0x74, 0x68, 0x72, 0x65, 0x65, 0x00"), "{asm}");
}


/// `EData` puts bytes in the data EEPROM image of the hex: byte addresses on the PIC18 (0x380000 on the Q41), word
/// addresses doubled on the PIC16 (0xF000 words = 0x1E000), the data in the low byte of each word.
#[test]
fn edata_lands_in_the_eeprom_image_of_the_hex() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("edata");
    // (device, hex address of the first byte, bytes at offset 0, bytes at offset 20)
    let cases: [(&str, u32, &str, &str); 4] = [
        ("18F27Q10", 0x31_0000, "0102034869", "AAFF"),
        ("18F16Q41", 0x38_0000, "0102034869", "AAFF"),
        ("16F18346", 0x1_E000, "01000200030048006900", "AA00FF00"),
        ("16F13245", 0x1_E000, "01000200030048006900", "AA00FF00"),
    ];
    for (dev, base, first, second) in cases {
        let src = out.join(format!("{dev}.bas"));
        std::fs::write(&src, format!("Device = {dev}\nClock = 8\nEData 1, 2, 3, \"Hi\"\nEData At 20, 0xAA, -1\nDim x As Byte\nx = 1\n")).unwrap();
        let hex = out.join(format!("{dev}.hex"));
        let r = Command::new(basil()).arg(&src).arg("-o").arg(&hex).output().unwrap();
        assert!(r.status.success(), "{dev}: {}", String::from_utf8_lossy(&r.stderr));
        // data records as (byte address, hex digits)
        let (mut ext, mut recs) = (0u32, Vec::new());
        for l in std::fs::read_to_string(&hex).unwrap().lines() {
            let b: Vec<u8> = (1..l.len() - 1).step_by(2).map(|i| u8::from_str_radix(&l[i..i + 2], 16).unwrap()).collect();
            match b[3] {
                4 => ext = (u32::from(b[4]) << 24) | (u32::from(b[5]) << 16),
                0 => recs.push((ext | (u32::from(b[1]) << 8) | u32::from(b[2]), b[4..4 + b[0] as usize].iter().map(|x| format!("{x:02X}")).collect::<String>())),
                _ => {}
            }
        }
        let at = |a: u32, want: &str| assert!(recs.iter().any(|(ra, d)| *ra == a && d == want), "{dev}: no record {want} at {a:#X}: {recs:?}");
        let step = if dev.starts_with("16") { 2 } else { 1 };
        at(base, first);
        at(base + 20 * step, second);
    }
}

/// `-g` points the asm's `#line` directives at the BASIC source and leaves the generated hex unchanged.
#[test]
fn debug_flag_maps_code_to_basic_lines_without_changing_the_hex() {
    let dir = scratch("debug_lines");
    let bas = dir.join("dbg.bas");
    std::fs::copy(root().join("tests/exec/arith_byte.bas"), &bas).unwrap();
    let run = |extra: &[&str], hex: &str| {
        let out = Command::new(basil()).args(extra).arg("-o").arg(dir.join(hex)).arg(&bas).output().unwrap();
        assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    };
    run(&["-S"], "plain.hex");
    let asm_plain = std::fs::read_to_string(dir.join("plain.S")).unwrap();
    run(&["-S", "-g"], "dbg.hex");
    let asm_dbg = std::fs::read_to_string(dir.join("dbg.S")).unwrap();
    assert!(!asm_plain.contains("#line ") && !asm_plain.contains("PSECT dbg"));
    assert!(asm_dbg.contains("PSECT dbg"), "no variable symbols");
    assert!(asm_dbg.lines().any(|l| l.starts_with("#line ") && l.contains("dbg.bas")), "no #line for the program");
    // Only the code differs in nothing but `#line` lines; `-g` also names the variables as symbols.
    let strip = |s: &str| s[s.find("PSECT code,").unwrap()..].lines().filter(|l| !l.starts_with("#line ")).collect::<Vec<_>>().join("\n");
    assert_eq!(strip(&asm_plain), strip(&asm_dbg), "-g changed the generated code");
}

/// `-g` appends a DWARF unit naming the program's variables and routines to the ELF.
#[test]
fn debug_flag_adds_variables_and_routines_to_the_elf() {
    if !have_pic_as() {
        return;
    }
    let dir = scratch("debug_vars");
    let bas = dir.join("vars.bas");
    std::fs::write(&bas, "Program T\nDevice = 18F27Q10\nClock = 1\nDim counter As Word = 0\nSub Bump(amount As Byte)\n    Dim local_tmp As Byte\n    local_tmp = amount\n    counter = counter + local_tmp\nEnd Sub\nDo\n    Bump(3)\n    LATC = Byte(counter)\nLoop\n").unwrap();
    let out = Command::new(basil()).arg("-g").arg(&bas).output().unwrap();
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    assert!(!String::from_utf8_lossy(&out.stderr).contains("no variable information"));
    let elf = std::fs::read(dir.join("vars.elf")).unwrap();
    let has = |needle: &[u8]| elf.windows(needle.len()).any(|w| w == needle);
    assert!(has(b"counter\0") && has(b"basil\0") && has(b"Word\0"), "variable and type names missing from the ELF");
    let plain = scratch("debug_vars_plain").join("vars.bas");
    std::fs::copy(&bas, &plain).unwrap();
    assert!(Command::new(basil()).arg(&plain).output().unwrap().status.success());
    let elf2 = std::fs::read(plain.with_extension("elf")).unwrap();
    assert!(!elf2.windows(6).any(|w| w == b"basil\0"), "plain build carries debug-only data");
}

/// Overlaid RAM symbols in this library-heavy K22 program used to make pic-as fail with error 1314.
#[test]
fn debug_flag_links_aht30_oled_with_overlaid_ram() {
    if !have_pic_as() {
        return;
    }
    let dir = scratch("debug_k22_overlay");
    for (name, flags) in [("optimized", vec!["-g"]), ("unoptimized", vec!["-g", "-O0"])] {
        let hex = dir.join(format!("{name}.hex"));
        let out = Command::new(basil())
            .args(flags)
            .arg("-o").arg(&hex)
            .arg(root().join("examples/PIC18F25K22/aht30/aht30_oled_display.bas"))
            .output().unwrap();
        assert!(out.status.success(), "{name}: {}", String::from_utf8_lossy(&out.stderr));
        assert!(hex.is_file());
        let elf = std::fs::read(hex.with_extension("elf")).unwrap();
        for name in [b"FmtBuf\0".as_slice(), b"WriteHundredths\0", b"basil\0"] {
            assert!(elf.windows(name.len()).any(|w| w == name), "debug name missing: {name:?}");
        }
    }
}

/// `-g` on an enhanced mid-range part: `#line` for the BASIC lines, and routines and variables in word / data addresses.
#[test]
fn debug_flag_on_pic16_adds_lines_routines_and_variables() {
    if !have_pic_as() {
        return;
    }
    let dir = scratch("debug_pic16");
    let bas = dir.join("p16.bas");
    std::fs::write(&bas, "Program T\nDevice = 16F17146\nDim counter As Byte\nSub Bump(amount As Byte)\n    Dim local_tmp As Byte\n    local_tmp = amount + 1\n    counter = local_tmp\nEnd Sub\ncounter = 5\nBump(counter)\nBump(counter)\nEnd\n").unwrap();
    let out = Command::new(basil()).arg("-g").arg(&bas).output().unwrap();
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(out.status.success() && !err.contains("warning"), "{err}");
    let asm = std::fs::read_to_string(dir.join("p16.S")).unwrap();
    assert!(asm.lines().any(|l| l.starts_with("#line 9 ") && l.contains("p16.bas")), "no #line for the program");
    let elf = std::fs::read(dir.join("p16.elf")).unwrap();
    let has = |needle: &[u8]| elf.windows(needle.len()).any(|w| w == needle);
    assert!(has(b"counter\0") && has(b"local_tmp\0") && has(b"Bump\0") && has(b"basil\0"), "names missing from the ELF");
    let plain = scratch("debug_pic16_plain").join("p16.bas");
    std::fs::copy(&bas, &plain).unwrap();
    assert!(Command::new(basil()).arg(&plain).output().unwrap().status.success());
    let asm2 = std::fs::read_to_string(plain.with_extension("S")).unwrap();
    let strip = |s: &str| s[s.find("PSECT code,").unwrap()..].lines().filter(|l| !l.starts_with("#line ")).collect::<Vec<_>>().join("\n");
    assert_eq!(strip(&asm), strip(&asm2), "-g changed the generated code");
}

// ---- PIC18-Q41 ---------------------------------------------------------------------------------

const Q41_PARTS: [&str; 6] = ["18F04Q41", "18F05Q41", "18F06Q41", "18F14Q41", "18F15Q41", "18F16Q41"];

/// A test program for another part: only its `Device` line changes.
fn for_device(src: &Path, device: &str, into: &Path) -> PathBuf {
    let text = std::fs::read_to_string(src).unwrap();
    let mut out = String::new();
    let mut done = false;
    for line in text.lines() {
        if !done && line.trim_start().to_ascii_lowercase().starts_with("device") {
            out += &format!("Device = {device}\n");
            done = true;
        } else {
            out += line;
            out.push('\n');
        }
    }
    std::fs::write(into, out).unwrap();
    into.to_path_buf()
}

/// The programs of `tests/exec` that touch no peripheral register build for every PIC18-Q41 part, with
/// handlers (the vectors hold a `goto`, the context is saved by the controller) and with data above 0FFFh.
#[test]
fn q41_parts_build_the_standard_programs() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("q41parts");
    let programs = ["arith_byte", "arith_word", "arith_longword", "arrays", "flow", "funcs", "isr_save", "isr_dual", "isr_single", "events_isr", "bit_packed_isr", "reentrant", "str_basic", "structs"];
    let mut failures = Vec::new();
    for dev in Q41_PARTS {
        for p in programs {
            let src = for_device(&root().join(format!("tests/exec/{p}.bas")), dev, &out.join(format!("{p}_{dev}.bas")));
            let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join(format!("{p}_{dev}.hex"))).output().unwrap();
            let text = String::from_utf8_lossy(&r.stderr).into_owned();
            // A program too big for the part's RAM is refused with E-RAM, which is the right answer.
            let too_big = text.contains("error[E-RAM]");
            if (!r.status.success() && !too_big) || text.contains("pic-as:") {
                failures.push(format!("{p} for {dev}:\n{text}"));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// Every library module builds on all six PIC18-Q41 parts.
#[test]
fn q41_library_modules_build() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("q41lib");
    for f in bas_files(&root().join("tests/exec_q41")) {
        let name = f.file_stem().unwrap().to_string_lossy().into_owned();
        let r = Command::new(basil()).arg(&f).arg("-o").arg(out.join(format!("{name}.hex"))).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        assert!(r.status.success() && !text.contains("warning"), "{name}:\n{text}");
    }
    for dev in Q41_PARTS {
        // `oled` and `aht30` do not fit the 1 KB parts.
        let all = root().join(if dev == "18F04Q41" || dev == "18F14Q41" { "tests/programs/library_q41_small.bas" } else { "tests/programs/library_q41.bas" });
        let src = for_device(&all, dev, &out.join(format!("library_{dev}.bas")));
        let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join(format!("library_{dev}.hex"))).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        assert!(r.status.success() && !text.contains("warning"), "{dev}:\n{text}");
    }
}

/// A part whose Access Bank is not at the top of the SFR space: `ANSELC` (0410h) is banked and needs `BSR`, while
/// `INTCON0` (04D6h) and `TRISC` (04C8h) are fast SFRs. The Q10 test "below the Access RAM's end" got this wrong.
#[test]
fn q41_low_sfrs_are_not_access_bank_operands() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("q41access");
    let src = out.join("t.bas");
    std::fs::write(&src, "Program T\nDevice = 18F16Q41\nClock = 1\nANSELC = 0\nTRISC = 0\nINTCON0 = 0\nNVMCON1 = 0\n").unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").arg("-o").arg(out.join("t.hex")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(out.join("t.S")).unwrap();
    assert!(asm.contains("ANSELC, b"), "{asm}");
    assert!(asm.contains("NVMCON1, b"), "{asm}");
    assert!(asm.contains("TRISC, c"), "{asm}");
    assert!(asm.contains("INTCON0, c"), "{asm}");
}

/// The RTCC model test double (`tests/exec_rtcc/i2c.bas`) carries a copy of the block routines of `lib/i2c.bas` so that `rtcc` runs against the
/// real logic; the two must not drift apart. Each routine is compared with comments dropped and the module's `lastStatus` read as the model's `last`.
#[test]
fn rtcc_model_block_routines_match_the_library() {
    fn routine(text: &str, name: &str) -> String {
        let at = text.find(&format!("Function {name}(")).unwrap_or_else(|| panic!("{name} not found"));
        let rest = &text[at..];
        let end = rest.find("End Function").unwrap() + "End Function".len();
        rest[..end]
            .lines()
            .filter(|l| !l.trim_start().starts_with('\''))
            .map(|l| l.trim_end().replace("lastStatus", "last"))
            .collect::<Vec<_>>()
            .join("\n")
    }
    let lib = std::fs::read_to_string(root().join("lib/i2c.bas")).unwrap().replace("\r\n", "\n");
    // the block routines of the software and MSSP hosts (the second definitions; the first are the hardware ones)
    let generic = &lib[lib.find("#if Not _i2chw\n' Block transfers").expect("generic block routines")..];
    let model = std::fs::read_to_string(root().join("tests/exec_rtcc/i2c.bas")).unwrap().replace("\r\n", "\n");
    for name in ["Open", "I2cReadRegs", "I2cWriteRegs", "I2cProbe"] {
        assert_eq!(routine(generic, name), routine(&model, name), "{name}: the model's copy differs from lib/i2c.bas");
    }
}

/// `#option I2c = Hardware` (the I2C1 peripheral with the block routines and `Rtcc` on top) builds on all six PIC18-Q41 parts with no
/// warning, and the software host stays the default: the same program without the option still builds.
#[test]
fn q41_hardware_i2c_builds() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("q41i2chw");
    let all = root().join("tests/programs/i2c_hw_q41.bas");
    for dev in Q41_PARTS {
        let src = for_device(&all, dev, &out.join(format!("hw_{dev}.bas")));
        let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join(format!("hw_{dev}.hex"))).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        assert!(r.status.success() && !text.contains("warning"), "{dev}:\n{text}");
        // The option really changes the code: the hardware build drives I2C1 and has no bit-banged clock routine, and the same
        // program without the option is the software host.
        let no_option: String = std::fs::read_to_string(&src).unwrap().lines().filter(|l| l.trim() != "#option I2c = Hardware").map(|l| format!("{l}\n")).collect();
        let sw = out.join(format!("sw_{dev}.bas"));
        std::fs::write(&sw, no_option).unwrap();
        let r = Command::new(basil()).arg(&sw).arg("-S").arg("-o").arg(out.join(format!("sw_{dev}.hex"))).output().unwrap();
        assert!(r.status.success(), "{dev} (software):\n{}", String::from_utf8_lossy(&r.stderr));
        let r = Command::new(basil()).arg(&src).arg("-S").arg("-o").arg(out.join(format!("hw_{dev}.hex"))).output().unwrap();
        assert!(r.status.success());
        let hw_s = std::fs::read_to_string(out.join(format!("hw_{dev}.S"))).unwrap();
        let sw_s = std::fs::read_to_string(out.join(format!("sw_{dev}.S"))).unwrap();
        assert!(hw_s.contains("I2C1TXB") && !hw_s.contains("I2C_SCLHIGH"), "{dev}: hardware build");
        assert!(sw_s.contains("I2C_SCLHIGH") && !sw_s.contains("I2C1TXB"), "{dev}: software build");
    }
}

/// The hardware I2C driver executed: `scripts/picsim.py` is an instruction-level simulator of the code the compiler writes, with a model of
/// the I2C1 host (MDB has none) and a simulated client; `scripts/test_i2chw.py` checks every routine's status, data, register setup and the
/// exact bus transcript, with faults, at several clock speeds, and `Rtcc` on top. It stops after assembly, so it needs no `pic-as`. Optimised,
/// and as the `-O0` reference build (which found two order-of-read races the optimised code hid). It builds about 40 programs and runs them in
/// pure Python, a few minutes in all, so like the MDB tests it is opt-in: `BASIL_SIM=1` (or `BASIL_MDB=1`).
#[test]
fn i2c_hardware_driver_in_simulator() {
    if std::env::var("BASIL_SIM").is_err() && std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_SIM=1 (or BASIL_MDB=1) to run the hardware I2C simulator test");
        return;
    }
    for flags in ["", "-O0"] {
        let r = Command::new("python3")
            .arg(root().join("scripts/test_i2chw.py"))
            .env("BASIL", basil())
            .env("BASIL_LIB", root().join("lib"))
            .env("BASIL_FLAGS", flags)
            .output()
            .unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
}

/// With `BASIL_MDB=1` the programs that touch no peripheral, and the PIC18-Q41 library tests, run on the
/// simulator's `PIC18F16Q41`.
#[test]
fn q41_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let mut files: Vec<PathBuf> = bas_files(&root().join("tests/exec"))
        .into_iter()
        .filter(|p| {
            let t = std::fs::read_to_string(p).unwrap();
            let name = p.file_stem().unwrap().to_string_lossy().into_owned();
            // `Include` means a library module: only the ones that are device independent.
            !t.contains("Include \"") || ["lib_system", "lib_intosc", "lib_intosc_div"].contains(&name.as_str())
        })
        .collect();
    files.extend(bas_files(&root().join("tests/exec_q41")));
    let r = Command::new("python3")
        .arg(root().join("scripts/exec-test.py"))
        .arg("--basil")
        .arg(basil())
        .arg("--device")
        .arg("18F16Q41")
        .args(&files)
        .output()
        .unwrap();
    let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
    assert!(r.status.success(), "{text}");
}

// ---- PIC18(L)F2x/4xK22 -----------------------------------------------------------------------------

const K22_PARTS: [&str; 16] = [
    "18F23K22", "18F24K22", "18F25K22", "18F26K22", "18F43K22", "18F44K22", "18F45K22", "18F46K22", "18LF23K22", "18LF24K22", "18LF25K22", "18LF26K22", "18LF43K22", "18LF44K22", "18LF45K22",
    "18LF46K22",
];

/// The Q10 interrupt programs of `tests/exec` raise their interrupt through PIR0; `tests/exec_k22` has the K22 versions.
const K22_SKIP: &[&str] = &["isr_single", "isr_dual", "isr_save", "events_isr", "gosub_isr", "bit_packed_isr"];

/// A K22 copy of a Q-series program: the Device line, and a Q-series Config line becomes an external 64 MHz clock (FOSC = ECHPIO6), so
/// `Clock = 64` stays true without oscillator code.
fn for_k22(src: &Path, device: &str, into: &Path) -> PathBuf {
    let p = for_device(src, device, into);
    let text = std::fs::read_to_string(&p).unwrap();
    let out: String = text
        .lines()
        .map(|l| if l.trim_start().to_ascii_lowercase().starts_with("config ") && (l.contains("RSTOSC") || l.contains("FEXTOSC")) { "Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON".to_string() } else { l.to_string() })
        .map(|l| l + "\n")
        .collect();
    std::fs::write(&p, out).unwrap();
    p
}

/// The 40/44-pin parts (PIC18(L)F4xK22).
fn k22_big(dev: &str) -> bool {
    dev.trim_start_matches("18LF").trim_start_matches("18F").starts_with('4')
}

/// A program meant for the 40/44-pin parts only (`' devices: 18F45K22`).
fn k22_big_only(p: &Path) -> bool {
    std::fs::read_to_string(p).unwrap().lines().any(|l| l.starts_with("' devices:") && l.contains("18F45K22") && !l.contains("18F25K22"))
}

/// The standard programs (with handlers, both priorities) and the K22 library programs build for every part of the family; on the
/// parts other than the 64 KB ones a program too big for the part's RAM or flash may be refused with E-RAM or E-ROM, the right answer.
#[test]
fn k22_parts_build_the_standard_programs() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("k22parts");
    let programs = ["arith_byte", "arith_word", "arith_longword", "arrays", "flow", "funcs", "reentrant", "str_basic", "structs"];
    let mut failures = Vec::new();
    for dev in K22_PARTS {
        let mut srcs: Vec<PathBuf> = programs.iter().map(|p| for_k22(&root().join(format!("tests/exec/{p}.bas")), dev, &out.join(format!("{p}_{dev}.bas")))).collect();
        for f in bas_files(&root().join("tests/exec_k22")) {
            if k22_big_only(&f) && !k22_big(dev) {
                continue;
            }
            let name = f.file_stem().unwrap().to_string_lossy().into_owned();
            srcs.push(for_device(&f, dev, &out.join(format!("k22_{name}_{dev}.bas"))));
        }
        for src in srcs {
            let r = Command::new(basil()).arg(&src).arg("-o").arg(src.with_extension("hex")).output().unwrap();
            let text = String::from_utf8_lossy(&r.stderr).into_owned();
            // Every program fits the largest parts (64 KB, 3896 bytes: 26K22, 46K22); the others may refuse one as too big
            // (arith_longword needs 2547 bytes of RAM, more than the 1536 of the x5 parts).
            let small = !(dev.ends_with("26K22") || dev.ends_with("46K22"));
            let too_big = small && (text.contains("error[E-RAM]") || text.contains("error[E-ROM]"));
            if (!r.status.success() && !too_big) || text.contains("pic-as:") {
                failures.push(format!("{} for {dev}:\n{text}", src.display()));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// Every library module but `dma` builds on all sixteen parts with no warning: the whole library on the 16 KB and larger parts, the
/// ported peripheral modules on the 8 KB PIC18(L)F23K22 / 43K22 (`library_k22_small.bas`); `dma` stops with #error.
#[test]
fn k22_library_modules_build() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("k22lib");
    for dev in K22_PARTS {
        let small = dev.contains("23K22") || dev.contains("43K22");
        let all = root().join(if small { "tests/programs/library_k22_small.bas" } else { "tests/programs/library_k22.bas" });
        let src = for_device(&all, dev, &out.join(format!("library_{dev}.bas")));
        let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join(format!("library_{dev}.hex"))).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        assert!(r.status.success() && !text.contains("warning"), "{dev}:\n{text}");
    }
    let src = out.join("uses_dma.bas");
    std::fs::write(&src, "Program T\nDevice = 18F25K22\nClock = 16\nInclude \"dma\"\n").unwrap();
    let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join("uses_dma.hex")).output().unwrap();
    let text = String::from_utf8_lossy(&r.stderr).into_owned();
    assert!(!r.status.success() && text.contains("E-PP-ERROR"), "{text}");
}

/// Two interrupt priorities set IPEN, which is RCON bit 7 on the K22 (its INTCON bit 5 is TMR0IE, DS40001412H Registers 4-1, 9-1); the
/// extended instruction set (XINST = ON) is refused; a program larger than the 8 KB of the PIC18F23K22 is refused with E-ROM.
#[test]
fn k22_ipen_xinst_and_flash_size() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("k22core");
    let src = for_device(&root().join("tests/exec_k22/isr_dual.bas"), "18F25K22", &out.join("isr_dual.bas"));
    let r = Command::new(basil()).arg(&src).arg("-S").arg("-o").arg(out.join("isr_dual.hex")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(out.join("isr_dual.S")).unwrap();
    assert!(asm.contains("bsf RCON, 7, c"), "IPEN must be RCON bit 7:\n{asm}");
    let x = out.join("xinst.bas");
    std::fs::write(&x, "Program T\nDevice = 18F25K22\nClock = 16\nConfig XINST = ON\n").unwrap();
    let r = Command::new(basil()).arg(&x).arg("-o").arg(out.join("xinst.hex")).output().unwrap();
    let text = String::from_utf8_lossy(&r.stderr).into_owned();
    assert!(!r.status.success() && text.contains("E-CONFIG") && text.contains("XINST"), "{text}");
    let big = for_device(&root().join("tests/programs/library_k22.bas"), "18F23K22", &out.join("big.bas"));
    let r = Command::new(basil()).arg(&big).arg("-o").arg(out.join("big.hex")).output().unwrap();
    let text = String::from_utf8_lossy(&r.stderr).into_owned();
    assert!(!r.status.success() && text.contains("E-ROM"), "{text}");
}

/// With `BASIL_MDB=1` (or `BASIL_SIM=1`): the programs that touch no peripheral run on the simulated PIC18F26K22 (the 3.9 KB part, so
/// the RAM-hungry ones fit), and `tests/exec_k22` on the PIC18F25K22 and, for the 40/44-pin programs, the PIC18F45K22, optimised and at
/// `-O0`. basil-sim models the K22's interrupts, timers, EUSART, MSSP, ADC, EEPROM/flash, CCP PWM and oscillator status (the picsim
/// repository); programs that MDB cannot check say `' engine: sim`.
#[test]
fn k22_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() && std::env::var("BASIL_SIM").is_err() {
        eprintln!("set BASIL_MDB=1 (or BASIL_SIM=1) to run the simulator tests");
        return;
    }
    let core: Vec<PathBuf> = bas_files(&root().join("tests/exec"))
        .into_iter()
        .filter(|p| {
            let t = std::fs::read_to_string(p).unwrap();
            let name = p.file_stem().unwrap().to_string_lossy().into_owned();
            !t.contains("Include \"") && !K22_SKIP.contains(&name.as_str())
        })
        .collect();
    let k22: Vec<PathBuf> = bas_files(&root().join("tests/exec_k22"));
    let big: Vec<PathBuf> = k22.iter().filter(|p| k22_big_only(p)).cloned().collect();
    // Unoptimised, these two are larger than the 64 KB of the PIC18F26K22 (E-ROM; the PIC18F27Q10 has 128 KB).
    let o0_big = ["arith_mulconst", "array_rmw"];
    for (dev, files) in [("18F26K22", &core), ("18F25K22", &k22), ("18F45K22", &big)] {
        for flags in ["", "-O0"] {
            let files: Vec<&PathBuf> = files.iter().filter(|p| flags.is_empty() || !o0_big.contains(&p.file_stem().unwrap().to_string_lossy().as_ref())).collect();
            let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).arg("--device").arg(dev).args(&files).output().unwrap();
            let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
            assert!(r.status.success(), "{dev}, flags `{flags}`:\n{text}");
        }
    }
}

const P16_PARTS: [&str; 2] = ["16F17126", "16F17146"];

/// The programs of `tests/exec` that run on the enhanced mid-range core with only the `Device`, `Config` and
/// `Clock` lines changed (the others use PIC18 registers, PIC18 assembly or cycle counts of a 64 MHz part).
const P16_PORTABLE: &[&str] = &[
    "absminmax", "boundscheck", "boundscheck_hoist", "minmax_once", "arith_byte", "arith_integer", "arith_shortint", "arith_word", "arrays", "bit_packed", "byref", "callopt", "countloop", "events", "events_array_cmp", "events_params",
    "flow", "funcs", "inc", "multidim", "mulzero", "overlay", "reentrant", "review", "rmw", "static_local", "strarray", "str_basic", "str_slice", "str_func", "str_func2", "gosub", "call_stmt", "if_gosub", "str_cat_cmp", "str_cat_assign", "structinit_nested", "agg_result", "agg_params", "agg_byval", "str_num", "forward", "str_slice_ref", "structinit", "structs", "structstr", "tablewalk", "overload",
    "arrays_full", "events_isr", "isr_save", "lib_timer", "lib_timer12", "lib_timer_event", "lib_timer_hw", "lib_lcd", "lib_pinio_ref", "lib_shift", "lib_oled", "lib_aht30", "lib_rtcc", "lib_rtccspi", "lib_strings", "lib_format", "lib_onewire",
    "loop_free_end", "unary_signext", "table_pair", "array_walk", "two_array_walk", "descending_copy", "mul_walk_rotate", "signed_div_pow2", "signed_div_pow2_shared", "param_result", "divk_word", "divw_long", "float_basic", "float_chain", "float_compare", "float_muldiv", "float_pow2", "float_nan_order", "float_denormal_cmp", "lib_floatlib", "lib_floatlib_cmp", "lib_floatlib_conv", "lib_floatlib_edge", "float_negate", "p16_inplace_ops", "local_reuse_calls",
];

/// A test program of `tests/exec` for an enhanced mid-range part: its own `Device`, `Config` and `Clock`.
fn for_p16(src: &Path, device: &str, into: &Path) -> PathBuf {
    let text = std::fs::read_to_string(src).unwrap();
    let mut out = String::new();
    let mut device_done = false;
    for line in text.lines() {
        let t = line.trim_start().to_ascii_lowercase();
        if !device_done && t.starts_with("device") {
            out += &format!("Device = {device}\n");
            device_done = true;
        } else if t.starts_with("config ") {
            // The PIC16F183xx parts call the 32 MHz power-up setting HFINT32 (2x PLL), and so do the PIC16F153xx parts.
            out += if device.starts_with("16F183") || device.starts_with("16F153") { "Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON\n" } else { "Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\n" };
        } else if t.starts_with("clock") && t.contains("64") {
            out += "Clock = 32\n";
        } else {
            out += line;
            out.push('\n');
        }
    }
    std::fs::write(into, out).unwrap();
    into.to_path_buf()
}

/// The portable programs, and the programs written for the part (`tests/exec_p16`), build for both PIC16F171x6 parts.
#[test]
fn p16_parts_build_the_standard_programs() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("p16parts");
    let mut failures = Vec::new();
    for dev in P16_PARTS {
        let mut programs: Vec<PathBuf> = P16_PORTABLE.iter().map(|p| for_p16(&root().join(format!("tests/exec/{p}.bas")), dev, &out.join(format!("{p}_{dev}.bas")))).collect();
        for f in bas_files(&root().join("tests/exec_p16")) {
            let name = f.file_stem().unwrap().to_string_lossy().into_owned();
            if name == "lib_pwm_pins" && dev == "16F17126" {
                continue; // reads RB4PPS and RB5PPS; the 16F17126 has no port B
            }
            programs.push(for_p16(&f, dev, &out.join(format!("{name}_{dev}.bas"))));
        }
        for src in programs {
            let r = Command::new(basil()).arg(&src).arg("-o").arg(src.with_extension("hex")).output().unwrap();
            let text = String::from_utf8_lossy(&r.stderr).into_owned();
            if !r.status.success() || text.contains("pic-as:") {
                failures.push(format!("{} for {dev}:\n{text}", src.display()));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// With `BASIL_MDB=1` the portable programs and `tests/exec_p16` run on the simulator's `PIC16F17146`.
#[test]
fn p16_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let mut files: Vec<PathBuf> = P16_PORTABLE.iter().map(|p| root().join(format!("tests/exec/{p}.bas"))).collect();
    files.extend(bas_files(&root().join("tests/exec_p16")));
    // The larger benchmark programs too: they caught a copy forwarded into the wrong bank (0.1.182).
    files.extend(bas_files(&root().join("bench/large")));
    for flags in ["", "-O0"] {
        let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).arg("--device").arg("16F17146").args(&files).output().unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
}

const P13_PARTS: [&str; 9] = ["16F13113", "16F13114", "16F13115", "16F13123", "16F13124", "16F13125", "16F13143", "16F13144", "16F13145"];

/// Programs of the PIC16F171xx sets that cannot run on the PIC16F13145: too big for its 1 KB of RAM or 8K words of flash, or about a
/// peripheral it lacks (second EUSART, data EEPROM, the 16-bit PWM); `tests/exec_p13` has the 13145 versions of the last few.
const P13_SKIP: &[&str] = &["arith_integer", "arith_word", "lib_oled", "float_compare", "float_pow2", "lib_floatlib_edge", "lib_eeprom", "eeprom_word_edge", "lib_serial2", "serial2_word_digits", "lib_pwm", "lib_pwm_pins", "lib_adc", "lib_flashwrite"];

/// The programs for the PIC16F13145: the portable ones and `tests/exec_p16` that fit and apply, then `tests/exec_p13`.
fn p13_programs() -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = P16_PORTABLE.iter().filter(|p| !P13_SKIP.contains(p)).map(|p| root().join(format!("tests/exec/{p}.bas"))).collect();
    files.extend(bas_files(&root().join("tests/exec_p16")).into_iter().filter(|f| !P13_SKIP.contains(&f.file_stem().unwrap().to_str().unwrap())));
    files.extend(bas_files(&root().join("tests/exec_p13")));
    files
}

/// Every member of the PIC16F13145 family builds the small program (port A only on the 8-pin part, 256 bytes of RAM, 2K words of
/// flash); the PIC16F13145 builds all of its programs.
#[test]
fn p13_parts_build() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("p13parts");
    let mut failures = Vec::new();
    let small = std::fs::read_to_string(root().join("tests/exec_p13_parts/small.bas")).unwrap();
    let mut programs: Vec<(String, PathBuf)> = Vec::new();
    for dev in P13_PARTS {
        let f = out.join(format!("small_{dev}.bas"));
        std::fs::write(&f, small.replace("16F13113", dev)).unwrap();
        programs.push((dev.to_string(), f));
    }
    for src in p13_programs() {
        let name = src.file_stem().unwrap().to_string_lossy().into_owned();
        // `tests/exec_p13` programs already name the part and its clock; the others are changed as for the PIC16F171xx.
        let f = if src.starts_with(root().join("tests/exec_p13")) { src.clone() } else { for_p16(&src, "16F13145", &out.join(format!("{name}_16F13145.bas"))) };
        programs.push(("16F13145".into(), f));
    }
    for (dev, src) in programs {
        let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        if !r.status.success() || text.contains("pic-as:") {
            failures.push(format!("{} for {dev}:\n{text}", src.display()));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// Erratum 1.3.1 of the PIC16F13145 family (DS80001115F): above 16 MHz a NOP at 0000h and at the start of the handler; none at 16 MHz,
/// with `#option FetchNop = false`, or on the PIC16F17146.
#[test]
fn p13_fetch_nop_work_around() {
    let out = scratch("p13nop");
    let src = std::fs::read_to_string(root().join("tests/exec_p16/isr_single.bas")).unwrap();
    let asm = |dev: &str, clock: &str, extra: &str, name: &str| {
        let mut text = String::new();
        for line in src.lines() {
            let t = line.trim_start().to_ascii_lowercase();
            if t.starts_with("device") {
                text += &format!("Device = {dev}\n{extra}");
            } else if t.starts_with("clock") {
                text += &format!("Clock = {clock}\n");
            } else {
                text += line;
                text.push('\n');
            }
        }
        let f = out.join(format!("{name}.bas"));
        std::fs::write(&f, text).unwrap();
        let r = Command::new(basil()).arg("-S").arg(&f).arg("-o").arg(out.join(format!("{name}.S"))).output().unwrap();
        assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
        let s = std::fs::read_to_string(out.join(format!("{name}.S"))).unwrap();
        let at = |org: &str| s.split(org).nth(1).unwrap().lines().nth(1).unwrap().trim().to_string();
        (at("ORG 0x0000"), at("ORG 0x0004"))
    };
    assert_eq!(asm("16F13145", "32", "", "a"), ("nop".into(), "nop".into()));
    assert_ne!(asm("16F13145", "16", "", "b").0, "nop");
    assert_ne!(asm("16F13145", "32", "#option FetchNop = false\n", "c").0, "nop");
    assert_ne!(asm("16F17146", "32", "", "d").0, "nop");
    // The PIC16F13214/15/24/25/44/45 errata (DS80001213B) list no fetch erratum: no NOP at any clock.
    assert_ne!(asm("16F13245", "32", "", "e").0, "nop");
    assert_ne!(asm("16F13214", "32", "", "f").1, "nop");
}

/// With `BASIL_MDB=1` the PIC16F13145 programs run on the simulator's `PIC16F13145`.
#[test]
fn p13_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files = p13_programs();
    for flags in ["", "-O0"] {
        let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).arg("--device").arg("16F13145").args(&files).output().unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
}

/// The start-up zeroing of globals (`clrf 0xNNN`) is dropped for a variable the first statement overwrites, and only then: a byte that is read
/// before it is written, the other bytes of a partly written Word, and every variable of a program with an interrupt handler keep their clear.
#[test]
fn startup_clears_are_kept_where_a_read_can_see_zero() {
    let out = scratch("startclr");
    let clears = |name: &str, body: &str| -> usize {
        let f = out.join(format!("{name}.bas"));
        std::fs::write(&f, format!("Program P\nDevice = 18F27Q10\nClock = 64\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON\n{body}\nDo\nLoop\n")).unwrap();
        let s = out.join(format!("{name}.S"));
        let r = Command::new(basil()).arg("-S").arg(&f).arg("-o").arg(&s).output().unwrap();
        assert!(r.status.success(), "{name}: {}", String::from_utf8_lossy(&r.stderr));
        let text = std::fs::read_to_string(&s).unwrap();
        let start = text.split("__reset:").nth(1).unwrap();
        start.lines().take_while(|l| !l.trim().starts_with("_L1")).filter(|l| l.trim().starts_with("clrf 0x")).count()
    };
    // Assigned before any read: no clear.
    assert_eq!(clears("a", "Dim a As Byte\na = PORTA\nPORTB = a"), 0);
    // Only the low byte of the Word is written: the high byte is read as zero, so its clear stays.
    assert_eq!(clears("w", "Dim w As Word\nw.Byte0 = PORTA\nPORTB = w.Byte1"), 1);
    // Read before the write: the clear stays.
    assert_eq!(clears("r", "Dim x As Byte\nPORTB = x\nx = PORTA"), 1);
    // An interrupt handler can see a variable at any time: nothing is dropped.
    assert_eq!(clears("i", "Dim cnt As Byte\nDim a As Byte\nInterrupt H()\n    Inc(cnt)\nEnd Interrupt\na = PORTA\ncnt = a\nPORTB = cnt"), 2);
}

const P132_PARTS: [&str; 6] = ["16F13214", "16F13215", "16F13224", "16F13225", "16F13244", "16F13245"];

/// Programs of the PIC16F171xx sets that cannot run on the PIC16F13245 (DS40002686B): too big for its 1 KB of RAM or 8K words of flash
/// (`lib_oled` needs a 1 KB frame buffer); `tests/exec_p132` has the versions of `lib_adc` (10 bits, TAD from 0.5 us) and `lib_flashwrite`
/// (8K words) for the part. The part has the data EEPROM, both EUSARTs and the 16-bit PWM, so those tests run as written for the PIC16F17146.
const P132_SKIP: &[&str] = &["arith_integer", "arith_word", "lib_oled", "float_compare", "float_pow2", "lib_floatlib_edge", "lib_adc", "lib_flashwrite"];

/// The programs for the PIC16F13245: the portable ones and `tests/exec_p16` that fit and apply, then `tests/exec_p132`.
fn p132_programs() -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = P16_PORTABLE.iter().filter(|p| !P132_SKIP.contains(p)).map(|p| root().join(format!("tests/exec/{p}.bas"))).collect();
    files.extend(bas_files(&root().join("tests/exec_p16")).into_iter().filter(|f| !P132_SKIP.contains(&f.file_stem().unwrap().to_str().unwrap())));
    files.extend(bas_files(&root().join("tests/exec_p132")));
    files
}

/// Every member of the PIC16F13214/15/24/25/44/45 family builds the small program (port A only on the 8-pin parts, 512 bytes of RAM and 4K words of
/// flash on the smallest); the PIC16F13245 builds all of its programs.
#[test]
fn p132_parts_build() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("p132parts");
    let mut failures = Vec::new();
    let small = std::fs::read_to_string(root().join("tests/exec_p132_parts/small.bas")).unwrap();
    let mut programs: Vec<(String, PathBuf)> = Vec::new();
    for dev in P132_PARTS {
        let f = out.join(format!("small_{dev}.bas"));
        std::fs::write(&f, small.replace("16F13214", dev)).unwrap();
        programs.push((dev.to_string(), f));
    }
    for src in p132_programs() {
        let name = src.file_stem().unwrap().to_string_lossy().into_owned();
        // `tests/exec_p132` programs already name their part and clock; the others are changed as for the PIC16F171xx.
        let f = if src.starts_with(root().join("tests/exec_p132")) { src.clone() } else { for_p16(&src, "16F13245", &out.join(format!("{name}_16F13245.bas"))) };
        programs.push(("16F13245".into(), f));
    }
    for (dev, src) in programs {
        let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        if !r.status.success() || text.contains("pic-as:") {
            failures.push(format!("{} for {dev}:\n{text}", src.display()));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// With `BASIL_MDB=1` the PIC16F13245 programs run on the simulator's `PIC16F13245`, and the pin tests on the 8-, 14- and 20-pin part each.
#[test]
fn p132_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files = p132_programs();
    for flags in ["", "-O0"] {
        let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).arg("--device").arg("16F13245").args(&files).output().unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
    // The pin tests name one part each (`devices:`), so they were skipped above.
    for (dev, name) in [("16F13214", "pins8"), ("16F13224", "pins14"), ("16F13244", "pins20")] {
        let f = root().join(format!("tests/exec_p132/{name}.bas"));
        let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg("--device").arg(dev).arg(&f).output().unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "{name} on {dev}:\n{text}");
    }
}

const P183_PARTS: [&str; 16] = [
    "16F18313", "16F18323", "16F18324", "16F18325", "16F18326", "16F18344", "16F18345", "16F18346", "16LF18313", "16LF18323", "16LF18324", "16LF18325", "16LF18326", "16LF18344", "16LF18345",
    "16LF18346",
];

/// Programs of the PIC16F171xx sets that do not apply to the PIC16F183xx: Timer1 and Timer2 with their clock-select and hardware-limit registers, and the library
/// modules whose registers differ (`tests/exec_p183` has the PIC16F183xx versions).
const P183_SKIP: &[&str] = &["lib_intosc", "lib_timer12", "lib_timer_hw", "lib_adc", "lib_eeprom", "lib_flashwrite", "lib_i2c", "lib_pwm", "lib_pwm_pins", "lib_serial", "lib_serial2", "serial2_word_digits", "lib_spi"];

/// The programs for the PIC16F183xx: the portable ones and `tests/exec_p16` that apply, then `tests/exec_p183`.
fn p183_programs() -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = P16_PORTABLE.iter().filter(|p| !P183_SKIP.contains(p)).map(|p| root().join(format!("tests/exec/{p}.bas"))).collect();
    files.extend(bas_files(&root().join("tests/exec_p16")).into_iter().filter(|f| !P183_SKIP.contains(&f.file_stem().unwrap().to_str().unwrap())));
    files.extend(bas_files(&root().join("tests/exec_p183")));
    files
}

/// Every member of the PIC16F183xx family builds the small program (port A only on the 8-pin part, 256 bytes of RAM, 2K words of flash); the
/// PIC16F18346 builds all of its programs.
#[test]
fn p183_parts_build() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("p183parts");
    let mut failures = Vec::new();
    let small = std::fs::read_to_string(root().join("tests/exec_p183_parts/small.bas")).unwrap();
    let mut programs: Vec<(String, PathBuf)> = Vec::new();
    for dev in P183_PARTS {
        let f = out.join(format!("small_{dev}.bas"));
        std::fs::write(&f, small.replace("16F18313", dev)).unwrap();
        programs.push((dev.to_string(), f));
    }
    for src in p183_programs() {
        let name = src.file_stem().unwrap().to_string_lossy().into_owned();
        // `tests/exec_p183` programs already name a part and its clock; the others are changed as for the PIC16F171xx.
        let f = if src.starts_with(root().join("tests/exec_p183")) { src.clone() } else { for_p16(&src, "16F18346", &out.join(format!("{name}_16F18346.bas"))) };
        programs.push(("16F18346".into(), f));
    }
    for (dev, src) in programs {
        let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        if !r.status.success() || text.contains("pic-as:") {
            failures.push(format!("{} for {dev}:\n{text}", src.display()));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// The PIC16F183xx modules that stop with `#error` instead of using registers the part does not have.
#[test]
fn p183_unported_modules_stop() {
    let out = scratch("p183err");
    for m in ["serial2", "dma", "intosc"] {
        let f = out.join(format!("e_{m}.bas"));
        std::fs::write(&f, format!("Program E\nDevice = 16F18326\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON\nInclude \"{m}\"\nDim x As Byte\nx = 1\n")).unwrap();
        let r = Command::new(basil()).arg(&f).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        assert!(!r.status.success() && text.contains("E-PP-ERROR"), "{m} did not stop with #error:\n{text}");
    }
}

/// With `BASIL_MDB=1` the PIC16F183xx programs run on the simulator's `PIC16F18346`.
#[test]
fn p183_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files = p183_programs();
    for flags in ["", "-O0"] {
        let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).arg("--device").arg("16F18346").args(&files).output().unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
}

const P152_PARTS: [&str; 6] = ["16F15213", "16F15214", "16F15223", "16F15224", "16F15243", "16F15244"];

/// Programs of the PIC16F171xx sets that do not apply to the PIC16F152xx (or do not fit its 512 bytes of RAM and 4K words of flash): the library
/// modules whose registers differ (`tests/exec_p152` has the PIC16F152xx versions) and the programs that are too big.
const P152_SKIP: &[&str] = &["lib_intosc", "arith_byte", "arith_integer", "arith_shortint", "arith_word", "agg_byval", "arrays_full", "lib_oled", "float_compare", "float_pow2", "lib_floatlib_edge", "lib_adc", "lib_eeprom", "eeprom_word_edge", "lib_flashwrite", "lib_i2c", "lib_pwm", "lib_pwm_pins", "lib_serial2", "serial2_word_digits", "lib_serial", "lib_spi"];

/// The programs for the PIC16F152xx: the portable ones and `tests/exec_p16` that apply, then `tests/exec_p152`.
fn p152_programs() -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = P16_PORTABLE.iter().filter(|p| !P152_SKIP.contains(p)).map(|p| root().join(format!("tests/exec/{p}.bas"))).collect();
    files.extend(bas_files(&root().join("tests/exec_p16")).into_iter().filter(|f| !P152_SKIP.contains(&f.file_stem().unwrap().to_str().unwrap())));
    files.extend(bas_files(&root().join("tests/exec_p152")));
    files
}

/// Every member of the PIC16F152xx family builds the small program (port A only on the 8-pin parts, 256 bytes of RAM, 2K words of flash); the
/// PIC16F15244 builds all of its programs.
#[test]
fn p152_parts_build() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("p152parts");
    let mut failures = Vec::new();
    let small = std::fs::read_to_string(root().join("tests/exec_p152_parts/small.bas")).unwrap();
    let mut programs: Vec<(String, PathBuf)> = Vec::new();
    for dev in P152_PARTS {
        let f = out.join(format!("small_{dev}.bas"));
        std::fs::write(&f, small.replace("16F15213", dev)).unwrap();
        programs.push((dev.to_string(), f));
    }
    for src in p152_programs() {
        let name = src.file_stem().unwrap().to_string_lossy().into_owned();
        // `tests/exec_p152` programs already name a part and its clock; the others are changed as for the PIC16F171xx.
        let f = if src.starts_with(root().join("tests/exec_p152")) { src.clone() } else { for_p16(&src, "16F15244", &out.join(format!("{name}_16F15244.bas"))) };
        programs.push(("16F15244".into(), f));
    }
    for (dev, src) in programs {
        let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        if !r.status.success() || text.contains("pic-as:") {
            failures.push(format!("{} for {dev}:\n{text}", src.display()));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// The PIC16F152xx modules that stop with `#error` instead of using registers or memory the part does not have.
#[test]
fn p152_unported_modules_stop() {
    let out = scratch("p152err");
    for m in ["eeprom", "serial2", "dma"] {
        let f = out.join(format!("e_{m}.bas"));
        std::fs::write(&f, format!("Program E\nDevice = 16F15244\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHZ, WDTE = OFF, LVP = ON\nInclude \"{m}\"\nDim x As Byte\nx = 1\n")).unwrap();
        let r = Command::new(basil()).arg(&f).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        assert!(!r.status.success() && text.contains("E-PP-ERROR"), "{m} did not stop with #error:\n{text}");
    }
}

/// With `BASIL_MDB=1` the PIC16F152xx programs run on the simulator's `PIC16F15244`.
#[test]
fn p152_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files = p152_programs();
    for flags in ["", "-O0"] {
        let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).arg("--device").arg("16F15244").args(&files).output().unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
}

const P153_PARTS: [&str; 26] = [
    "16F15313", "16F15323", "16F15324", "16F15325", "16F15344", "16F15345", "16F15354", "16F15356", "16F15356", "16F15375", "16F15376", "16F15385", "16F15386", "16LF15313", "16LF15323", "16LF15324", "16LF15325", "16LF15344", "16LF15345", "16LF15354",
    "16LF15355", "16LF15356", "16LF15375", "16LF15376", "16LF15385", "16LF15386",
];

/// Programs of the PIC16F171xx sets that do not apply to the PIC16F153xx: the library modules whose registers differ (`tests/exec_p153` has the PIC16F153xx versions) and the programs that need data EEPROM.
const P153_SKIP: &[&str] = &["lib_intosc", "i2c_pps_edges", "eeprom_word_edge", "lib_adc", "lib_eeprom", "lib_flashwrite", "lib_i2c", "lib_pwm", "lib_pwm_pins", "lib_serial2", "serial2_word_digits", "lib_serial", "lib_spi"];

/// The programs for the PIC16F153xx: the portable ones and `tests/exec_p16` that apply, then `tests/exec_p153`.
fn p153_programs() -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = P16_PORTABLE.iter().filter(|p| !P153_SKIP.contains(p)).map(|p| root().join(format!("tests/exec/{p}.bas"))).collect();
    files.extend(bas_files(&root().join("tests/exec_p16")).into_iter().filter(|f| !P153_SKIP.contains(&f.file_stem().unwrap().to_str().unwrap())));
    files.extend(bas_files(&root().join("tests/exec_p153")));
    files
}

/// Every member of the PIC16F153xx family builds the small program (port A only on the 8-pin parts, 256 bytes of RAM, 2K words of flash; the PIC16F15313/23 have one EUSART); the
/// PIC16F15356 builds all of its programs.
#[test]
fn p153_parts_build() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("p153parts");
    let mut failures = Vec::new();
    let small = std::fs::read_to_string(root().join("tests/exec_p153_parts/small.bas")).unwrap();
    let mut programs: Vec<(String, PathBuf)> = Vec::new();
    for dev in P153_PARTS {
        let f = out.join(format!("small_{dev}.bas"));
        std::fs::write(&f, small.replace("16F15313", dev)).unwrap();
        programs.push((dev.to_string(), f));
    }
    for src in p153_programs() {
        let name = src.file_stem().unwrap().to_string_lossy().into_owned();
        // `tests/exec_p153` programs already name a part and its clock; the others are changed as for the PIC16F171xx.
        let f = if src.starts_with(root().join("tests/exec_p153")) { src.clone() } else { for_p16(&src, "16F15356", &out.join(format!("{name}_16F15356.bas"))) };
        programs.push(("16F15356".into(), f));
    }
    for (dev, src) in programs {
        let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        if !r.status.success() || text.contains("pic-as:") {
            failures.push(format!("{} for {dev}:\n{text}", src.display()));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// The PIC16F153xx modules that stop with `#error` instead of using registers or memory the part does not have: no data EEPROM and no DMA anywhere, and no second EUSART on the 8- and 14-pin PIC16F15313/23.
#[test]
fn p153_unported_modules_stop() {
    let out = scratch("p153err");
    for (m, dev) in [("eeprom", "16F15356"), ("dma", "16F15356"), ("serial2", "16F15313")] {
        let f = out.join(format!("e_{m}.bas"));
        std::fs::write(&f, format!("Program E\nDevice = {dev}\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON\nInclude \"{m}\"\nDim x As Byte\nx = 1\n")).unwrap();
        let r = Command::new(basil()).arg(&f).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        assert!(!r.status.success() && text.contains("E-PP-ERROR"), "{m} did not stop with #error:\n{text}");
    }
}

/// With `BASIL_MDB=1` the PIC16F153xx programs run on the simulator's `PIC16F15356`.
#[test]
fn p153_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files = p153_programs();
    // The larger and smaller parts route PPS differently (every pin on the 8- to 20-pin parts, two ports per signal from 28 pins up), so each has its own programs on its own part.
    let groups: [(&str, Vec<PathBuf>); 4] = [
        ("16F15356", files),
        ("16F15386", bas_files(&root().join("tests/exec_p153_big"))),
        ("16F15376", bas_files(&root().join("tests/exec_p153_40"))),
        ("16F15344", bas_files(&root().join("tests/exec_p153_small"))),
    ];
    for (dev, files) in groups {
        for flags in ["", "-O0"] {
            let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).arg("--device").arg(dev).args(&files).output().unwrap();
            let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
            assert!(r.status.success(), "{dev}, flags `{flags}`:\n{text}");
        }
    }
}

const P180_PARTS: [&str; 2] = ["16F18056", "16F18076"];

/// Programs of the PIC16F171xx sets that do not apply to the PIC16F18056/76: the library modules whose registers differ (`tests/exec_p180` has the
/// PIC16F18056 versions), and four programs that the simulator's PIC16F18056/76 model gets wrong although the same hex file is right on its
/// PIC16F17146 model: in each, a 4-byte (or longer) variable that sits at data address 5A0h loses its first bytes (`float_compare`: `vGe`, `lib_floatlib_edge`: `r217`, and
/// the last results of `arith_integer` and `arith_word`). Cause found: the simulator's PIC16F18056 and PIC16F18076 models ignore every write to 5A0h..5A3h
/// (linear 2370h..2373h), direct or through an FSR; a hand-written fill of all RAM leaves only those four bytes unwritten. The generated code and the device files are not at fault.
const P180_SKIP: &[&str] = &["lib_intosc", "i2c_pps_edges", "arith_integer", "arith_word", "float_compare", "lib_floatlib_edge", "lib_adc", "lib_i2c", "lib_pwm", "lib_pwm_pins", "lib_serial", "lib_serial2", "lib_spi"];

/// The programs for the PIC16F18056/76: the portable ones and `tests/exec_p16` that apply, then `tests/exec_p180`.
fn p180_programs() -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = P16_PORTABLE.iter().filter(|p| !P180_SKIP.contains(p)).map(|p| root().join(format!("tests/exec/{p}.bas"))).collect();
    files.extend(bas_files(&root().join("tests/exec_p16")).into_iter().filter(|f| !P180_SKIP.contains(&f.file_stem().unwrap().to_str().unwrap())));
    files.extend(bas_files(&root().join("tests/exec_p180")));
    files
}

/// Both members of the PIC16F18056/76 family build the small program (28 and 40 pins); the PIC16F18056 builds all of its programs, the programs of the skip
/// list too (they build; only the simulator run of four of them is held back).
#[test]
fn p180_parts_build() {
    if !have_pic_as() {
        return;
    }
    let out = scratch("p180parts");
    let mut failures = Vec::new();
    let small = std::fs::read_to_string(root().join("tests/exec_p180_parts/small.bas")).unwrap();
    let mut programs: Vec<(String, PathBuf)> = Vec::new();
    for dev in P180_PARTS {
        let f = out.join(format!("small_{dev}.bas"));
        std::fs::write(&f, small.replace("16F18056", dev)).unwrap();
        programs.push((dev.to_string(), f));
    }
    for src in p180_programs() {
        let name = src.file_stem().unwrap().to_string_lossy().into_owned();
        // `tests/exec_p180` programs already name a part and its clock; the others are changed as for the PIC16F171xx.
        let f = if src.starts_with(root().join("tests/exec_p180")) { src.clone() } else { for_p16(&src, "16F18056", &out.join(format!("{name}_16F18056.bas"))) };
        programs.push(("16F18056".into(), f));
    }
    for src in ["arith_integer", "arith_word", "float_compare", "lib_floatlib_edge"] {
        programs.push(("16F18056".into(), for_p16(&root().join(format!("tests/exec/{src}.bas")), "16F18056", &out.join(format!("{src}_16F18056.bas")))));
    }
    for (dev, src) in programs {
        let r = Command::new(basil()).arg(&src).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        if !r.status.success() || text.contains("pic-as:") {
            failures.push(format!("{} for {dev}:\n{text}", src.display()));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// The PIC16F18056/76 module that stops with `#error` instead of using registers the part does not have.
#[test]
fn p180_unported_modules_stop() {
    let out = scratch("p180err");
    for m in ["dma"] {
        let f = out.join(format!("e_{m}.bas"));
        std::fs::write(&f, format!("Program E\nDevice = 16F18056\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nInclude \"{m}\"\nDim x As Byte\nx = 1\n")).unwrap();
        let r = Command::new(basil()).arg(&f).arg("-o").arg(out.join("x.hex")).output().unwrap();
        let text = String::from_utf8_lossy(&r.stderr).into_owned();
        assert!(!r.status.success() && text.contains("E-PP-ERROR"), "{m} did not stop with #error:\n{text}");
    }
}

/// With `BASIL_MDB=1` the PIC16F18056/76 programs run on the simulator's `PIC16F18056` and `PIC16F18076`.
#[test]
fn p180_programs_in_simulator() {
    if std::env::var("BASIL_MDB").is_err() {
        eprintln!("set BASIL_MDB=1 to run the simulator tests");
        return;
    }
    let files = p180_programs();
    for dev in P180_PARTS {
        for flags in ["", "-O0"] {
            let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).arg("--device").arg(dev).args(&files).output().unwrap();
            let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
            assert!(r.status.success(), "{dev} flags `{flags}`:\n{text}");
        }
    }
}

/// A program that calls C routines is linked by xc8-cc (`CFile` / `Extern`); the simulator run of the same
/// program is `tests/exec_c`.
#[test]
fn c_routines_link() {
    if !Path::new("/opt/microchip/xc8").is_dir() && std::env::var("BASIL_XC8CC").is_err() {
        eprintln!("xc8-cc not found; skipping");
        return;
    }
    let out = std::env::temp_dir().join(format!("basil-c-{}", std::process::id()));
    std::fs::create_dir_all(&out).unwrap();
    let hex = out.join("c_basic.hex");
    let r = Command::new(basil()).arg(root().join("tests/exec_c/c_basic.bas")).arg("-o").arg(&hex).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    assert!(hex.is_file());
    // `-g`: the ELF carries the Basic variables beside the C debug information, at addresses past `_basil_entry`.
    let r = Command::new(basil()).arg("-g").arg(root().join("tests/exec_c/c_basic.bas")).arg("-o").arg(out.join("g.hex")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    assert!(!String::from_utf8_lossy(&r.stderr).contains("warning"), "{}", String::from_utf8_lossy(&r.stderr));
    let elf = std::fs::read(out.join("g.elf")).unwrap();
    assert!(elf.windows(13).any(|w| w == b"T_BUMP__RESUL"), "no Basic variable in the debug information");
    // A handler may call a C routine inside Save; outside Save it is E-ISR-CALL like any routine.
    let src = out.join("isr.bas");
    std::fs::write(&src, "Program T\nDevice = 18F27Q10\nClock = 16\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF\nCFile \"x.c\"\nExtern Sub f()\nInterrupt H()\n    Save(0, f)\n        f()\n    Restore\nEnd Interrupt\nf()\n").unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    std::fs::write(&src, "Program T\nDevice = 18F27Q10\nClock = 16\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF\nCFile \"x.c\"\nExtern Sub f()\nInterrupt H()\n    f()\nEnd Interrupt\nf()\n").unwrap();
    let r = Command::new(basil()).arg(&src).arg("-S").output().unwrap();
    assert!(!r.status.success());
    assert!(String::from_utf8_lossy(&r.stderr).contains("E-ISR-CALL"), "{}", String::from_utf8_lossy(&r.stderr));
    let r = Command::new(basil()).arg(root().join("tests/exec_c/c_isr.bas")).arg("-o").arg(out.join("c_isr.hex")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    std::fs::remove_dir_all(&out).ok();
}

fn asm_of(dir: &Path, name: &str, body: &str, extra: &[&str]) -> String {
    let src = dir.join(format!("{name}.bas"));
    let head = "Program T\nDevice = 18F27Q10\nClock = 16\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF\n";
    std::fs::write(&src, format!("{head}{body}")).unwrap();
    let r = Command::new(basil()).args(extra).arg("-S").arg(&src).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    std::fs::read_to_string(dir.join(format!("{name}.S"))).unwrap()
}

/// A routine called once is moved into its call, unless it is declared `NoInline` (PIC18 and PIC16 back ends).
#[test]
fn noinline_keeps_a_routine_called_once() {
    if !have_pic_as() {
        return;
    }
    let d = scratch("noinline");
    let body = |kw: &str| format!("Dim q As Byte\n{kw}Sub Bump()\n    LATA = LATA + 3\nEnd Sub\nq = PORTB\nBump()\nLATB = q\n");
    let s = asm_of(&d, "inl", &body(""), &[]);
    assert!(!s.contains("T_BUMP:"), "{s}");
    let s = asm_of(&d, "noinl", &body("NoInline "), &[]);
    assert!(s.contains("rcall T_BUMP") && s.contains("T_BUMP:"), "{s}");
    // On the Declare only, and on a Function.
    let s = asm_of(&d, "decl", &body("Declare NoInline Sub Bump()\n"), &[]);
    assert!(s.contains("rcall T_BUMP") && s.contains("T_BUMP:"), "{s}");
    let f = "Dim q As Byte\nNoInline Function Twice(ByVal x As Byte) As Byte\n    Result = x + x\nEnd Function\nq = Twice(PORTB)\nLATB = q\n";
    let s = asm_of(&d, "func", f, &[]);
    assert!(s.contains("rcall T_TWICE") && s.contains("T_TWICE:"), "{s}");
    let s = asm_of(&d, "func_inl", &f.replace("NoInline ", ""), &[]);
    assert!(!s.contains("T_TWICE:"), "{s}");
    // A Declare and a definition that disagree.
    let src = d.join("clash.bas");
    std::fs::write(&src, "Program T\nDevice = 18F27Q10\nClock = 16\nDeclare NoInline Sub Bump()\nInline Sub Bump()\n    LATA = 1\nEnd Sub\nBump()\n").unwrap();
    let r = Command::new(basil()).arg("-S").arg(&src).output().unwrap();
    assert!(!r.status.success() && String::from_utf8_lossy(&r.stderr).contains("E-FORWARD"), "{}", String::from_utf8_lossy(&r.stderr));
    let src = d.join("p16.bas");
    std::fs::write(&src, "Program T\nDevice = 16F17126\nClock = 8\nDim q As Byte\nNoInline Sub Bump()\n    LATA = LATA + 3\nEnd Sub\nq = PORTC\nBump()\nLATC = q\n").unwrap();
    let r = Command::new(basil()).arg("-S").arg(&src).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let s = std::fs::read_to_string(d.join("p16.S")).unwrap();
    assert!(s.contains("call T_BUMP") && s.contains("T_BUMP:"), "{s}");
    std::fs::remove_dir_all(&d).ok();
}

#[test]
fn write_only_globals_get_no_ram_and_counted_loops_share_their_variable() {
    if !have_pic_as() {
        return;
    }
    let d = scratch("ramsave");
    // A global that is only ever written takes no RAM; --keep-vars keeps it for simulator runs.
    let wo = "Dim a, w As Byte\nDim k As Byte\nFor a = 1 To 5\n    k = k + 1\nNext\nw = k\n";
    let s = asm_of(&d, "wo", wo, &[]);
    assert!(!s.contains("T_A equ"), "{s}");
    assert!(asm_of(&d, "wo_keep", wo, &["--keep-vars"]).contains("T_A equ"));
    // A loop variable that is read afterwards is its own counter: no hidden byte. (`a = q` first: with the loop's
    // final store its only one, `a` would read as that constant afterwards and not be read at all.)
    let rd = "Dim a, k, r As Byte\nDim q As PORTB\na = q\nFor a = 1 To 5\n    k = k + 1\nNext\nq = a + k\n";
    let s = asm_of(&d, "rd", rd, &[]);
    assert!(!s.contains("__H"), "{s}");
    // The count must not be seen by a handler: a variable an interrupt routine reads keeps a hidden counter.
    let isr = "Dim a, k As Byte\nDim q As PORTB\nInterrupt H()\n    q = a\nEnd Interrupt\nFor a = 1 To 5\n    k = k + 1\nNext\nq = a + k\n";
    let s = asm_of(&d, "isr", isr, &[]);
    assert!(s.contains("__H"), "{s}");
    std::fs::remove_dir_all(&d).ok();
}

#[test]
fn dead_accumulator_updates_preserve_observable_reads() {
    if !have_pic_as() { return; }
    let d = scratch("dead_updates");
    let dead = "Dim acc As LongWord\nDim a As Word\na = PORTB\nWhile True\n    acc = acc + LongWord(a) * a\n    LATC = Byte(a)\nWend\n";
    let s = asm_of(&d, "dead", dead, &[]);
    assert!(!s.contains("T_ACC equ"), "{s}");
    assert!(asm_of(&d, "keep", dead, &["--keep-vars"]).contains("T_ACC equ"));
    let live = dead.replace("LATC = Byte(a)", "LATC = Byte(acc)");
    assert!(asm_of(&d, "live", &live, &[]).contains("T_ACC equ"));
    let volatile = "Volatile Dim sourceval As Byte\nDim acc As Byte\nWhile True\n    acc = acc + sourceval\nWend\n";
    assert!(asm_of(&d, "volatile", volatile, &[]).contains("T_ACC equ"));
    let isr = "Dim acc As Byte\nInterrupt H()\n    LATC = acc\nEnd Interrupt\nWhile True\n    acc = acc + 1\nWend\n";
    assert!(asm_of(&d, "isr_acc", isr, &[]).contains("T_ACC equ"));
    let src = d.join("p16dead.bas");
    std::fs::write(&src, format!("Program T\nDevice = 16F18346\nClock = 16\n{dead}")).unwrap();
    let r = Command::new(basil()).arg("-S").arg(&src).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    assert!(!std::fs::read_to_string(d.join("p16dead.S")).unwrap().contains("T_ACC equ"));
    std::fs::remove_dir_all(&d).ok();
}

/// A counted loop that reads its Byte variable compares it with the last value instead of keeping a hidden counter;
/// a Word element stored from a constant is written into its temporary directly; the PIC16 back end drops the
/// RAM of a write-only global as the PIC18 one does.
#[test]
fn read_loops_word_constant_stores_and_pic16_write_only_save_space() {
    if !have_pic_as() {
        return;
    }
    let d = scratch("ramsave2");
    let rl = "Dim a, k As Byte\nDim q As PORTB\nFor a = 1 To 10\n    k = k + a\nNext\nq = k\n";
    let s = asm_of(&d, "rl", rl, &[]);
    assert!(!s.contains("__H"), "{s}");
    assert!(s.contains("xorlw 0x0A"), "{s}");
    assert!(!s.contains("dcfsnz"), "{s}");
    let w = "Dim wa(20) As Word\nDim i As Byte\nDim q As PORTB\ni = PORTC\nwa(i) = 5\nq = wa(3).Byte0\n";
    let s = asm_of(&d, "wc", w, &[]);
    assert!(!s.contains("movwf __A0"), "{s}");
    let src = d.join("p16.bas");
    std::fs::write(&src, "Program T\nDevice = 16F17126\nClock = 8\nDim i, k As Byte\nFor i = 1 To 5\n    LATA = LATA + 1\nNext\nFor k = 1 To 5\n    LATC = k\nNext\n").unwrap();
    let r = Command::new(basil()).arg("-S").arg(&src).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let s = std::fs::read_to_string(d.join("p16.S")).unwrap();
    assert!(!s.contains("T_I equ"), "{s}");
    std::fs::remove_dir_all(&d).ok();
}

/// `Adc` works out its conversion clock and acquisition time when the program is compiled: no 32-bit
/// divide is linked and the registers get the constants (16 MHz: ADCS = 7, ADACQ = 5).
#[test]
fn adc_conversion_clock_is_computed_at_compile_time() {
    if !have_pic_as() {
        return;
    }
    let d = scratch("adcclock");
    let s = asm_of(&d, "adcclk", "Include \"adc\"\nAdc.AdcInit()\n", &[]);
    assert!(!s.contains("__div"), "{s}");
    assert!(s.contains("movlw 0x07\n    movwf ADCLK") || s.contains("movlw 0x07\n    movlb"), "{s}");
    assert!(s.contains("movlw 0x05"), "{s}");
    std::fs::remove_dir_all(&d).ok();
}

/// Reuse phase-local storage on both cores, while retaining overlapping and observable locals.
#[test]
fn disjoint_local_lifetimes_share_storage() {
    let out = scratch("localreuse");
    let source = std::fs::read_to_string(root().join("tests/exec/local_reuse.bas")).unwrap();
    for dev in ["18F27Q10", "16F17146"] {
        for (name, from, edit, shared) in [
            ("phases", "total = total + b * 5", "total = total + b * 5", true),
            ("overlap", "total = total + b * 5", "total = total + b * 5 + a", false),
            ("volatile", "Dim b As Word", "Volatile Dim b As Word", false),
            ("partial", "b = x Xor 5678", "b.Byte0 = Byte(x)", false),
            ("jump", "b = x Xor 5678", "GoTo phase2\nphase2:\nb = x Xor 5678", false),
        ] {
            let text = source.replace("18F27Q10", dev)
                .replace("Clock = 64", "Clock = 32")
                .replace("RSTOSC = HFINTOSC_64MHZ", if dev.starts_with("16") { "RSTOSC = HFINTOSC_32MHz" } else { "RSTOSC = HFINTOSC_64MHZ" })
                .replace(from, edit);
            let src = out.join(format!("{name}_{dev}.bas"));
            let asm = src.with_extension("S");
            std::fs::write(&src, text).unwrap();
            let r = Command::new(basil()).arg("-S").arg(&src).arg("-o").arg(&asm).output().unwrap();
            assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
            let text = std::fs::read_to_string(asm).unwrap();
            assert_eq!(!data_addrs(&text).contains_key("T_WORK__B"), shared, "{name} {dev}");
        }
    }
}

/// The bank placement trial must keep the measured control-program saving, including page sizing.
#[test]
fn pic16_bank_placement_reduces_control_program() {
    let out = scratch("bankplacement");
    let src = for_p16(&root().join("bench/large/d_ctrl.bas"), "16F18346", &out.join("control.bas"));
    let asm = out.join("control.S");
    let r = Command::new(basil()).arg("-S").arg("--report").arg(src).arg("-o").arg(&asm).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let report = String::from_utf8_lossy(&r.stdout);
    let words: u32 = report.split("Program: ").nth(1).unwrap().split_whitespace().next().unwrap().parse().unwrap();
    let ram: u32 = report.split("total ").nth(1).unwrap().split_whitespace().next().unwrap().parse().unwrap();
    assert!(words <= 861, "{report}");
    assert!(ram <= 237, "{report}");
    let text = std::fs::read_to_string(asm).unwrap();
    assert!(text.lines().filter(|l| l.trim_start().starts_with("movlb ")).count() <= 31);
    let debug_asm = out.join("control_debug.S");
    let r = Command::new(basil()).args(["-S", "-g"]).arg(out.join("control.bas")).arg("-o").arg(&debug_asm).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let debug = std::fs::read_to_string(debug_asm).unwrap();
    let code = |s: &str| s[s.find("PSECT code,").unwrap()..].lines().filter(|l| !l.starts_with("#line ")).collect::<Vec<_>>().join("\n");
    assert_eq!(code(&text), code(&debug), "debug markers changed bank placement or code");

}

/// Fully initialized local arrays lose their entry clears; partial words and volatile arrays retain them.
#[test]
fn initialized_arrays_drop_only_redundant_entry_clears() {
    let out = scratch("arrayinit");
    let source = std::fs::read_to_string(root().join("tests/exec/array_init.bas")).unwrap();
    for dev in ["18F27Q10", "16F17146"] {
        for (name, from, to, cleared) in [
            ("full", "buf(i) = x + i", "buf(i) = x + i", false),
            ("partial_word", "buf(i) = x + i", "buf(i).Byte0 = Byte(x + i)", true),
            ("volatile", "Dim buf(16) As Word", "Volatile Dim buf(16) As Word", true),
        ] {
            let src = out.join(format!("{name}_{dev}.bas"));
            std::fs::write(&src, source.replacen(from, to, 1)).unwrap();
            if dev.starts_with("16") { for_p16(&src, dev, &src); }
            let asm = src.with_extension("S");
            let r = Command::new(basil()).args(["-S", "--report"]).arg(&src).arg("-o").arg(&asm).output().unwrap();
            assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
            let text = std::fs::read_to_string(&asm).unwrap();
            let filled = text.split("T_FILLED:").nth(1).unwrap().split("T_PARTIALBUF:").next().unwrap();
            let partial = text.split("T_PARTIALBUF:").nth(1).unwrap().split("T_BRANCHBUF:").next().unwrap();
            let clear = if dev.starts_with("18") { "clrf POSTINC0" } else { "movwi FSR0++" };
            assert_eq!(filled.contains(clear), cleared, "{name} {dev}: {filled}");
            assert!(partial.contains(clear), "{dev}: an unwritten element still needs its zero");
            if name == "full" {
                let report = String::from_utf8_lossy(&r.stdout);
                let words: u32 = report.split("Program: ").nth(1).unwrap().split_whitespace().next().unwrap().parse().unwrap();
                assert!(words <= if dev.starts_with("18") { 138 } else { 181 }, "{report}");
                let debug_asm = src.with_extension("debug.S");
                let r = Command::new(basil()).args(["-S", "-g"]).arg(&src).arg("-o").arg(&debug_asm).output().unwrap();
                assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
                let debug = std::fs::read_to_string(debug_asm).unwrap();
                let code = |s: &str| s[s.find("PSECT code,").unwrap()..].lines().filter(|l| !l.starts_with("#line ")).collect::<Vec<_>>().join("\n");
                assert_eq!(code(&text), code(&debug), "-g changed array initialization code");

            }
        }
    }
}

/// The array-clear pass is not blocked by a named SFR access or a pointer parameter elsewhere in the program, and a
/// local whose element address is passed on keeps its clear.
#[test]
fn array_clear_guard_ignores_named_sfrs_and_pointer_parameters() {
    let out = scratch("arrayguard");
    let asm = out.join("guard.S");
    let r = Command::new(basil()).args(["-S"]).arg(root().join("tests/exec/array_init_guard.bas")).arg("-o").arg(&asm).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let text = std::fs::read_to_string(&asm).unwrap();
    let filled = text.split("T_FILLED:").nth(1).unwrap().split("T_ESCAPED:").next().unwrap();
    let escaped = text.split("T_ESCAPED:").nth(1).unwrap();
    assert!(!filled.contains("clrf POSTINC0"), "{filled}");
    assert!(escaped.contains("clrf T_ESCAPED__BUF"), "{escaped}");
}

/// Tables in later pages must not force MOVLP when all code remains in the reset page.
#[test]
fn pic16_tables_do_not_force_code_page_selections() {
    let out = scratch("flashpages");
    let src = root().join("tests/exec_p16/float_random.bas");
    let asm = out.join("float.S");
    let r = Command::new(basil()).args(["-S", "--report"]).arg(&src).arg("-o").arg(&asm).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let text = std::fs::read_to_string(&asm).unwrap();
    let report = String::from_utf8_lossy(&r.stdout);
    let words: u32 = report.split("Program: ").nth(1).unwrap().split_whitespace().next().unwrap().parse().unwrap();
    assert!(words > 2048 && words <= 3969, "{report}");
    assert!(!text.lines().any(|l| l.trim_start().starts_with("movlp ")), "unnecessary page selections");
    assert!(text.lines().any(|l| l.starts_with(";SYM __CA") && u32::from_str_radix(l.split("0x").nth(1).unwrap(), 16).unwrap() >= 2048));
    let debug = out.join("float_debug.S");
    let r = Command::new(basil()).args(["-S", "-g"]).arg(&src).arg("-o").arg(&debug).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let code = |s: &str| s[s.find("PSECT code,").unwrap()..].lines().filter(|l| !l.starts_with("#line ")).collect::<Vec<_>>().join("\n");
    assert_eq!(code(&text), code(&std::fs::read_to_string(debug).unwrap()), "debug info changed paging");
    for (name, extra, suffix) in [
        ("reference", vec!["-O0"], ""),
        ("latch", vec![], "\nPCLATH = 0\n"),
        ("assembly", vec![], "\nAsm\n    movwf PCLATH\nEnd Asm\n"),
        ("macro", vec![], "\nAsm\n    pagesel __reset\nEnd Asm\n"),
    ] {
        let f = out.join(format!("{name}.bas"));
        std::fs::write(&f, std::fs::read_to_string(&src).unwrap() + suffix).unwrap();
        let s = f.with_extension("S");
        let r = Command::new(basil()).arg("-S").args(extra).arg(f).arg("-o").arg(&s).output().unwrap();
        assert!(r.status.success(), "{name}: {}", String::from_utf8_lossy(&r.stderr));
        assert!(std::fs::read_to_string(s).unwrap().lines().any(|l| l.trim_start().starts_with("movlp ")), "{name}: paging must remain");
    }
}

/// Code in page one still needs selections, including a return to a caller whose latch differs.
#[test]
fn pic16_real_code_in_later_pages_keeps_page_selections() {
    let out = scratch("realpages");
    let src = out.join("pages.bas");
    let body = format!("' expect: PAGES_ANSWER=133\nProgram Pages\nDevice = 16F17146\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nVolatile Dim answer As Word\nNoInline Function A(ByVal x As Word) As Word\nAsm\n{}End Asm\nResult = x + 7\nEnd Function\nNoInline Function B(ByVal x As Word) As Word\nResult = x + 3\nEnd Function\nanswer = A(20)\nanswer = answer + B(10)\nanswer = answer + B(20)\nanswer = answer + A(30)\nanswer = answer + B(30)\n", "nop\n".repeat(2100));
    std::fs::write(&src, body).unwrap();
    let asm = src.with_extension("S");
    let r = Command::new(basil()).arg("-S").arg(src).arg("-o").arg(&asm).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let text = std::fs::read_to_string(asm).unwrap();
    let b = text.lines().find(|l| l.starts_with(";SYM PAGES_B ")).unwrap().split("0x").nth(1).unwrap();
    let addr = u32::from_str_radix(b, 16).unwrap();
    assert!(addr >= 2048);
    assert!(text.contains(&format!("movlp 0x{:02X}", (addr >> 8) & 0x7f)), "the later page must be selected");
    assert_eq!(text.lines().filter(|l| l.trim_start().starts_with("movlp ")).count(), 3);
    let debug = out.join("pages_debug.S");
    let r = Command::new(basil()).args(["-S", "-g"]).arg(out.join("pages.bas")).arg("-o").arg(&debug).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let debug = std::fs::read_to_string(debug).unwrap();
    let code = |s: &str| s[s.find("PSECT code,").unwrap()..].lines().filter(|l| !l.starts_with("#line ")).collect::<Vec<_>>().join("\n");
    assert_eq!(code(&text), code(&debug));
}

/// Hardware interrupt shadowing preserves the reset-page invariant; an explicit shadow read does not.
#[test]
fn pic16_interrupts_with_late_tables_preserve_page_zero() {
    let out = scratch("interruptpages");
    let src = out.join("irq.bas");
    let text = std::fs::read_to_string(root().join("tests/exec_p16/isr_single.bas")).unwrap();
    let pad = (0..2050).map(|i| (i & 255).to_string()).collect::<Vec<_>>().join(",");
    let text = text.replacen("Function Mix(", &format!("Volatile Dim sample As Byte\nConst Pad(2050) As Byte = ({pad})\nFunction Mix("), 1) + "\nsample = Pad(Byte(n))\n";
    for (name, suffix, pages) in [("table", "", false), ("shadow", "\nsample = PCLATH_SHAD\n", true), ("assembly", "\nAsm\n    nop\nEnd Asm\n", true)] {
        std::fs::write(&src, text.clone() + suffix).unwrap();
        let asm = out.join(format!("{name}.S"));
        let r = Command::new(basil()).args(["-S", "--report"]).arg(&src).arg("-o").arg(&asm).output().unwrap();
        assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
        let report = String::from_utf8_lossy(&r.stdout);
        let words: u32 = report.split("Program: ").nth(1).unwrap().split_whitespace().next().unwrap().parse().unwrap();
        assert!(words > 2048);
        let asm = std::fs::read_to_string(asm).unwrap();
        assert_eq!(asm.lines().any(|l| l.trim_start().starts_with("movlp ")), pages, "{name}");
    }
}

/// PIC16 arrays span GPR banks without occupying the common bytes inside the apparent address interval.
#[test]
fn pic16_ram_report_counts_physical_bytes_across_banks() {
    let out = scratch("physicalram");
    let src = out.join("ram.bas");
    std::fs::write(&src, "Program RamCheck\nDevice = 16F17146\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nVolatile Dim buf(160) As Byte\nVolatile Dim sample As Byte\nbuf(0) = PORTA\nbuf(159) = PORTA\nsample = buf(PORTA And 127)\n").unwrap();
    let r = Command::new(basil()).args(["-S", "--report"]).arg(src).arg("-o").arg(out.join("ram.S")).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let report = String::from_utf8_lossy(&r.stdout);
    assert!(report.contains("total 162 bytes"), "{report}");
}

/// Word walks must keep full byte offsets and stop at code that can clobber the FSR.
#[test]
fn pic16_signed_power_of_two_division_and_fallbacks() {
    let out = scratch("signed_div_pow2");
    let source = "Program DP\nDevice = 16F17146\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nVolatile Dim a, d, r1, r2, r3 As Integer\nr1 = a / 8\nr2 = a / 32\nr3 = a / 2\n";
    for (name, text, flags, specialized) in [
        ("balanced", source.to_string(), vec![], true),
        ("kept", source.to_string(), vec!["--keep-vars"], true),
        ("speed", source.replace("Volatile Dim", "#option Optimize = Speed\nVolatile Dim"), vec![], true),
        ("unoptimized", source.to_string(), vec!["-O0"], false),
        ("negative", source.replace("/ 8", "/ -8").replace("/ 32", "/ -32").replace("/ 2", "/ -2"), vec![], false),
        ("other_constant", source.replace("/ 8", "/ 3").replace("/ 32", "/ 3").replace("/ 2", "/ 3"), vec![], false),
        ("variable", source.replace("/ 8", "/ d").replace("/ 32", "/ d").replace("/ 2", "/ d"), vec![], false),
        ("unsigned", source.replace("As Integer", "As Word"), vec![], false),
        ("mixed", source.replace("r1 = a / 8", "r1 = a / d").replace("r2 = a / 32", "r2 = a / 3"), vec![], false),
    ] {
        let src = out.join(format!("{name}.bas"));
        let asm = src.with_extension("S");
        std::fs::write(&src, text).unwrap();
        let r = Command::new(basil()).arg("-S").args(flags).arg(src).arg("-o").arg(&asm).output().unwrap();
        assert!(r.status.success(), "{name}: {}", String::from_utf8_lossy(&r.stderr));
        let text = std::fs::read_to_string(asm).unwrap();
        if name == "speed" {
            assert!(text.contains("asrf __A1, f"));
            assert!(!text.contains("__sdivp2"));
            assert!(!text.contains("__sdiv2"));
        } else {
            assert_eq!(text.contains("call __sdivp2"), specialized, "{name}");
        }
        if matches!(name, "negative" | "other_constant" | "variable" | "unoptimized") {
            assert!(text.contains("call __sdiv2"), "general signed divide: {name}");
        }
        if name == "mixed" {
            assert!(!text.contains("asrf __A1"), "unprofitable inline specialization must also be rejected");
        }
    }
    let src = for_p16(&root().join("tests/exec/signed_div_pow2_shared.bas"), "16F18346", &out.join("shared.bas"));
    let asm = src.with_extension("S");
    let r = Command::new(basil()).arg("-S").arg(src).arg("-o").arg(&asm).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let text = std::fs::read_to_string(asm).unwrap();
    assert_eq!(text.matches("call __sdivp").count(), 14, "shared fixture must exercise specialization");
}

#[test]
fn pic16_word_array_walks_and_dsp_size() {
    let out = scratch("wordwalk");
    let source = "Program W\nDevice = 16F17146\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nDim a(8) As Word\nDim i As Byte\nVolatile Dim sink As Word\nNoInline Sub Touch()\nsink = sink + 1\nEnd Sub\nFor i = 0 To 7\na(i) = Word(i) * 3\nNext\nsink = a(7)\n";
    for (name, text, walking) in [
        ("plain", source.to_string(), true),
        ("volatile", source.replace("Dim a(8)", "Volatile Dim a(8)"), false),
        ("call", source.replace("a(i) =", "Touch()\na(i) ="), false),
        ("descending", source.replace("0 To 7", "7 To 0 Step -1"), false),
    ] {
        let src = out.join(format!("{name}.bas"));
        let asm = src.with_extension("S");
        std::fs::write(&src, text).unwrap();
        let r = Command::new(basil()).arg("-S").arg(src).arg("-o").arg(&asm).output().unwrap();
        assert!(r.status.success(), "{name}: {}", String::from_utf8_lossy(&r.stderr));
        let text = std::fs::read_to_string(asm).unwrap();
        assert_eq!(text.contains("addfsr FSR0, 2"), walking, "{name}");
    }
    let src = for_p16(&root().join("bench/large/b_dsp.bas"), "16F18346", &out.join("dsp.bas"));
    let asm = src.with_extension("S");
    let r = Command::new(basil()).args(["-S", "--report"]).arg(&src).arg("-o").arg(&asm).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let report = String::from_utf8_lossy(&r.stdout);
    let words: u32 = report.split("Program: ").nth(1).unwrap().split_whitespace().next().unwrap().parse().unwrap();
    let ram: u32 = report.split("total ").nth(1).unwrap().split_whitespace().next().unwrap().parse().unwrap();
    assert!(words <= 1448, "{report}");
    assert!(ram <= 164, "{report}");
    let text = std::fs::read_to_string(&asm).unwrap();
    for name in ["K_LOWPASS__Y", "K_U"] {
        assert!(!text.lines().any(|l| l.trim().starts_with(&format!("movwf {name}"))), "copy into {name} remains");
    }
}


#[test]
fn local_storage_reuse_accepts_known_callees_on_both_cores() {
    let out = scratch("localcalls");
    for dev in ["18F27Q10", "16F17146"] {
        let src = if dev.starts_with("16") {
            for_p16(&root().join("tests/exec/local_reuse_calls.bas"), dev, &out.join("reuse16.bas"))
        } else { root().join("tests/exec/local_reuse_calls.bas") };
        for (name, flags, shared) in [("release", vec![], true), ("kept", vec!["--keep-vars"], false)] {
            let asm = out.join(format!("{name}_{dev}.S"));
            let r = Command::new(basil()).arg("-S").args(flags).arg(&src).arg("-o").arg(&asm).output().unwrap();
            assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
            let text = std::fs::read_to_string(asm).unwrap();
            assert_eq!(!data_addrs(&text).contains_key("REUSE_WORK__B"), shared, "{name} {dev}");
        }
    }
}


#[test]
fn pic16_two_array_walk_guards() {
    let out = scratch("pairwalk");
    let source = "Program W\nDevice = 16F17146\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nDim a(8), b(8) As Integer\nDim i As Byte\nVolatile Dim sink As LongInt\nNoInline Sub Touch()\nsink = sink + 1\nEnd Sub\nFor i = 0 To 7\nsink = sink + a(i) * b(i)\nNext\n";
    for (name, text, flags, walking) in [
        ("plain", source.to_string(), vec![], true),
        ("unoptimized", source.to_string(), vec!["-O0"], false),
        ("volatile", source.replace("Dim a(8)", "Volatile Dim a(8)"), vec![], false),
        ("call", source.replace("sink = sink + a(i)", "Touch()\nsink = sink + a(i)"), vec![], false),
        ("descending", source.replace("0 To 7", "7 To 0 Step -1"), vec![], false),
        ("conditional", source.replace("sink = sink + a(i) * b(i)", "If i <> 3 Then\nsink = sink + a(i) * b(i)\nEnd If"), vec![], false),
        ("write", source.replace("sink = sink + a(i) * b(i)", "a(i) = b(i)"), vec![], false),
    ] {
        let src = out.join(format!("{name}.bas"));
        let asm = src.with_extension("S");
        std::fs::write(&src, text).unwrap();
        let r = Command::new(basil()).arg("-S").args(flags).arg(src).arg("-o").arg(&asm).output().unwrap();
        assert!(r.status.success(), "{name}: {}", String::from_utf8_lossy(&r.stderr));
        let text = std::fs::read_to_string(asm).unwrap();
        assert_eq!(text.contains("addfsr FSR1, 2"), walking, "{name}");
        assert_eq!(text.contains("moviw 0[FSR1]\n    movwf __B0"), walking, "direct multiply operand: {name}");
    }
}

#[test]
fn dsp_inlined_fir_result_is_built_in_saved_destination() {
    let dir = scratch("dsp_result_retarget");
    let out = dir.join("b_dsp.hex");
    let r = Command::new(basil()).arg(root().join("bench/large/b_dsp.bas"))
        .args(["-S"]).arg("-o").arg(&out).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let asm = std::fs::read_to_string(dir.join("b_dsp.S")).unwrap();
    assert!(!asm.lines().any(|l| l.trim_start().starts_with("movff K_FIR__RESULT,")));
    assert!(!asm.lines().any(|l| l.trim_start().starts_with("movff K_FIR__RESULT+1,")));
    assert!(asm.contains("movff __A0, K_F\n"));
    assert!(asm.contains("movff __A1, K_F+1\n"));
}

#[test]
fn pic16_dsp_result_retargeting() {
    let dir = scratch("dsp_result16");
    let src = for_p16(&root().join("bench/large/b_dsp.bas"), "16F18346", &dir.join("dsp.bas"));
    let asm = dir.join("dsp.S");
    let r = Command::new(basil()).arg("-S").arg(src).arg("-o").arg(&asm).output().unwrap();
    assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
    let text = std::fs::read_to_string(asm).unwrap();
    for name in ["K_FIR__RESULT", "K_LOWPASS__RESULT"] {
        assert!(!text.lines().any(|l| l.trim().starts_with(&format!("movwf {name}"))), "staged result: {name}");
        assert!(!text.lines().any(|l| l.trim().starts_with(&format!("movf {name},"))), "staged result read: {name}");
        assert!(!text.lines().any(|l| l.trim().starts_with(&format!("movf {name}+1,"))), "staged high result read: {name}");
    }
}

#[test]
fn pic16_descending_copy_guards() {
    let out = scratch("descending_copy");
    let source = "Program W\nDevice = 16F17146\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nDim a(8) As Integer\nDim i As Byte\nVolatile Dim sink As Integer\nFor i = 7 To 1 Step -1\na(i) = a(i - 1)\nNext\nsink = a(7)\n";
    for (name, text, flags, walking) in [
        ("plain", source.to_string(), vec![], true),
        ("unoptimized", source.to_string(), vec!["-O0"], false),
        ("volatile", source.replace("Dim a(8)", "Volatile Dim a(8)"), vec![], false),
        ("wrap", source.replace("7 To 1", "7 To 0"), vec![], false),
        ("conditional", source.replace("a(i) = a(i - 1)", "If i <> 3 Then\na(i) = a(i - 1)\nEnd If"), vec![], false),
    ] {
        let src = out.join(format!("{name}.bas"));
        let asm = src.with_extension("S");
        std::fs::write(&src, text).unwrap();
        let r = Command::new(basil()).arg("-S").args(flags).arg(src).arg("-o").arg(&asm).output().unwrap();
        assert!(r.status.success(), "{name}: {}", String::from_utf8_lossy(&r.stderr));
        let text = std::fs::read_to_string(asm).unwrap();
        assert_eq!(text.contains("addfsr FSR1, -2"), walking, "{name}");
    }
}

#[test]
fn pic16_byte_divisor_and_paired_results() {
    let out = scratch("pic16_div_pair");
    let source = "Program DP\nDevice = 16F17146\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nDim value As Word\nVolatile Dim sink As Byte\nvalue = Word(PORTA) * 257\nsink = Byte(value Mod 11) + 48\nvalue = value / 11\nsink = Byte(value)\n";
    for (name, source, flags, calls) in [
        ("paired", source.to_string(), vec![], 1),
        ("volatile", source.replace("Dim value", "Volatile Dim value"), vec![], 2),
        ("unoptimized", source.to_string(), vec!["-O0"], 2),
    ] {
        let src = out.join(format!("{name}.bas"));
        let asm = src.with_extension("S");
        std::fs::write(&src, source).unwrap();
        let r = Command::new(basil()).arg("-S").args(flags).arg(&src).arg("-o").arg(&asm).output().unwrap();
        assert!(r.status.success(), "{}", String::from_utf8_lossy(&r.stderr));
        let text = std::fs::read_to_string(asm).unwrap();
        let helper = if name == "unoptimized" { "call __udiv2" } else { "call __divk2" };
        if name == "paired" {
            assert_eq!(text.matches("movlw 16").count(), 1, "{text}");
            assert!(!text.contains("subwfb"), "byte remainder: {text}");
        } else {
            assert_eq!(text.matches(helper).count(), calls, "{name}: {text}");
        }
    }
}

#[test]
fn pic16_word_divisor_and_paired_results() {
    let out = scratch("pic16_word_div_pair");
    for (name, divisor, signed, flags, helper, calls) in [
        ("paired", 1023, false, vec![], "divw4", 1),
        ("max", 65535, false, vec![], "divw4", 1),
        ("byte", 255, false, vec![], "divk4", 1),
        ("wide", 65537, false, vec![], "udiv4", 1),
        ("signed", 1023, true, vec![], "sdiv4", 1),
        ("unoptimized", 1023, false, vec!["-O0"], "udiv4", 2),
    ] {
        let ty = if signed { "LongInt" } else { "LongWord" };
        let source = format!("Program DP\nDevice = 16F17146\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nDim value As {ty}\nVolatile Dim q, r As {ty}\nvalue = {ty}(PORTA) * 5000\nr = value Mod {divisor}\nq = value / {divisor}\n");
        let src = out.join(format!("{name}.bas"));
        let asm = src.with_extension("S");
        std::fs::write(&src, source).unwrap();
        let result = Command::new(basil()).arg("-S").args(flags).arg(&src).arg("-o").arg(&asm).output().unwrap();
        assert!(result.status.success(), "{name}: {}", String::from_utf8_lossy(&result.stderr));
        let text = std::fs::read_to_string(asm).unwrap();
        // A helper with a single caller is inlined by the assembly pass.
        if helper == "divw4" || helper == "divk4" {
            assert_eq!(text.matches("movlw 32").count(), calls + 1, "{name}: {text}");
            assert_eq!(text.contains("rlf __C1, f"), helper == "divw4", "{name}: {text}");
            assert!(!text.contains("rlf __C2, f"), "{name}: {text}");
        } else {
            assert!(text.contains("rlf __C3, f"), "{name}: {text}");
        }
    }
}

#[test]
fn pic16_word_divten_selection() {
    let out = scratch("pic16_divten");
    for (name, ty, divisor, flags, specialized) in [
        ("word", "Word", 10, vec![], true),
        ("signed", "Integer", 10, vec![], false),
        ("long", "LongWord", 10, vec![], false),
        ("other", "Word", 11, vec![], false),
        ("unoptimized", "Word", 10, vec!["-O0"], false),
    ] {
        let source = format!("Program DT\nDevice = 16F17146\nClock = 32\nConfig FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\nVolatile Dim value, q, r As {ty}\nvalue = {ty}(PORTA)\nq = value / {divisor}\nr = value Mod {divisor}\n");
        let src = out.join(format!("{name}.bas"));
        let asm = src.with_extension("S");
        std::fs::write(&src, source).unwrap();
        let result = Command::new(basil()).arg("-S").args(flags).arg(src).arg("-o").arg(&asm).output().unwrap();
        assert!(result.status.success(), "{name}: {}", String::from_utf8_lossy(&result.stderr));
        let text = std::fs::read_to_string(asm).unwrap();
        assert_eq!(text.contains("call __divten2"), specialized, "{name}: {text}");
    }
}
