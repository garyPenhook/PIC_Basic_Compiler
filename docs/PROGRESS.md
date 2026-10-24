# Progress log

## M0 — Foundations (accepted 2026-10-23: Gary delegated approval of practical/logical choices)

Done
- Plan written and approved (`PLAN.md`).
- Decisions recorded (`docs/DECISIONS.md`): D1–D5 accepted; D9–D19 made; D6 (tentative) and D7 decided; D8 open.
- Efficiency made a top-level goal (PLAN §1, §7A); benchmark gate moved to M4.
- Repo skeleton: git repository, Rust crate `basicc`, folders for source, devices, device
  generator, library, tests; vendor manuals moved to git-ignored `reference/`.
- `docs/LANGUAGE.md` draft 0.1, `docs/GRAMMAR.md` draft 0.1, `docs/ABI.md` outline.
- Reference compilers verified on this machine for the 18F27Q10 (first data point in PLAN §7A.4):
  XC8 v4.00 and Swordfish 2.2.5.0 both compile and report sizes.

Review items D11–D13, D16 and the missing-`Device` error were auto-approved as proposed. D6 (tentative) and D7 (IEEE binary32) were decided; D8 stays open until after M9.

## M1 — Fact base (done 2026-10-23)
- `docs/FACTS-18F27Q10.md`: memory map, Access Bank, stack, interrupts, instruction set, clock and
  configuration words, errata — each with a data sheet / errata / device-pack page cite.
- All "TO VERIFY (M1)" markers in `PLAN.md`, `LANGUAGE.md` and `ABI.md` resolved.
- Corrections found while verifying: the flash-write errata workaround is **two** NOPs (not one);
  `XINST = 1` makes the low 96 Access Bank bytes FSR2-indexed, so the default build uses `XINST = 0`;
  the unconfigured default clock is an *external* oscillator, so config words are always emitted
  explicitly; the part has fixed interrupt vectors only.
- Carried forward (listed in FACTS §9): `BRA` ranges (M4), bank 13 / NVM rules (M8), peripheral
  register maps (M6/M8), reset flags (M6).

## M2 — Device description (done 2026-10-23)
- Cargo workspace: `basicc` (compiler), `crates/devdesc` (schema, loader, validator, 7 tests),
  `tools/devgen` (pack → TOML generator and data sheet cross-check, 3 tests).
- `devices/18F27Q10.toml` generated from `PIC18F-Q_DFP 1.31.492`: 438 SFRs with bit fields (current and
  legacy names), 32 joined registers, 12 configuration registers with every setting value, 16 RAM
  banks (bank 13 flagged as system RAM), Access Bank ranges, vectors.
- `devices/18F27Q10.expect.toml`: values entered by hand from the data sheet (Table 1, Fig. 11-1, p.193).
  `devgen check` compares 15 values (memory sizes, vectors, peripheral counts) — all agree.
- Independent confirmation: the pack's `RSTOSC` encodings (`HFINTOSC_64MHZ`=000, `EXTOSC`=111, …)
  match data sheet Table 5-1 (p.53). A deliberately wrong expectation is rejected (checked).
- `scripts/check-devices.sh` regenerates each device and diffs it, then runs the cross-check.
- Pack quirks handled and documented in `docs/DEVICE-FORMAT.md`: non-memory-mapped simulator registers
  skipped; joined registers defined by byte members (pack widths unreliable, e.g. 22-bit `NVMADR`
  declared 16-bit); non-contiguous sectors refused rather than guessed.

## M3 — Front end (done 2026-10-23)
- `basicc` is now a library plus a binary: `src/{diag,pp,lexer,ast,parser,types,project,sema}.rs`.
  `basicc --check prog.bas` runs the whole front end and prints `file:line:col: error[CODE]: message`
  with the source line and a caret.
- Lexer: case-insensitive keywords, `$FF` `%101` `#13` `1.5e3` literals, `'` `//` `(* *)` `{ }` comments
  (nesting), ` _` continuation, raw `Asm` bodies. Preprocessor: `#define/#ifdef/#option/#error…` (D25).
- Parser: the full `GRAMMAR.md` including headers, includes, declarations, structures and unions, routines,
  interrupts, events, `Save`, `Asm`, `Select`, loops and the Positron spellings (D20). Errors are
  recovered per line, so one run reports several problems.
- Semantic analysis: scopes and visibility, modules and qualified names, device registers and bit
  fields resolved through `devdesc`, `Config` settings validated against the pack, constant folding,
  the D16 typing and evaluation-width rules (widths are recorded per node), D11 boolean/integer mixing,
  D12 narrowing, D13 recursion (call-graph cycle check), array/bit bounds, modifiers and promotions,
  `For`/`Select`/label/`Break` rules, parameter and call checking, interrupt priority and `Save` rules,
  global RAM against the device's usable RAM.
- Tests: 89 negative and 32 valid programs plus 6 multi-file projects, each naming the exact diagnostic
  codes expected (`tests/frontend.rs`); lexer unit tests; a damaged-input test (every prefix and every
  line-deleted variant of the corpus, over 1000 runs) that must not panic.
- Language gaps found and settled are in LANGUAGE.md §14A and DECISIONS.md D20–D27. One doc error
  fixed: the `Const T(2) … (1, 2, 3)` example contradicted the element-count rule.
- Not done, by decision: `W-OVF` (D26), clock upper limit (D27), `#if` family (D25).
- Diagnostic codes: `docs/DIAGNOSTICS.md`.

## M4 — Back end, Route A (done 2026-10-23)
- Pipeline: checked tree → `lower.rs` (width-annotated IR, `ir.rs`) → `codegen.rs` (two passes: use
  counts, then final code against the planned layout) → `asm.rs` (branch relaxation, text) →
  pic-as (`driver.rs`). `basicc prog.bas` produces `prog.hex`, `prog.S`, `prog.map`; `--report`
  prints words per routine and every data object; `-S` stops at the assembly.
- Covered: Boolean/Bit/Char and 8/16/32-bit integers, all operators (hardware 8×8 multiply,
  shift-and-add/restoring-division helpers for the rest), comparisons incl. signed, short-circuit
  logic, `If/Select/While/Repeat/For/Break/Continue/Exit/GoTo`, routines with by-value parameters
  and results, device registers and register bits, `Inc/Dec/Clear/High/Low/Toggle/Input/Output`,
  exact `DelayMS/DelayUS`, `Asm`, `Terminate`, configuration words, start-up RAM clearing.
- Front-end hooks added: `Symbol.owner`, `Analysis.decl_syms`, `Span: Hash`.
- Tests: `tests/backend.rs` (assembles the valid corpus with zero pic-as warnings, checks the reset
  vector, checks unsupported features are rejected); `scripts/exec-test.py` runs `tests/exec` in the
  MPLAB X simulator (`BASICC_MDB=1 cargo test --test backend`). `scripts/gen-arith-tests.py`
  generates every operator at all six integer types on run-time operands with independently
  computed expectations (about 3,900 checks, all passing); further programs cover control flow,
  routines, registers and exact delay cycle counts (1,600 / 16,000 / 8,000,000 cycles).
- Benchmarks: `scripts/bench.py`, nine kernel pairs vs XC8 `-Os`/`-O2`, results in
  `docs/BENCHMARKS.md`; targets recalibrated there.
- Self-review (`/code-review high`) found and fixed: a stale carry after skipping a zero low byte in
  multi-byte add/subtract of a constant (wrong results, e.g. `a + 256`); `Reentrant` routines silently
  compiled with a static frame (now `E-BACKEND`); one-character string initialisers and defaults
  stored as 0; variables used only in `Asm` blocks getting no storage; duplicated error reports;
  silent `None` exits in place resolution; hard-coded Access Bank bounds; unused scratch bytes
  reserved by unsigned wide compares; variable delays at a non-integral cycles-per-unit clock now an
  error instead of a silent rounding. Regression cases are in `tests/exec/carry.bas` and
  `tests/backend.rs` (the deferred-feature list is now explicit).
- Found while testing: the simulator's OV flag after `SUBWFB` (D34); `Inc` is a reserved word, so
  it cannot name a program.
- Not done (by decision D35): arrays, strings, structures, floats, ByRef, interrupts, hardware
  verification (no programmer decision yet, D6), `.bas` golden-assembly tests (arrive with the
  optimiser in M5, when assembly text starts to be worth pinning).

## Next: M5 — Language breadth + first optimisations
Arrays, strings, structures, ByRef, 16×16 hardware multiply and multiply-by-constant, `DECFSZ` loops,
frame overlay, zero-init elimination, peephole pass; gates in `docs/BENCHMARKS.md`.

## M5 progress
- Arrays (done): `Dim a(n) As <integer|Char>` for globals and locals; constant indices fold to an
  offset (out of range is `E-BOUNDS`), run-time indices are a 16-bit byte offset in `Place::idx`
  and are addressed through FSR0 (`point_fsr0` in `codegen.rs`; the value of a store is settled
  first). `Inc/Dec/Clear` of an element work. Not yet: array initialisers, `Bit`/`Boolean` arrays,
  whole-array `Clear`/assignment, `ByRef` array parameters, Const arrays. Interrupts (M6) must save
  FSR0 because element access uses it. Test: `tests/exec/arrays.bas`.
- ByRef parameters (done): scalars and arrays of integer/Char; the parameter holds a 16-bit address
  (`Var.by_ref`, `Base::Ptr`), the caller passes `ExK::Addr`, and every access goes through FSR0
  like an indexed element. Not yet: `ByRefConst`, `Bit`/`Boolean` by reference, `Bound()` of an
  array parameter. Fixed: a local named `tmp` clashed with the routine's `__TMP` temporary area.
  Test: `tests/exec/byref.bas`.
- Strings (done): `String(n)` is n+1 RAM bytes, zeroed at start-up, with `Dim s As String = "…"`
  initialisers (globals and locals). Supported: assignment from a literal, string, Char or a `+`
  chain of them (`St::StrSet`, cut off at the declared size and Null-terminated), in-place append
  (`s = s + x`), `=`/`<>` between strings or against a literal (`ExK::StrEq`), `s(i)` as a Char
  (constant or run-time index, also through `ByRef`), `Clear(s)`, and `ByRef`/`ByRefConst` String
  parameters. Literals live in program memory after the code (`__STR<n>`, read with `TBLRD*+`);
  a literal passed to a `ByRefConst` parameter is copied once at start-up into a static RAM buffer
  so the callee has a single (RAM) access path. Runtime helpers `strr/strf/strc/stre/strqr/strqf`
  use FSR0 (destination), FSR1 (RAM source), TBLPTR/TABLAT (flash source) and `__D0` (room left).
  The target may only appear as the first operand of its own `+` chain (`s = t + s` is `E-BACKEND`);
  two `ByRef` parameters that alias at run time are not detected; writing `s(n)` (the Null slot) is the program's responsibility, as there is no run-time bounds check; a literal passed ByRefConst is limited to 255 characters. Not yet: `Len`/`Left`/`Mid`
  (not in the front end either), string-returning functions, arrays of strings, comparing a
  concatenation. Interrupts (M6) must save FSR1, TBLPTR/TABLAT and `__D0` as well as FSR0.
  Test: `tests/exec/strings.bas`.
- Multiply (done): 16/24/32-bit products use the 8×8 hardware multiplier (`MULWF`/`MULLW`, unsigned;
  the low n bytes of the product are the same for signed operands). `__mulN` sums the partial
  products `A[i]*B[j]` with `i+j < n` into `__C`, then copies to `__A` (n=2: 3 multiplies, no loop).
  A constant factor is inlined instead of calling the helper: a power of two is a shift, otherwise one
  `MULLW` per non-zero constant byte (and per live byte of a zero-extended Byte operand). Interrupts
  (M6) must also save PRODH/PRODL and `__C`. Benchmarks: add32 57208 → 4808 cycles, fixmul 33463 →
  7437. A constant factor that is zero (after masking to the width) still evaluates a call in the other
  operand. Tests: `tests/exec/arith_mulconst.bas` (generated; constants at 16/24/32 bits including
  negative and top-bit-set ones, Word×Byte), `tests/exec/mulzero.bas`.
- Structures (done): a field is a byte offset into the variable (`layout` in `lower.rs`, fields in
  declaration order, no padding), so `p.X`, `p.Inner.B`, `pts(i).Hist(j)` and `p.Tag` are ordinary
  `Place` arithmetic; a second run-time index adds to the first. Union members (`En As Val.0`,
  `W As Val.word0`) are placed by following their designator from the field they name. Supported:
  global/local structure variables, nesting, array and `String` fields, arrays of structures,
  `Clear(x)` and `a = b` for whole structures and arrays (1 to 255 bytes; `St::ClearMem`/`St::Copy`,
  unrolled when small, else an FSR0 (destination)/FSR1 (source) loop, source pointed first), and
  `ByRef` structure parameters (pointer plus field offset). Not yet: structure-valued function
  results, structure initialisers, `ByRefConst` structures (the language reserves it for constant
  arrays and strings), assigning a `String` field of an array element picked at run time (the other
  string forms on such fields are fine), whole-array or whole-structure copies over 255 bytes, a bit
  of an element picked at run time. All of the run-time-index forms report `E-BACKEND` (pinned by a
  test in `tests/backend.rs`). Local structures are static and zeroed once at start-up, like every
  local. Test: `tests/exec/structs.bas`.
- Next in M5: `DECFSZ` loops, frame overlay, peephole.

## Backlog: extended instruction set (XINST = 1)
Facts are recorded (FACTS-18F27Q10.md, ABI.md) but nothing is implemented. Scheduled for M9 with
reentrant functions; work items are in PLAN.md §7.2 (assembler table, XINST mode flag in codegen,
FSR2 software-stack frames, `CALLW` function pointers, simulator support, tests/benchmarks).
