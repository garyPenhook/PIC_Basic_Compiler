# Basic_Compiler

A personal BASIC compiler for PIC microcontrollers, with code efficiency as a top priority.
First target: **PIC18F27Q10**. Other microcontrollers will be added slowly, one at a time, later.

* Language: a structured, typed core (modules, subroutines/functions, structures, interrupts)
  with a friendly command library on top.
* Back end: generates assembly for Microchip's `pic-as`, which assembles and links the `.hex`.
* Plan and status: `PLAN.md`, `docs/PROGRESS.md`. Decisions: `docs/DECISIONS.md`.
* Language: `docs/LANGUAGE.md`, `docs/GRAMMAR.md`. Calling convention: `docs/ABI.md`. Benchmarks: `docs/BENCHMARKS.md`.

Status: M5 in progress (back end done in M4; arrays, by-reference parameters, strings, structures, hardware multiply and `DECFSZ` counted loops added). `basicc prog.bas`
compiles programs to `prog.hex` (plus `prog.S`, `prog.map`) through pic-as; `--report` prints sizes, `-S` stops at the
assembly, `--check` stops after the front end. Floats and events (and a few remaining array, string,
structure and by-reference forms) are rejected with `E-BACKEND` until a later milestone. Interrupt handlers and the `gpio`, `delay`, `timer`, `serial` and `serial2` library (`docs/LIBRARY.md`) work (M6).

* Tests: `cargo test`; simulator tests with `BASICC_MDB=1 cargo test --test backend` (needs MPLAB X `mdb`).
* Benchmarks against XC8: `scripts/bench.py`, results in `docs/BENCHMARKS.md`.

Personal-use project. Vendor manuals under `reference/` are not part of the repository and must
not be redistributed.
