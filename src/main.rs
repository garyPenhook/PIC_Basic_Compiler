//! basil — BASIC compiler for PIC microcontrollers.
//!
//! `basil prog.bas` compiles to `prog.hex` (with `prog.S` and `prog.map` beside it) through
//! pic-as. `--check` stops after the front end, `-S` stops after writing the assembly.

use basil::codegen::generate;
use basil::diag::{Diagnostics, Render, Severity};
use basil::toolchain;
use basil::driver::{c_stub, report, run_pic_as, run_xc8_cc, target_of, usage_summary};
use basil::lower::lower;
use basil::project::{LoadConfig, load};
use basil::sema::{SemaConfig, analyze};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "usage: basil [options] <program.bas>\nTry 'basil --help' for more information.";

const HELP: &str = "basil - BASIC compiler for PIC microcontrollers

usage: basil [options] <program.bas>

Compiles <program.bas> to <program>.hex, with <program>.S (assembly) and
<program>.map beside it.

options:
  -o FILE         write the hex file to FILE
  --check         front end only (syntax, types, declarations); no output files
  -S              stop after writing the assembly
  --report        also print words per routine and every RAM object
  -O0             no optimisation (-O1, -O2 and -Os mean the default, optimise)
  -g              debug build: line, variable and routine information in <program>.elf
  --dual          two builds in one run: the optimised release (<program>.hex, .elf, .S, .map)
                  and an unoptimised debug build that keeps every variable
                  (<program>_debug.hex, _debug.elf with all symbols, _debug.S, _debug.map)
  --keep-vars     keep stores to variables nothing reads (for simulator tests)
  -D NAME         define a preprocessor name (repeatable)
  -L DIR          add a library folder (repeatable)
  --devices DIR   folder holding the device descriptions
  --pic-as PATH   the pic-as assembler (default: $BASIL_PICAS, then pic-as on PATH,
                  then the newest MPLAB XC8 install)
  --dfp DIR       the device pack's xc8 folder (default: $BASIL_DFP, then the pack the
                  device file names under ~/.mchp_packs/Microchip or MPLAB X's packs)
  --xc8-cc PATH   the xc8-cc C compiler (default: $BASIL_XC8CC, then the XC8 install of pic-as)
  --packs DIR     an extra folder holding device packs as <pack>/<version>/xc8 (repeatable;
                  also $BASIL_PACKS)
  --doctor        show which tools and packs basil found, and exit non-zero if one is missing
  -V, --version   print the version and exit
  -h, --help      print this help and exit

Tool paths can also be kept in ~/.config/basil/config (%APPDATA%\\basil\\config on Windows)
as `pic-as = PATH`, `xc8-cc = PATH`, `dfp = DIR` and `packs = DIR` lines; flags and
environment variables win over it.

lib/ and devices/ are found in the source file's folder or the nearest parent; the
modules and devices built into basil are used last.
Full documentation: docs/MANUAL.md
";

/// The nearest folder called `name` in `start` or one of its parents. Only the nearest is used,
/// so a stray `lib` or `devices` folder higher up cannot shadow the project's own.
fn nearest_with(start: &Path, name: &str) -> Option<PathBuf> {
    start.ancestors().map(|d| d.join(name)).find(|c| c.is_dir())
}

/// `--doctor`: what basil found on this machine. Fails when pic-as or every pack folder is missing.
fn doctor() -> ExitCode {
    let mut ok = true;
    println!("basil {}", env!("CARGO_PKG_VERSION"));
    match toolchain::config_path() {
        Some(p) if p.is_file() => println!("settings: {}", p.display()),
        Some(p) => println!("settings: none (optional file: {})", p.display()),
        None => {}
    }
    match toolchain::resolve_pic_as(None) {
        Ok(p) => {
            let v = std::process::Command::new(&p).arg("--version").output().ok().map(|o| String::from_utf8_lossy(if o.stdout.is_empty() { &o.stderr } else { &o.stdout }).lines().next().unwrap_or("").trim().to_string()).unwrap_or_default();
            println!("pic-as:  {}{}", p.display(), if v.is_empty() { String::new() } else { format!("  ({v})") });
            match toolchain::resolve_xc8_cc(&p, None) {
                Ok(c) => println!("xc8-cc:  {}", c.display()),
                Err(e) => println!("xc8-cc:  missing (only programs that call C need it)\n         {e}"),
            }
        }
        Err(e) => {
            ok = false;
            println!("pic-as:  MISSING\n{e}");
        }
    }
    let roots = toolchain::pack_roots(&[]);
    let mut any = false;
    for r in &roots {
        let n = std::fs::read_dir(r).map(|d| d.filter_map(|e| e.ok()).filter(|e| e.path().is_dir()).count()).unwrap_or(0);
        println!("packs:   {} ({n} found)", r.display());
        any |= n > 0;
    }
    if !any {
        ok = false;
        println!("packs:   MISSING: no device packs in {}\n         install them with MPLAB X (Tools > Packs) or set BASIL_DFP / pass --dfp", roots.iter().map(|r| r.display().to_string()).collect::<Vec<_>>().join(", "));
    }
    match basil::embedded::dirs() {
        Some((lib, dev)) => println!("built-in: lib {}, devices {}", lib.display(), dev.display()),
        None => println!("built-in: lib and devices cache not writable; only folders next to the program are used"),
    }
    if ok { ExitCode::SUCCESS } else { ExitCode::from(1) }
}

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let mut file: Option<PathBuf> = None;
    let mut check_only = false;
    let mut asm_only = false;
    let mut want_report = false;
    let mut optimise = true;
    let mut keep_vars = false;
    let mut debug = false;
    let mut dual = false;
    let mut out_hex: Option<PathBuf> = None;
    let mut pic_as: Option<PathBuf> = None;
    let mut dfp_arg: Option<PathBuf> = None;
    let mut xc8_arg: Option<PathBuf> = None;
    let mut pack_dirs: Vec<PathBuf> = Vec::new();
    let mut defines = Vec::new();
    let mut lib_dirs = Vec::new();
    let mut dev_dirs = Vec::new();
    while let Some(a) = args.next() {
        match a.as_str() {
            "--version" | "-V" => {
                println!("basil {}", env!("CARGO_PKG_VERSION"));
                return ExitCode::SUCCESS;
            }
            "--help" | "-h" => {
                print!("{HELP}");
                return ExitCode::SUCCESS;
            }
            "--check" => check_only = true,
            "-S" => asm_only = true,
            "--report" => want_report = true,
            "-O0" => optimise = false,
            "--keep-vars" => keep_vars = true,
            "-g" => debug = true,
            "--dual" => dual = true,
            "-O1" | "-O2" | "-Os" => optimise = true,
            "-o" => match args.next() {
                Some(v) => out_hex = Some(PathBuf::from(v)),
                None => return usage(),
            },
            "--pic-as" => match args.next() {
                Some(v) => pic_as = Some(PathBuf::from(v)),
                None => return usage(),
            },
            "--dfp" => match args.next() {
                Some(v) => dfp_arg = Some(PathBuf::from(v)),
                None => return usage(),
            },
            "--xc8-cc" => match args.next() {
                Some(v) => xc8_arg = Some(PathBuf::from(v)),
                None => return usage(),
            },
            "--packs" => match args.next() {
                Some(v) => pack_dirs.push(PathBuf::from(v)),
                None => return usage(),
            },
            "--doctor" => return doctor(),
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
    if dual {
        return build_dual(&file, out_hex.as_deref());
    }

    let start = file.canonicalize().ok().and_then(|p| p.parent().map(Path::to_path_buf)).unwrap_or_else(|| PathBuf::from("."));
    lib_dirs.extend(nearest_with(&start, "lib"));
    dev_dirs.extend(nearest_with(&start, "devices"));
    // Last resort: the modules and device descriptions built into this compiler.
    if let Some((lib, dev)) = basil::embedded::dirs() {
        lib_dirs.push(lib);
        dev_dirs.push(dev);
    }

    let mut diags = Diagnostics::default();
    let project = load(&file, &LoadConfig { lib_dirs, defines, devices_dirs: dev_dirs.clone(), optimise }, &mut diags);
    // Run semantic analysis even after syntax errors in other units so that one run reports as
    // much as possible, but not when the main file did not parse at all.
    if project.units.is_empty() {
        for d in &diags.items {
            eprintln!("{}", Render(d, &project.sources));
        }
        eprintln!("basil: {} error(s)", diags.error_count());
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
    // The target is built once: the size trials of the optimiser and the final build see the same options.
    let target = analysis.device.as_ref().map(|dev| {
        let mut target = target_of(dev);
        target.opt = optimise;
        target.keep_vars = keep_vars;
        if debug {
            // Absolute paths, so the debugger finds the sources wherever it is started.
            target.debug_files = project.sources.names().map(|n| std::fs::canonicalize(n).map(|p| p.display().to_string()).unwrap_or_else(|_| n.to_string())).collect();
        }
        target
    });
    if optimise && let Some(p) = &mut program {
        if let Some(t) = &target {
            // Calls that pass constants may get their own copy of the routine; kept only where the program shrinks
            // and still builds (no errors, and the hardware return stack is deep enough).
            basil::opt::optimize_sized(p, &|q| {
                let g = generate(q, t);
                if g.errors.is_empty() && g.stack_levels <= t.hw_stack { Some(g.out.words) } else { None }
            });
        } else {
            basil::opt::optimize(p);
        }
    }
    let mut generated = None;
    if let Some(p) = &program {
        let target = target.as_ref().unwrap();
        let g = generate(p, target);
        for (span, msg) in &g.errors {
            diags.error(if msg.starts_with("out of data RAM") { "E-RAM" } else { "E-BACKEND" }, *span, msg.clone());
        }
        if g.errors.is_empty() && g.stack_levels > target.hw_stack {
            diags.error("E-STACK", basil::diag::Span::default(), format!("the hardware return stack can need {} levels (calls, helpers and interrupt entries) but the device has {}", g.stack_levels, target.hw_stack));
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
        eprintln!("basil: {errors} error(s), {warnings} warning(s)");
        return ExitCode::from(1);
    }
    if check_only {
        eprintln!("basil: front end OK ({} unit(s), {dev_name}, {warnings} warning(s))", project.units.len());
        return ExitCode::SUCCESS;
    }
    let (program, generated) = (program.unwrap(), generated.unwrap());

    let hex = out_hex.unwrap_or_else(|| file.with_extension("hex"));
    // xc8-cc names the object of the C code after the output file, so the assembly must not share its stem.
    let stem = hex.file_stem().and_then(|s| s.to_str()).unwrap_or("out").to_string();
    let asm_path = if !program.c_link() { hex.with_extension("S") } else { hex.with_file_name(format!("{stem}_basil.S")) };
    let map_path = hex.with_extension("map");
    if let Err(e) = std::fs::write(&asm_path, &generated.out.text) {
        eprintln!("basil: cannot write {}: {e}", asm_path.display());
        return ExitCode::from(1);
    }
    // The readable form of the assembly, next to it: BASIC statements, addresses, BASIC variable names.
    let lst_path = hex.with_extension("lst");
    let texts: std::collections::HashMap<String, &str> = project.sources.names().zip(project.sources.texts()).map(|(n, t)| (std::fs::canonicalize(n).map(|p| p.display().to_string()).unwrap_or_else(|_| n.to_string()), t)).collect();
    let lst = basil::listing::listing(&generated.out.text, &|f, n| texts.get(f).and_then(|t| t.lines().nth((n as usize).checked_sub(1)?)).map(str::to_string));
    if let Err(e) = std::fs::write(&lst_path, lst) {
        eprintln!("basil: cannot write {}: {e}", lst_path.display());
    }
    if want_report {
        print!("{}", report(&program, &generated));
    }
    if asm_only {
        eprintln!("basil: wrote {} ({} words)", asm_path.display(), generated.out.words);
        return ExitCode::SUCCESS;
    }
    let pic_as = match toolchain::resolve_pic_as(pic_as.as_deref()) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("basil: {e}");
            return ExitCode::from(1);
        }
    };
    let dev = analysis.device.as_ref().unwrap();
    let dfp = match toolchain::resolve_dfp(dfp_arg.as_deref(), &pack_dirs, &dev.device.pack, &dev.device.pack_version) {
        Ok(d) => {
            if !d.exact {
                eprintln!("basil: warning: device pack {} {} is not installed; using {} ({})", dev.device.pack, dev.device.pack_version, d.version, d.dir.display());
            }
            d.dir
        }
        Err(e) => {
            eprintln!("basil: {e}");
            return ExitCode::from(1);
        }
    };
    let linked = if !program.c_link() {
        run_pic_as(&pic_as, dev, &asm_path, &dfp, &hex, &map_path)
    } else {
        let xc8 = match toolchain::resolve_xc8_cc(&pic_as, xc8_arg.as_deref()) {
            Ok(p) => p,
            Err(e) => {
                eprintln!("basil: {e}");
                return ExitCode::from(1);
            }
        };
        let stub = hex.with_file_name(format!("{stem}_cstub.c"));
        if let Err(e) = std::fs::write(&stub, c_stub(&program.externs, &program.exports)) {
            eprintln!("basil: cannot write {}: {e}", stub.display());
            return ExitCode::from(1);
        }
        let cfiles: Vec<PathBuf> = program.cfiles.iter().map(|f| start.join(f)).collect();
        for f in &cfiles {
            if !f.is_file() {
                eprintln!("basil: C file {} not found (CFile names are relative to the program's folder)", f.display());
                return ExitCode::from(1);
            }
        }
        let reserved = basil::codegen::ram_ranges(&generated.objs, &generated.layout);
        run_xc8_cc(&xc8, dev, &asm_path, &stub, &cfiles, &reserved, &dfp, &hex, &map_path)
    };
    match linked {
        Ok(run) => {
            for line in run.output.lines().filter(|l| !run.ok || l.contains("error") || l.contains("warning")) {
                eprintln!("pic-as: {line}");
            }
            if !run.ok {
                eprintln!("basil: the assembler or linker failed; see {}", asm_path.display());
                return ExitCode::from(1);
            }
        }
        Err(e) => {
            eprintln!("basil: {e}");
            return ExitCode::from(1);
        }
    }
    if debug {
        let elf = hex.with_extension("elf");
        let source = std::fs::canonicalize(&file).unwrap_or_else(|_| file.clone());
        let mut info = generated.debug.clone();
        if program.c_link() {
            // The code is relocatable: addresses so far are offsets from `_basil_entry`.
            let base = std::fs::read_to_string(&map_path).ok().and_then(|m| m.lines().find_map(|l| l.strip_prefix("_basil_entry").and_then(|r| u32::from_str_radix(r.split_whitespace().nth(1)?, 16).ok())));
            match base {
                Some(b) => {
                    for f in &mut info.funcs {
                        f.low += b;
                        f.high += b;
                    }
                    info.end += b;
                }
                None => eprintln!("basil: warning: no _basil_entry in {}; the debug addresses are wrong", map_path.display()),
            }
        }
        let done = std::fs::read(&elf).map_err(|e| e.to_string()).and_then(|mut b| basil::dwarf::augment(&mut b, &info, &source.display().to_string()).and_then(|_| std::fs::write(&elf, b).map_err(|e| e.to_string())));
        if let Err(e) = done {
            eprintln!("basil: warning: no variable information in {}: {e}", elf.display());
        }
    }
    if dev.device.family == "pic16e" {
        eprintln!("basil: {} -> {} ({} words)", file.display(), hex.display(), generated.out.words);
    } else {
        eprintln!("basil: {} -> {} ({} words, {} bytes)", file.display(), hex.display(), generated.out.words, generated.out.words * 2);
    }
    let color = std::io::IsTerminal::is_terminal(&std::io::stderr()) && std::env::var_os("NO_COLOR").is_none();
    eprint!("{}", usage_summary(analysis.device.as_ref().unwrap(), &generated, color));
    ExitCode::SUCCESS
}

fn usage() -> ExitCode {
    eprintln!("{USAGE}");
    ExitCode::from(2)
}

/// `--dual`: run this compiler twice with the other options as given: once as the optimised release and once as an
/// unoptimised `-g --keep-vars` build written beside it as `<stem>_debug.*`.
fn build_dual(file: &Path, out_hex: Option<&Path>) -> ExitCode {
    let exe = match std::env::current_exe() {
        Ok(e) => e,
        Err(e) => {
            eprintln!("basil: cannot find myself to run the two builds: {e}");
            return ExitCode::from(1);
        }
    };
    let release = out_hex.map(Path::to_path_buf).unwrap_or_else(|| file.with_extension("hex"));
    let stem = release.file_stem().and_then(|s| s.to_str()).unwrap_or("out").to_string();
    let debug_hex = release.with_file_name(format!("{stem}_debug.hex"));
    // Everything the user passed except --dual, -g, -O*, --keep-vars and -o, which each build sets itself.
    let mut common = Vec::new();
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--dual" | "-g" | "-O0" | "-O1" | "-O2" | "-Os" | "--keep-vars" => {}
            "-o" => {
                args.next();
            }
            _ => common.push(a),
        }
    }
    let runs: [(&str, Vec<String>, &Path); 2] = [
        ("release", vec!["-O2".into()], &release),
        ("debug", vec!["-O0".into(), "-g".into(), "--keep-vars".into()], &debug_hex),
    ];
    for (name, extra, out) in runs {
        eprintln!("basil: {name} build -> {}", out.display());
        let ok = std::process::Command::new(&exe).args(&common).args(&extra).arg("-o").arg(out).status().map(|s| s.success()).unwrap_or(false);
        if !ok {
            eprintln!("basil: the {name} build failed");
            return ExitCode::from(1);
        }
    }
    ExitCode::SUCCESS
}
