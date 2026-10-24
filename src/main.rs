//! basicc — BASIC compiler for PIC microcontrollers (milestone M0 skeleton).
//!
//! Nothing is implemented yet; see PLAN.md for the milestones.

use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("--version") | Some("-V") => {
            println!("basicc {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        Some(path) if !path.starts_with('-') => {
            eprintln!("basicc: the compiler is not implemented yet (milestone M0); cannot compile {path}");
            ExitCode::from(2)
        }
        _ => {
            eprintln!("usage: basicc [--version] <program.bas>");
            ExitCode::from(2)
        }
    }
}
