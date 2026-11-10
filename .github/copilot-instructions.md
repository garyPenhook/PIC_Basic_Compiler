# Basic_Compiler (`basil`): instructions for Copilot

Basil is a personal BASIC compiler for 8-bit PIC microcontrollers, written in Rust (edition 2024, workspace members: the root
`basil` crate, `crates/devdesc`, `tools/devgen`). It turns Basil source (`.bas`) into a `.hex` through Microchip's `pic-as`.
Language and library help for writing `.bas` programs is in the user-level `basil` instruction files; this file is about working
**on the compiler itself**. Docs: `docs/MANUAL.md`, `docs/LANGUAGE.md`, `docs/GRAMMAR.md`, `docs/LIBRARY.md`, `docs/DIAGNOSTICS.md`,
`docs/ABI.md`, `docs/DEVICE-FORMAT.md`, `docs/DECISIONS.md` (numbered decisions D1..), `docs/PROGRESS.md`, `PLAN.md`.

## Pipeline (one module per stage, in `src/`)

`project.rs` (load program + `Include`d modules) -> `pp.rs` (line preprocessor, keeps line numbers) -> `lexer.rs` -> `parser.rs`
(recursive descent, grammar in `docs/GRAMMAR.md`) -> `sema.rs` (names, types, constants, language rules; results attached to `NodeId`s,
the tree is not mutated) -> `lower.rs` (checked tree to the width-annotated IR in `ir.rs`) -> `opt.rs` (IR optimisation) ->
code generator (`codegen.rs` for PIC18, `codegen16.rs` + `codegen16/` for the enhanced mid-range PIC16) -> `peephole.rs` / `codegen16/opt.rs`
-> `asm.rs` (branch relaxation, pic-as text) -> `driver.rs` (runs `pic-as`, or `xc8-cc` for C interop; size report). `dwarf.rs` adds debug
info for `-g`. `embedded.rs` bundles `lib/` and `devices/` into the binary. `diag.rs` renders diagnostics. `main.rs` is the CLI.

- The code generators consume only the IR, never the AST. Every integer expression in the IR carries its evaluation width and signedness.
- Diagnostics have stable codes (`E-TYPE`, `W-NARROW`, ...). Tests match on codes, not wording. New codes go in `docs/DIAGNOSTICS.md`.
- Device facts live in `devices/<part>.toml`, **generated** by `tools/devgen` from the Microchip pack and cross-checked against
  `<part>.expect.toml` (hand-written from the data sheet, each line with a page cite). Never edit a generated `.toml` by hand; never
  hard-code a register address, vector or Config value in Rust: read it from the device description.
- Library modules (`lib/*.bas`) are written in Basil. Chip differences are gated with `#if _has(REG)` / `_has(REG.FIELD)`, one branch per
  register layout, never by part number. A module that does not support a chip must `#error`, never fall through to another chip's registers.

## Project rules (from PLAN.md)

- **Efficiency is a top priority**: smaller and faster output, measured against XC8 (`docs/BENCHMARKS.md`, `bench/`, `scripts/bench.py`).
  A one-word or one-cycle saving is worth taking when it is safe. When changing a code generator or optimiser, the output for the existing
  PIC18F27Q10 programs must not get bigger, and a change meant for another chip must leave Q10 output byte-identical (compare `.hex`/`.S`).
- **Every device or silicon fact comes from a Microchip data sheet, errata or pack, with a cite** (document number and page) in the code or docs.
  Do not state or code a hardware fact from memory. Mark unconfirmed items clearly.
- Clean-room: the language is described in our own words from behaviour; do not copy text or tables from third-party compiler manuals in `reference/`
  (those are git-ignored and must not be committed or redistributed). Microchip tools (`pic-as`, `xc8-cc`, MPLAB X, packs) are not bundled.
- Adding a device means more than a `.toml`: a code generator for a new core family, a review of **every** library module for the new part,
  and updates to `docs/MANUAL.md` "Supported device", `docs/LIBRARY.md` "Device support" tables, `README.md`, `pic-config` data, and tests.
- Nothing has been run on real hardware yet; do not claim hardware verification, say "verified in the simulator" at most.
- Keep docs and the user manual in step with behaviour: language change -> `docs/LANGUAGE.md`, `docs/GRAMMAR.md`, `docs/MANUAL.md`; library change -> `docs/LIBRARY.md`.
  Bump the version in `Cargo.toml` as the existing history does.

## Build and test

```
cargo build --release                      # target/release/basil
cargo test --workspace                     # parser, sema, diagnostics, codegen tests (what CI runs)
BASIL_MDB=1 cargo test --test backend      # simulator tests: need MPLAB X mdb + pic-as + device packs; slow, opt-in
BASIL_MDB=1 cargo test q41                 # a family subset
```
Tests: `tests/lexer.rs`, `tests/frontend.rs`, `tests/backend.rs`; programs in `tests/valid/` (must build), `tests/negative/` (must be rejected
with the expected code), `tests/golden/`, `tests/exec*/` (run in the simulator and check results; every program is also built with `-O0` and
must give the same results), `tests/programs/library_all.bas` (includes every module). Python helpers in `scripts/` generate test programs
(`gen-*.py`), model hardware the simulator lacks (`dma_sim.py`, `picsim.py`) and run benchmarks. New language features need a valid test and,
for each new error, a negative test. Tests that need pic-as/mdb skip themselves when it is missing.

## Rust style

- Match the surrounding code: plain `std`, no new dependencies without a strong reason (the root crate depends only on `devdesc`).
- Errors go through `Diagnostics` with a code, file, line and column; don't `panic!`/`unwrap` on user input. Report several errors per run (the parser skips to the next line).
- Backend limitations are reported as `E-BACKEND` / `E-UNSUPPORTED`, not silently miscompiled.
- Keep `-O0` and the optimised build semantically identical; an optimisation that needs a proof must state it in a comment.
- Generated assembly must assemble with `pic-as` without warnings.

## Related

`vscode-extension/` (VS Code support, TypeScript), `zed-extension/` (Zed + `basil-lsp.js`), `tools/pic-config/` (Qt 6 Config-line helper),
`tools/devgen/` (device description generator), `scripts/build-manual-pdf.sh` (manual PDF).
