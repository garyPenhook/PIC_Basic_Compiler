//! basicc — BASIC compiler for PIC microcontrollers.
//!
//! Milestone M3: the front end (lexer, parser, semantic analysis) is complete; there is no code
//! generator yet, so `basicc prog.bas` checks the program and reports diagnostics.

use basicc::diag::{Diagnostics, Render, Severity};
use basicc::project::{LoadConfig, load};
use basicc::sema::{SemaConfig, analyze};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "usage: basicc [--check] [-D NAME] [-L LIBDIR] [--devices DIR] [--version] <program.bas>";

/// Folders named `name` in `start` and each of its parents, nearest first.
fn ancestors_with(start: &Path, name: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut cur = Some(start.to_path_buf());
    while let Some(d) = cur {
        let cand = d.join(name);
        if cand.is_dir() {
            out.push(cand);
        }
        cur = d.parent().map(Path::to_path_buf);
    }
    out
}

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let mut file: Option<PathBuf> = None;
    let mut check_only = false;
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
    lib_dirs.extend(ancestors_with(&start, "lib"));
    dev_dirs.extend(ancestors_with(&start, "devices"));
    let home = Path::new(env!("CARGO_MANIFEST_DIR"));
    lib_dirs.push(home.join("lib"));
    dev_dirs.push(home.join("devices"));

    let mut diags = Diagnostics::default();
    let project = load(&file, &LoadConfig { lib_dirs, defines }, &mut diags);
    // Run semantic analysis even after syntax errors in other units so that one run reports as
    // much as possible, but not when the main file did not parse at all.
    let analysis = analyze(&project, &SemaConfig { devices_dirs: dev_dirs }, &mut diags);
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
    let dev = analysis.device.as_ref().map(|d| d.device.name.as_str()).unwrap_or("no device");
    eprintln!("basicc: front end OK ({} unit(s), {dev}, {warnings} warning(s))", project.units.len());
    if check_only {
        ExitCode::SUCCESS
    } else {
        eprintln!("basicc: code generation is not implemented yet (milestone M4)");
        ExitCode::from(2)
    }
}

fn usage() -> ExitCode {
    eprintln!("{USAGE}");
    ExitCode::from(2)
}
