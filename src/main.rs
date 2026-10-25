//! basicc — BASIC compiler for PIC microcontrollers.
//!
//! `basicc prog.bas` compiles to `prog.hex` (with `prog.S` and `prog.map` beside it) through
//! pic-as. `--check` stops after the front end, `-S` stops after writing the assembly.

use basicc::codegen::generate;
use basicc::diag::{Diagnostics, Render, Severity};
use basicc::driver::{find_pic_as, report, run_pic_as, target_of, usage_summary};
use basicc::lower::lower;
use basicc::project::{LoadConfig, load};
use basicc::sema::{SemaConfig, analyze};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "usage: basicc [--check] [-S] [--report] [-O0] [-o OUT.hex] [-D NAME] [-L LIBDIR] [--devices DIR] [--pic-as PATH] [--version] <program.bas>";

/// The nearest folder called `name` in `start` or one of its parents. Only the nearest is used,
/// so a stray `lib` or `devices` folder higher up cannot shadow the project's own.
fn nearest_with(start: &Path, name: &str) -> Option<PathBuf> {
    start.ancestors().map(|d| d.join(name)).find(|c| c.is_dir())
}

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let mut file: Option<PathBuf> = None;
    let mut check_only = false;
    let mut asm_only = false;
    let mut want_report = false;
    let mut optimise = true;
    let mut out_hex: Option<PathBuf> = None;
    let mut pic_as: Option<PathBuf> = None;
    let mut defines = Vec::new();
    let mut lib_dirs = Vec::new();
    let mut dev_dirs = Vec::new();
    while let Some(a) = args.next() {
        match a.as_str() {
            "--version" | "-V" => {
                println!("basicc {}", env!("CARGO_PKG_VERSION"));
                return ExitCode::SUCCESS;
            }
            "--check" => check_only = true,
            "-S" => asm_only = true,
            "--report" => want_report = true,
            "-O0" => optimise = false,
            "-O1" | "-O2" | "-Os" => optimise = true,
            "-o" => match args.next() {
                Some(v) => out_hex = Some(PathBuf::from(v)),
                None => return usage(),
            },
            "--pic-as" => match args.next() {
                Some(v) => pic_as = Some(PathBuf::from(v)),
                None => return usage(),
            },
            "-D" => match args.next() {
                Some(v) => defines.push(v),
                None => return usage(),
            },
            "-L" => match args.next() {
                Some(v) => lib_dirs.push(PathBuf::from(v)),
                None => return usage(),
            },
            "--devices" => match args.next() {
                Some(v) => dev_dirs.push(PathBuf::from(v)),
                None => return usage(),
            },
            s if s.starts_with('-') => return usage(),
            s => {
                if file.replace(PathBuf::from(s)).is_some() {
                    return usage();
                }
            }
        }
    }
    let Some(file) = file else { return usage() };

    let start = file.canonicalize().ok().and_then(|p| p.parent().map(Path::to_path_buf)).unwrap_or_else(|| PathBuf::from("."));
    lib_dirs.extend(nearest_with(&start, "lib"));
    dev_dirs.extend(nearest_with(&start, "devices"));
    // Last resort for a development build run outside the project tree.
    let home = Path::new(env!("CARGO_MANIFEST_DIR"));
    lib_dirs.push(home.join("lib"));
    dev_dirs.push(home.join("devices"));

    let mut diags = Diagnostics::default();
    let project = load(&file, &LoadConfig { lib_dirs, defines }, &mut diags);
    // Run semantic analysis even after syntax errors in other units so that one run reports as
    // much as possible, but not when the main file did not parse at all.
    if project.units.is_empty() {
        for d in &diags.items {
            eprintln!("{}", Render(d, &project.sources));
        }
        eprintln!("basicc: {} error(s)", diags.error_count());
        return ExitCode::from(1);
    }
    let analysis = analyze(&project, &SemaConfig { devices_dirs: dev_dirs }, &mut diags);
    let dev_name = analysis.device.as_ref().map(|d| d.device.name.clone()).unwrap_or_else(|| "no device".into());
    let front_errors = diags.error_count();

    // Lowering and code generation only run on a program the front end accepted.
    let mut program = None;
    if front_errors == 0 && !check_only {
        program = lower(&project, &analysis, &mut diags);
    }
    let mut generated = None;
    if let Some(p) = &program {
        let dev = analysis.device.as_ref().unwrap();
        let mut target = target_of(dev);
        target.opt = optimise;
        let g = generate(p, &target);
        for (span, msg) in &g.errors {
            diags.error("E-BACKEND", *span, msg.clone());
        }
        if g.errors.is_empty() && g.stack_levels > basicc::codegen::HW_STACK_LEVELS {
            diags.error("E-STACK", basicc::diag::Span::default(), format!("the hardware return stack can need {} levels (calls, helpers and interrupt entries) but the device has {}", g.stack_levels, basicc::codegen::HW_STACK_LEVELS));
        }
        generated = Some(g);
    }

    let mut items = diags.items.clone();
    items.sort_by_key(|d| (d.span.file, d.span.line, d.span.col));
    for d in &items {
        eprintln!("{}", Render(d, &project.sources));
    }
    let errors = diags.error_count();
    let warnings = items.iter().filter(|d| d.severity == Severity::Warning).count();
    if errors > 0 {
        eprintln!("basicc: {errors} error(s), {warnings} warning(s)");
        return ExitCode::from(1);
    }
    if check_only {
        eprintln!("basicc: front end OK ({} unit(s), {dev_name}, {warnings} warning(s))", project.units.len());
        return ExitCode::SUCCESS;
    }
    let (program, generated) = (program.unwrap(), generated.unwrap());

    let hex = out_hex.unwrap_or_else(|| file.with_extension("hex"));
    let asm_path = hex.with_extension("S");
    let map_path = hex.with_extension("map");
    if let Err(e) = std::fs::write(&asm_path, &generated.out.text) {
        eprintln!("basicc: cannot write {}: {e}", asm_path.display());
        return ExitCode::from(1);
    }
    if want_report {
        print!("{}", report(&program, &generated));
    }
    if asm_only {
        eprintln!("basicc: wrote {} ({} words)", asm_path.display(), generated.out.words);
        return ExitCode::SUCCESS;
    }
    let Some(pic_as) = pic_as.or_else(find_pic_as) else {
        eprintln!("basicc: pic-as not found (install MPLAB XC8 or set BASICC_PICAS)");
        return ExitCode::from(1);
    };
    match run_pic_as(&pic_as, analysis.device.as_ref().unwrap(), &asm_path, &hex, &map_path) {
        Ok(run) => {
            for line in run.output.lines().filter(|l| l.contains("error") || l.contains("warning")) {
                eprintln!("pic-as: {line}");
            }
            if !run.ok {
                eprintln!("basicc: pic-as failed; see {}", asm_path.display());
                return ExitCode::from(1);
            }
        }
        Err(e) => {
            eprintln!("basicc: {e}");
            return ExitCode::from(1);
        }
    }
    eprintln!("basicc: {} -> {} ({} words, {} bytes)", file.display(), hex.display(), generated.out.words, generated.out.words * 2);
    let color = std::io::IsTerminal::is_terminal(&std::io::stderr()) && std::env::var_os("NO_COLOR").is_none();
    eprint!("{}", usage_summary(analysis.device.as_ref().unwrap(), &generated, color));
    ExitCode::SUCCESS
}

fn usage() -> ExitCode {
    eprintln!("{USAGE}");
    ExitCode::from(2)
}
