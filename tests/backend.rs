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
    assert_eq!(files.len(), 2);
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
    std::fs::write(&bas, "Program T\nDevice = 18F27Q10\nClock = 1\nDim counter As Word = 0\nSub Bump(amount As Byte)\n    Dim local_tmp As Byte\n    local_tmp = amount\n    counter = counter + local_tmp\nEnd Sub\nDo\n    Bump(3)\nLoop\n").unwrap();
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

const P16_PARTS: [&str; 2] = ["16F17126", "16F17146"];

/// The programs of `tests/exec` that run on the enhanced mid-range core with only the `Device`, `Config` and
/// `Clock` lines changed (the others use PIC18 registers, PIC18 assembly or cycle counts of a 64 MHz part).
const P16_PORTABLE: &[&str] = &[
    "absminmax", "arith_byte", "arith_integer", "arith_shortint", "arith_word", "arrays", "bit_packed", "byref", "callopt", "countloop", "events", "events_array_cmp", "events_params",
    "flow", "funcs", "inc", "multidim", "mulzero", "overlay", "reentrant", "review", "rmw", "static_local", "strarray", "str_basic", "str_slice", "str_cat_cmp", "str_cat_assign", "structinit_nested", "agg_result", "agg_params", "agg_byval", "str_num", "forward", "str_slice_ref", "structinit", "structs", "structstr", "tablewalk", "overload",
    "arrays_full", "events_isr", "isr_save", "lib_timer", "lib_timer12", "lib_timer_event", "lib_timer_hw", "lib_lcd", "lib_shift", "lib_oled", "lib_aht30", "lib_rtcc", "lib_rtccspi", "lib_strings",
    "float_basic", "float_compare", "float_muldiv", "float_pow2", "float_nan_order", "float_denormal_cmp", "lib_floatlib", "lib_floatlib_cmp", "lib_floatlib_conv", "lib_floatlib_edge",
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
            // The PIC16F183xx parts call the 32 MHz power-up setting HFINT32 (2x PLL).
            out += if device.starts_with("16F183") { "Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON\n" } else { "Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON\n" };
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
    for flags in ["", "-O0"] {
        let r = Command::new("python3").arg(root().join("scripts/exec-test.py")).arg("--basil").arg(basil()).arg(format!("--flags={flags}")).arg("--device").arg("16F17146").args(&files).output().unwrap();
        let text = String::from_utf8_lossy(&r.stdout).into_owned() + &String::from_utf8_lossy(&r.stderr);
        assert!(r.status.success(), "flags `{flags}`:\n{text}");
    }
}

const P13_PARTS: [&str; 9] = ["16F13113", "16F13114", "16F13115", "16F13123", "16F13124", "16F13125", "16F13143", "16F13144", "16F13145"];

/// Programs of the PIC16F171xx sets that cannot run on the PIC16F13145: too big for its 1 KB of RAM or 8K words of flash, or about a
/// peripheral it lacks (second EUSART, data EEPROM, the 16-bit PWM); `tests/exec_p13` has the 13145 versions of the last few.
const P13_SKIP: &[&str] = &["arith_integer", "arith_word", "lib_oled", "float_compare", "float_pow2", "lib_floatlib_edge", "lib_eeprom", "lib_serial2", "lib_pwm", "lib_adc", "lib_flashwrite"];

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

const P183_PARTS: [&str; 16] = [
    "16F18313", "16F18323", "16F18324", "16F18325", "16F18326", "16F18344", "16F18345", "16F18346", "16LF18313", "16LF18323", "16LF18324", "16LF18325", "16LF18326", "16LF18344", "16LF18345",
    "16LF18346",
];

/// Programs of the PIC16F171xx sets that do not apply to the PIC16F183xx: Timer1 and Timer2 with their clock-select and hardware-limit registers, and the library
/// modules whose registers differ (`tests/exec_p183` has the PIC16F183xx versions).
const P183_SKIP: &[&str] = &["lib_timer12", "lib_timer_hw", "lib_adc", "lib_eeprom", "lib_flashwrite", "lib_i2c", "lib_pwm", "lib_serial", "lib_serial2", "lib_spi"];

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
const P152_SKIP: &[&str] = &["arith_byte", "arith_integer", "arith_shortint", "arith_word", "agg_byval", "arrays_full", "lib_oled", "float_compare", "float_pow2", "lib_floatlib_edge", "lib_adc", "lib_eeprom", "lib_flashwrite", "lib_i2c", "lib_pwm", "lib_serial2", "lib_serial", "lib_spi"];

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
