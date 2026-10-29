# Progress log

## M0 — Foundations (accepted 2026-10-23: Gary delegated approval of practical/logical choices)

Done
- Plan written and approved (`PLAN.md`).
- Decisions recorded (`docs/DECISIONS.md`): D1–D5 accepted; D9–D19 made; D6 (tentative) and D7 decided; D8 open.
- Efficiency made a top-level goal (PLAN §1, §7A); benchmark gate moved to M4.
- Repo skeleton: git repository, Rust crate `basil`, folders for source, devices, device
  generator, library, tests; vendor manuals moved to git-ignored `reference/`.
- `docs/LANGUAGE.md` draft 0.1, `docs/GRAMMAR.md` draft 0.1, `docs/ABI.md` outline.
- Reference compilers verified on this machine for the 18F27Q10 (first data point in PLAN §7A.4):
  XC8 v4.00 and another BASIC compiler both compile and report sizes.

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
- Cargo workspace: `basil` (compiler), `crates/devdesc` (schema, loader, validator, 7 tests),
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
- `basil` is now a library plus a binary: `src/{diag,pp,lexer,ast,parser,types,project,sema}.rs`.
  `basil --check prog.bas` runs the whole front end and prints `file:line:col: error[CODE]: message`
  with the source line and a caret.
- Lexer: case-insensitive keywords, `$FF` `0xFF` `%101` `0b101` `#13` `1.5e3` literals, `'` `//` `(* *)` `{ }` comments
  (nesting), ` _` continuation, raw `Asm` bodies. Preprocessor: `#define/#ifdef/#option/#error…` (D25).
- Parser: the full `GRAMMAR.md` including headers, includes, declarations, structures and unions, routines,
  interrupts, events, `Save`, `Asm`, `Select`, loops and the alternative spellings (D20). Errors are
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
  pic-as (`driver.rs`). `basil prog.bas` produces `prog.hex`, `prog.S`, `prog.map`; `--report`
  prints words per routine and every data object; `-S` stops at the assembly.
- Covered: Boolean/Bit/Char and 8/16/32-bit integers, all operators (hardware 8×8 multiply,
  shift-and-add/restoring-division helpers for the rest), comparisons incl. signed, short-circuit
  logic, `If/Select/While/Repeat/For/Break/Continue/Exit/GoTo`, routines with by-value parameters
  and results, device registers and register bits, `Inc/Dec/Clear/High/Low/Toggle/Input/Output`,
  exact `DelayMS/DelayUS`, `Asm`, `Terminate`, configuration words, start-up RAM clearing.
- Front-end hooks added: `Symbol.owner`, `Analysis.decl_syms`, `Span: Hash`.
- Tests: `tests/backend.rs` (assembles the valid corpus with zero pic-as warnings, checks the reset
  vector, checks unsupported features are rejected); `scripts/exec-test.py` runs `tests/exec` in the
  MPLAB X simulator (`BASIL_MDB=1 cargo test --test backend`). `scripts/gen-arith-tests.py`
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
- Counted loops (done): a `For` with constant bounds and step that runs at most 255 times counts a
  hidden Byte down (`St::Count`, `lower.rs` `for_stmt`). If the body never mentions the variable
  (and has no `Break`/`Return`/`Goto`/label/raw `Asm`; with a global variable, no calls either) the
  exit test is a single `DECFSZ` and the variable is set to its last value after the loop. If the
  body only reads the variable (`blocks_count_loop` in `ir.rs`: no write, no address taken, no call
  when the variable is global, no raw `Asm`) the variable is still stepped, with
  `DCFSNZ`/`BRA end`/add/`BRA top`, so `Break` and `Return` see the right value and the variable
  never passes its last value (D33). Other loops keep the compare form. Interrupts (M6) need nothing
  extra: the counter is an ordinary hidden static. Not yet: variable bounds (would need a computed
  trip count), trip counts over 255. Test: `tests/exec/countloop.bas`. Benchmarks: fixmul 7437 →
  5294 cycles and 128 → 102 bytes, add32 4808 → 4710; kernels whose loops are not constant-bounded
  gain one hidden byte of RAM and two bytes of code.
- Frame overlay (done): `independent()` in `codegen.rs` derives from the call graph which routines
  can never be live together; `plan_layout` places each object first-fit (hottest first, Access Bank
  first) and lets it sit on top of objects of independent routines (`Obj::owner`). Locals and `Result`
  are therefore cleared on entry (`entry_clears` in `lower.rs`, skipped when `written_first` proves an
  assignment comes first; D37) and start-up clears globals only. Not overlaid: globals, scratch, the
  main program's own objects, `ByRefConst` string buffers. Interrupt handlers (M6) must be `owner =
  None`. Tests: `tests/exec/overlay.bas` (siblings, nested chain, stale-storage cases, nested
  calls in expressions) and `frames_overlay_only_when_never_live_together` in `tests/backend.rs`.
- Read-modify-write (done): `x = x op <expr>` and `x = <expr> op x` (commutative ops) work the operand
  out first and fold it into `x` (`addwf x,f` / `addwf A,w` chains) when the operand contains no
  call. Test: `tests/exec/rmw.bas`.
- Peephole (done, `src/peephole.rs`): bit test into a Boolean then compared (`movlw 0 / btfsc R,b / movlw 1 / xorlw K / bz L`)
  becomes `btfsc`/`btfss R,b` + `bra L` when `WREG` and the flags are dead on both paths (`pass_bit_branch`); branch to the next instruction, `xorlw 0` after an instruction
  that set Z/N, redundant `WREG` loads, copy forwarding from `movff s, __X`, and dead stores to
  `WREG`/`__A`..`__D` (dead at a statement end, `Item::Fence`). Local to straight runs; status flags
  are tracked, so a flag-setting instruction is only deleted when nothing can read the flags; only
  compiler-placed RAM (and PRODL/PRODH) is ever reasoned about. Cycle-exact delay code is fenced
  off (`Item::Keep`). `-O0` disables the pass and the RMW forms (D38); the simulator suite runs every
  program both ways. Interrupts (M6): a handler can change a variable between a store and a reload,
  so `W::Mem` reasoning must be revisited for variables a handler writes. Not done: bit-store
  patterns, scratch-to-scratch copy forwarding, jump threading.
- Peephole and table walks (0.1.15): `rcall f` before `return` becomes `bra f`; code after a `return`,
  `retfie` or `bra` with no label is dropped; unreferenced `_L` labels are dropped (they only ended
  straight runs); `movlb` leaves a polling loop that never changes the bank; `movf s,w / movwf x /
  movf x,f` loses the repeated test. A 16-bit `Inc` is `infsnz lo,f / incf hi,f`. In `opt.rs`
  (`flash_walk`, run last) a constant-true loop that reads a literal table at `i + k` and steps `i`
  by one reads it with `TBLRD*+` instead (`Base::FlashNext`, `St::FlashSeek`): the pointer is set
  once before the loop and `i` goes away, unless the loop calls something that uses TBLPTR.
  `written_first` also sees a write that opens a constant-true loop, so `c` in `SerialWrite` is no
  longer cleared on entry. Test: `tests/exec/tablewalk.bas`; `isr_single.bas` now waits on `T0CON0`
  because `While hits < 300` could read the Word half-updated.
- Calls and tables (0.1.16): a table walk also works when the start is a run-time Word parameter
  (several literals sharing one table: `FlashSeek` takes an expression). A routine called from exactly
  one place, and by no jump or address, is moved into the call (`inline_single_calls` in `codegen.rs`;
  its `return`s become jumps to the end). A routine with one Byte parameter that only plain calls reach
  takes the argument in `WREG` (`Gen::warg`): it starts with `movwf P`, and `pass_warg` deletes that
  store and the one `movf P,w` when `WREG` provably survives to the read. More peephole: `bcc L1 / bra
  L2 / L1:` becomes `b!cc L2`, and a `movlb` to the bank already selected goes. Fixed: `src_to_reg`
  sized a scratch register for one byte while writing several, so a 16-bit compare against a constant
  overwrote the next variable. Test: `tests/exec/callopt.bas`.
- Write-only copies (0.1.17): `pass_wreg` keeps what `WREG` holds across a fence and past a conditional
  branch, and a callee is not given the caller's flags, so `movwf c / bz / movf c,w` loses the reload;
  `pass_write_only` then deletes `movwf v` when nothing in the program mentions `v` otherwise. `SerialWrite`
  is two words smaller.
- Review fixes (done): passes never touch the instruction after a skip and never use it as a copy
  source; `Result` is cleared on entry unless a straight-line assignment precedes any `Return`;
  objects over 256 bytes start on a bank boundary. Test: `tests/exec/review.bas`. Known cost: the
  first-fit layout (`Region::find`) is slower than the old bump pointer; not measured on large programs.
- Remaining for the M5 exit: golden-assembly tests, zero-init elimination of globals, single-call
  inlining.

## M6 progress
- Interrupts (done, `ir.rs` `St::Int`/`St::Save`, `lower.rs` `lower_interrupt`, `codegen.rs`
  `gen_isr`/`save_block`/`int_control`): D40–D45. A handler is a routine nobody calls with its own
  never-overlaid frame; the vectors, `IPEN`, `Enable`/`Disable`, shadow or software context save
  and `Save … Restore` are generated as described in ABI.md §2, §5. The first pass records which
  compiler registers each routine touches (`Facts`), later passes use that to size each handler's
  save area; `generate` repeats until the save areas settle like the temporaries do.
  Tests: `tests/exec/isr_single.bas` (one handler, free-running Timer0 whose period the handler
  varies, so interrupts land all over the main program; a call inside `Save`) and
  `tests/exec/isr_dual.bas` (two priorities, the high handler kicked from inside the low one after
  a varying delay and re-arming itself); both run optimised and `-O0`. `tests/backend.rs` pins the
  vector addresses, `IPEN`, the single `RETFIE, FAST`, and that a handler's frame is never shared
  with a sibling routine's.
- Checked by breaking the compiler on purpose: dropping the per-handler register saves makes
  `isr_single` fail, so that test does detect lost context. Forcing the low handler to use the
  shadow registers while both priorities exist does **not** make `isr_dual` fail: the MDB
  simulator does not reproduce the hardware overwrite of the shadow copy, so that rule rests on the
  data sheet (`p.112`) and awaits hardware.
- Stack depth (done, `stack_depth` in `codegen.rs`, `E-STACK`): the deepest call chain of the main
  program through the final item stream (routines, shared helpers, `call`/`rcall` in raw `Asm`),
  plus one level for each interrupt priority and that handler's own deepest chain, must not exceed
  31. An unknown raw-`Asm` call counts as one level. Test: `hardware_stack_depth_is_checked`.
- Not yet: the `gpio`, `delay`, `timer`, `serial` library; hardware runs
  (D6 still open). Large frames named in `Save` are copied byte by byte, which is long for big arrays.
- Library (done, `lib/`, `docs/LIBRARY.md`): `gpio`, `delay`, `timer` (Timer0/1/2), `serial` (EUSART1).
  Register values were taken from the data sheet through the pic-docs server. Tests:
  `tests/exec/lib_serial.bas`, `lib_timer.bas`, `lib_timer12.bas`, `lib_timer_hw.bas` (simulator, optimised and `-O0`) and
  `tests/programs/library_all.bas`. Fixed on the way: a module-qualified call used as a statement
  (`Serial.SerialInit(...)`) was rejected by the back end (`callee_of` in `lower.rs`). The MDB
  simulator models TXIF/TRMT timing but gives no way to see the bytes sent, so serial output is
  not checked, only its set-up and handshake. Not yet: hardware runs (D6). EUSART2: see below.
- Known limits: a `Save` block inside a routine that both main and a handler call shares one static
  save area; each `Exit`/`Break`/`Continue` inside `Save` repeats the restore code instead of
  jumping to one copy; `Save` bodies are scanned for callees by a separate IR walker
  (`stmt_calls`) that must follow new statement kinds. The register facts are recomputed from the
  final pass and the layout repeats until they agree.

## Backlog: extended instruction set (XINST = 1)
Facts are recorded (FACTS-18F27Q10.md, ABI.md) but nothing is implemented. Scheduled for M9 with
reentrant functions; work items are in PLAN.md §7.2 (assembler table, XINST mode flag in codegen,
FSR2 software-stack frames, `CALLW` function pointers, simulator support, tests/benchmarks).

## C interop: calling C routines from Basic (done 2026-10-28, 0.1.47)
- `CFile "x.c"` (header) and `Extern Sub|Function name(...)` (declaration, no body). Facts: XC8 user guide §5.8.5-5.8.6 (W for a first
  one-byte parameter, `?_func` for the rest, result in W or `?_func`). Design in `docs/ABI.md` §7.
- Parser/sema: `Routine.ext`, `HeaderKind::CFile`, `E-EXTERN` for parameter/result types that are not integer, Char or Boolean, `ByRef`,
  defaults, `Reentrant`. Lowering: the body is a generated `Asm` thunk, `Program.externs` / `Program.cfiles`. Codegen: relocatable `basilcode`
  psect and `_basil_entry` when a C routine is called; `ram_ranges` for `-mreserve`. Driver: `run_xc8_cc`, `c_stub`; `main.rs` refuses
  `Interrupt` with `Extern` and names the assembly `<name>_basil.S` (xc8-cc names the C object after the hex file).
- Tests: `tests/exec_c/c_basic` in the simulator (C globals with initial values, an array, 4-byte results; `scripts/exec-test.py` reads the entry
  address from the map), `tests/backend.rs::c_routines_link`, `tests/negative/extern_bad_param`.
- Not done: interrupt handlers with C, C calling Basic, `ByRef`/`Float`/structure arguments, hardware runs, `-g` with C.

## DMA library module, first step (done 2026-10-28, 0.1.39)
Decision (2026-10-27): DMA is a library module (`Include "dma"`), not language commands; `#if not _has(DMAnCON0)` gives `#error`.
- `lib/dma.bas`: `DmaCopy(channel, src, dst, count)` (RAM/SFR to RAM/SFR, increment both, 1..4095 bytes, returns at once), `DmaDone`, `DmaStop`,
  constants `DmaChannels`, `DmaMaxBytes`. Facts from DS40002214G: 16.3.4.1.1 (EN then DGO), 16.3.3 (DGO clears when the smaller counter
  reloads), 16.8 (set-up order), 16.12 (`DMASELECT` = channel - 1), 16.13.3 (`DMAnCON1` = 42h), 7.1.1 (`PRLOCKED` sequence). No DMA erratum
  beyond the vector numbers of Table 11-2 (DS80000901H 2.1). `AddressOf` values feed the address registers directly.
- Test: `tests/exec_q41/lib_dma.bas` checks the registers left behind. The MPLAB X simulator does not model the engine (`DGO` stays set, no byte
  moves) nor the `DMASELECT` overlay, so data movement and a second channel are untested. Not run on a real part.
- Not done (see 0.1.40 for SIRQ): flash/EEPROM sources (`SMR`), non-incrementing
  modes, completion interrupts, channel priorities (`DMAxPR`), the 16F17126/46 (its data sheet has not been read for DMA).

## DMA library module, hardware triggers (done 2026-10-28, 0.1.40)
- `lib/dma.bas`: `DmaOnTrigger(channel, trigger, src, dst, count, options)` arms a channel for SIRQ-started messages (`DmaFixedSrc`, `DmaFixedDst`, `DmaOnce`),
  with `DmaTrig...` constants for common sources (Table 16-6). A fixed side has size 1; `DmaOnce` sets SSTP (or DSTP when only the destination is the buffer)
  so SIRQEN clears after `count` bytes [16.4.2]. `DmaDone` now also waits for SIRQEN to clear. Facts from DS40002214G 16.3.3, 16.3.4.1.2, 16.4, 16.5, 16.8,
  16.13.2, 16.13.3, 16.13.13; the DS80000901H vector-number erratum agrees with Table 16-6.
- Test: `tests/exec_q41/lib_dma_trig.bas` (register contents for a feed, a receive with `DmaOnce`, a feed with `DmaOnce`, refusals). Simulator does not model the engine; not run on a real part.
- Not done: abort triggers (`DMAnAIRQ`), flash/EEPROM sources (`SMR`), completion interrupts, channel priorities (`DMAxPR`), the 16F17126/46.

## DMA library module, abort triggers (done 2026-10-28, 0.1.41)
- `lib/dma.bas`: `DmaAbortOn(channel, trigger)` writes `DMAnAIRQ` then sets `AIRQEN` (a single `bsf`, so `DGO`/`SIRQEN` changed by hardware are not rewritten) and refuses a channel with `EN` clear
  (clearing `EN` resets `DMAnAIRQ`, 16.9); `DmaAborted(channel)` reads and clears `DMAxAIF` (`PIR2.7`, `PIR6.7`, `PIR9.7`, `PIR10.7`, checked with the data sheet).
  Facts: DS40002214G 16.3.4.2.2, 16.8.6, 16.8.7, 16.13.14. An abort clears `DGO`, `SIRQEN` and `AIRQEN`, so `DmaDone` reports 1; `DmaAborted` tells it from a normal end.
- Test: `tests/exec_q41/lib_dma_abort.bas` (registers and the flag). Not run on a real part; the simulator does not model the engine.
- Not done: flash/EEPROM sources (`SMR`), completion interrupts, channel priorities (`DMAxPR`), resuming after an abort, the 16F17126/46.

## DMA library module, flash source (done 2026-10-28, 0.1.42)
- `lib/dma.bas`: `DmaCopyFlash(channel, src, dst, count)`, `src` a `LongWord` flash byte address; `DMAnCON1` = 4Ah (SMR = 01, both pointers increment), `DMAnSSAU` takes bits 23:16.
  Facts: DS40002214G 16.13.3 (SMR), 16.13.5 (SSA is 22 bits), 16.11 (the flash example uses SMR = 01 with `DMAnCON1` = 0Bh), Table 16-1.
  It is a separate function, not a shared helper: sharing the body with `DmaCopy` cost 24 more bytes for a program using only `DmaCopy`.
- Test: `tests/exec_q41/lib_dma_flash.bas` (registers, 22-bit address, refusal on a busy channel). Not run on a real part.
- Decision (2026-10-28): the data EEPROM source is left out because the data sheet does not give the `DMAnSSA` value for it (SMR = 1x); needs Microchip's answer or a hardware test.
- Not done: EEPROM source, completion interrupts, channel priorities (`DMAxPR`), resuming after an abort, the 16F17126/46.

## DMA library module, EEPROM source (done 2026-10-28, 0.1.43)
- Research: DS40002214G/242F give `SMR = 1x` for the EEPROM (16.13.3) and say Table 16-1 allows EEPROM to GPR/SFR, but not the `DMAnSSA` value. Microchip's technical brief TB3164
  (Direct Memory Access on 8-bit PIC Microcontrollers, section 7.1 Example-1) copies 512 EEPROM bytes to RAM with `DMA1SSA = 0x000000`, `DMA1CON1 = 0x7A` (`SMR = 11`): an offset from the
  start of the EEPROM. It is a family-level document, not the Q41 data sheet. No Q41-specific statement was found (searched the two Q41 data sheets and Microchip's online DMA pages).
- `lib/dma.bas`: `DmaCopyEeprom(channel, src, dst, count)`: `DMAnCON1` = 5Ah (`SMR = 11`), `SSAU` = 0, refuses a copy past `_EepromBytes`. Separate function (the shared-helper version cost 24 bytes for `DmaCopy` users).
- Test: `tests/exec_q41/lib_dma_eeprom.bas` (registers and bounds). Not run on a real part; first hardware check: bytes from `EepromWrite` appear in RAM. Fallback if wrong: `380000h`, the NVM address.
- Not done: completion interrupts, channel priorities (`DMAxPR`), resuming after an abort, the 16F17126/46.

## DMA model for the simulator tests (done 2026-10-28, 0.1.44)
- MDB (MPLAB X 6.35, the newest installed) has no DMA model for any Q41 part (`docs/FeatureSupport/SimPeripheralSupport.csv`) and keeps one flat register set where the part overlays four channels by `DMASELECT`.
  It cannot be patched, so `scripts/dma_sim.py` adds both: a four-channel engine written from DS40002214G chapter 16 (Tables 16-3 to 16-5, message end on the smaller counter, SSTP/DSTP, EN hard stop, DGO soft stop,
  AIRQ abort, the four flags, `PRLOCKED`, SFR/GPR, flash and EEPROM sources) and a replay driver.
- Driver: an interactive MDB session does not resume after a watchpoint stop (checked: the first stop works, later `run`/`continue` do nothing), so it works with scripts. A script stops on every write to `DMASELECT`,
  `DMAnCON0` and the test's mailbox byte and logs the registers, memory and flags; the engine replays the log and the script is built again with `write` commands that put the moved bytes, counters, `DMAnCON0` and flags in
  MDB after the stop they answer; passes repeat until the commands stop changing (about 3-6, 1-3 minutes a test).
- Tests opt in with a `' dma:` header line (`mailbox=SYM` for peripheral requests and aborts, `slow`, `sfr=NAME:1,2,3`, `ee=OFFSET:1,2`; `' dma-writes:` checks bytes written to an SFR): `lib_dma_move`, `lib_dma_trigmove`, `lib_dma_srcmove`,
  `lib_dma_abortmove` in `tests/exec_q41/`. The model itself has 15 unit tests: `python3 scripts/test_dma_sim.py` (also run by `cargo test`).
- Not modelled: bus timing (a message completes at once, or on `step` commands in `slow` mode), the one-cycle stop latency, XIP/`DMAnBUF` in flight, the trigger sources (the test says when a request comes), priorities.
  The model is the data sheet as read here, not silicon: the EEPROM source address is taken as an offset (TB3164), as the library assumes. Nothing here is a hardware result.
- Not done: completion interrupts in the model (the flags are set, no vector is taken), the 16F17126/46.

## Simulator tests: per-part expectations (done 2026-10-28, 0.1.45)
- `q41_programs_in_simulator` failed on `addressof`, `addressof_byref`, `pp_if` and `regs`: not compiler bugs, the expectations were Q10 values. The Q41 RAM starts at 0x500 and PORTB is 0x04CF (DS40002214G);
  `pp_if` tests `_device = 18F27Q10`; `regs` drives `PORTB.0`/`LATB.0`, which the 18F16Q41 does not have (it implements `LATB7..4`).
- `exec-test.py` reads `' expect-<DEVICE>:` lines (added to the `' expect:` ones for that part) and `' devices:` (the program is skipped on other parts). Used by the four programs above.

## exec-test.py review fixes (done 2026-10-28, 0.1.46)
- From the review of 0.1.45: skipped programs are counted and printed, and a run in which every program is skipped fails (a typo in a `' devices:` line no longer passes with no coverage);
  `' devices:` takes spaces or commas; the device name in the `expect-` pattern is escaped; the file is read once per program; the docstring says an `expect-<DEVICE>` name overrides the same name in `expect:`
  and the others are kept; `__pycache__/` is in `.gitignore`.
- Not done: Q41 variants of `regs` (RB4) and `pp_if`, so these two have no simulator coverage on the Q41.

## Library and devices built into the compiler (done 2026-10-27, 0.1.38)
- `build.rs` embeds `lib/*.bas` and `devices/<part>.toml` (not the `*.expect.toml` files). `src/embedded.rs` writes them once to
  `$XDG_CACHE_HOME/basil/<content hash>/{lib,devices}` (else `~/.cache`, else the temp folder) and `main.rs` searches that copy last, so a
  copied `basil` binary works from any folder. A `lib/` or `devices/` next to the program, `-L` and `--devices` still win.
- Removed the `CARGO_MANIFEST_DIR` fallback (it pointed at the build machine's checkout).
- The cache folder is named by a hash of the contents, so a rebuilt compiler never reads stale modules; a `complete` marker is written
  last and each file is renamed into place, so two `basil` runs starting together are safe.
- Not done: `BASIL_LIB` / `BASIL_DEVICES` variables, a per-user folder, `basil init`, `basil lib list|extract`, a project `basil.toml`.

## M7 — Route B evaluation (done 2026-10-24: decision D46, drop for now)
- The LLVM tree's three PIC symlinks (`llvm/lib/Target/PIC`, `tools/pic-llc`, `tools/pic-mc` under
  `~/.local/src/llvm-pic`) pointed at the deleted `~/Documents/PIC_Compiler`. They now point at
  `~/Documents/PIC_Compiler_recovered`. The original binaries are copied to
  `~/.local/build/llvm-pic-orig-bin/`.
- `ninja pic-llc pic-mc` fails at configure: `Target PIC is not in the set of libraries`. Causes found:
  `lib/Target/PIC/CMakeLists.txt` has only the TableGen rules and `TargetInfo` (no `add_llvm_target`,
  no source list, no `MCTargetDesc`, `GISel`, `AsmParser`, `Disassembler` subdirectories);
  `PICFrameLowering.cpp` does not exist (only the header); `tools/pic-llc/pic-llc.cpp` is 33 lines.
  So the recovered tests could not be run.
- Only data point: the prebuilt (2026-10-14) `pic-llc -march=pic18 -O2` on `pic-test/examples/sum.ll`
  gives 53 lines of assembly with visible waste (an `i8` index sign-extended to 16 bits, byte pairs
  copied through `WREG` several times). No quantitative comparison with Route A was made: `basil` has
  no LLVM IR output, so the same program cannot be fed to both.
- Decision D46: drop Route B for now. Route A stays the single back end. Not changed: the symlinks
  stay on the recovered tree, so the LLVM build directory cannot reconfigure until the backend is
  rebuilt or the links are removed.

## M6 — Timer1 gate/external clock, Timer2 hardware-limit modes (done 2026-10-24)
- `lib/timer.bas` gains `Timer1StartSource/StartCounter/StartGated/StartPulse`, `Timer1PulseDone`,
  `Timer1GateState` (T1CLK Table 20-2, T1GATE Table 20-4, T1GCON 20.14.2) and `Timer2StartLimit`,
  `Timer2Running` (T2HLT Table 21-3, T2RST Table 21-2), with `T1Clk*`, `T1Gate*`, `T2Mode*`,
  `T2Rst*` constants. Documented in `docs/LIBRARY.md`.
- The library does not set up pins: the caller makes T1CKI (RC0), T1G (RB5) and T2IN (RC3) digital
  inputs (ANSELx resets to 1 [p.247]). External Timer1 clocks are synchronised (SYNC = 0); asynchronous
  mode (Sleep) is not offered.
- The data sheet does not say that TMR2IF is set when a one-shot clears ON, and the MDB simulator does
  not set it: a one-shot end is detected with `Timer2Running`, and the flag is not tested.
- Test: `tests/exec/lib_timer_hw.bas` (simulator, optimised and `-O0`) checks the register values
  written and that a one-shot Timer2 clears ON after its period. The simulator has no pin stimulus, so
  counting on real external edges and gate pulses is not exercised; not checked on hardware (D6).
- `clock` is a reserved word, so library parameters use `clk`.

## M6 — Event handlers (done 2026-10-24)
- `Event` handlers and event variables (`lower.rs` `event_func`, `event_call`, `finish_event_dispatch`):
  a variable is one byte (the type's size was 3 in `types.rs`; now 1) holding the 1-based number of the
  handler assigned to it; a call goes to one generated dispatcher routine (`__EVDISP`, an `If` chain of
  ordinary calls built once all referenced handlers are known), so call graph, overlay and stack-depth
  analysis need no special cases. Only handlers named in an assignment are compiled.
- Deviation from the LANGUAGE.md §8 wording ("own non-overlaid frame"): handler frames overlay by the
  normal call-graph rule, and a handler had to call an event inside `Save` (`E-ISR-CALL`), because the
  dispatcher's parameter byte is shared (superseded in 0.1.23: see "Event extensions").
- Tests: `tests/exec/events.bas` (simulator, optimised and `-O0`: reassignment, unassigned call, two
  variables, locals zeroed per call, handler calling a routine), `tests/negative/event_in_isr.bas`,
  `tests/valid/event_in_isr_save.bas`.

## M6 — EUSART2 (done 2026-10-24)
- `lib/serial2.bas` (module `Serial2`): `serial` on EUSART2, TX on RB6 (`RB6PPS = 0x0B`), RX on RB7
  (`RX2PPS = 0x0F`, its reset default), flags `PIR3` bits 6/7. Values from DS40002043F Tables 18-1, 18-2, 15.13.5.
- Test `tests/exec/lib_serial2.bas` (optimised and `-O0`) checks the register values only: the MDB simulator never
  sets TX2IF (PIR3 reads 0x10, only TX1IF), so a send would hang there. Transmit/receive on EUSART2 is unverified
  until hardware (D6). `tests/programs/library_all.bas` includes the module.

## M8 — adc (done 2026-10-24)
- `lib/adc.bas` (module `Adc`): see `docs/LIBRARY.md`. Register values from DS40002043F §33 (ADCON0, ADREF, ADCLK,
  ADACQ, Table 33-1, AD20 TAD 1..9 us) and §30 (FVRCON); errata 1.4.1 and 1.4.4 applied, 1.4.2/1.4.3 not relevant.
- Test `tests/exec/lib_adc.bas` (optimised and `-O0`): register values after init and after `AdcRefFvr`, pin
  set-up, ADPCH, and that conversions complete in the simulator. The input is not driven, so result values and the
  dropped first conversion (errata 1.4.4) are not checked; nothing runs on hardware (D6).
- `trisa` clashes with the register `TRISA`: names are case-insensitive, so a variable cannot share a register's name.

## M8 — eeprom (done 2026-10-24)
- `lib/eeprom.bas` (module `Eeprom`): see `docs/LIBRARY.md`. Read and write sequences from DS40002043F §12.3
  (Examples 12-6, 12-7), NVMCON0/1 from §12.5; DFM array at NVMADRU = 0x31 (`docs/FACTS-18F27Q10.md`). Errata 1.6.1
  (NVMERR sticky, no work-around) means success is judged by read-back. 1.6.2 is program flash only.
- Test `tests/exec/lib_eeprom.bas` (optimised and `-O0`): the MDB simulator does not model DFM reads (a read leaves
  NVMDATL unchanged), so stored values are not checked; it checks the address registers, NVMEN cleared, GIE restored
  (and left off when it was off), invalid addresses and that a write completes. Nothing runs on hardware (D6).

## M8 — pwm (done 2026-10-24)
- `lib/pwm.bas` (module `Pwm`): see `docs/LIBRARY.md`. CCP1/CCP2 in PWM mode (DS40002043F §22.4, CCPxCON, CCPRx with
  FMT = 1) and PWM3/PWM4 (§23, PWMxCON, PWMxDC), all on Timer2 (CCPTMRS = 01); output routing RxyPPS = 5..8 and the
  allowed ports from Table 18-2 (28-pin columns). Start order follows §22.4.2 / §23.9. The errata sheet (DS80000832G)
  has no CCP/PWM entry.
- Test `tests/exec/lib_pwm.bas` (optimised and `-O0`): register values, pin routing, refusals, stop and restart of
  Timer2, and that the first-overflow wait completes in the simulator. The simulator does not show the pin waveform, so
  frequency and duty on the pin are not measured; nothing runs on hardware (D6).
- Not specified by the data sheet and therefore documented, not relied on: whether a CCP duty of exactly `PwmSteps`
  holds the pin high (PWM3/PWM4 text says "greater than or equal"); with `T2PR` = 255 100 % is unreachable.


## M8 — i2c (done 2026-10-25)
- `lib/i2c.bas` (module `I2c`): host mode on MSSP1, see `docs/LIBRARY.md`. Register values from DS40002043F §28.6, §28.7
  (Equation 28-1, SSPxADD 0..2 invalid), §28.9 (SSPM = 1000, SMP, SSPxCON2 sequence bits), PPS Tables 18-1 (MSSP1 inputs on
  ports B and C) and 18-2 (output codes 0x0F SCL, 0x10 SDA). The errata sheet (DS80000832G) has no MSSP entry.
- Every wait is bounded and the module polls SSP1IF/BCL1IF itself (no interrupt use), so a missing pull-up gives status 1.
- Test `tests/exec/lib_i2c.bas` (optimised and `-O0`): divider, SMP, PPS, TRIS, refusals, `I2cOff`, and that all routines return
  with no bus. The simulator has no pin model, so no transfer is exercised; nothing runs on hardware (D6).
- Bit aliases cannot be used as conditions (`E-COND`): compare with `= 1`.

## M8 — spi (done 2026-10-25)
- `lib/spi.bas` (module `Spi`): host mode on MSSP1, see `docs/LIBRARY.md`. Values from DS40002043F §28.2 (pin/TRIS rules, BF/WCOL),
  §28.9.1-28.9.2 (SMP, CKE, CKP, SSPM = 0000 / 1010, SSPxADD = 0 unsupported), PPS Tables 18-1/18-2 (SCK 0x0F, SDO 0x10, SDI via SSP1DATPPS).
  The errata sheet has no MSSP entry. Mode numbers follow from the CKP (idle level) and CKE (transmit on active-to-idle) definitions.
- Test `tests/exec/lib_spi.bas` (optimised and `-O0`): divider, SSPM/CKP/CKE per mode, PPS, TRIS, receive-only, refusals, `SpiOff`, and bounded
  return of every routine. The simulator has no pin model, so no waveform or data exchange is checked; nothing runs on hardware (D6).

## M8 — system (done 2026-10-25)
- `lib/system.bas` (module `System`): reset cause from PCON0 (DS40002043F §9.11, §9.12, §9.14.2, Table 9-3) and clock check from
  OSCCON2 / OSCFRQ (§5.6.2, §5.6.5, Table 5-1). No run-time clock change on purpose: every cycle-counted routine and library baud/period
  calculation uses the compile-time `Clock` (a run-time switch would need that to become a variable; not planned).
- Test `tests/exec/lib_system.bas` (optimised and `-O0`): every PCON0 pattern -> cause, the clear value, the clock table through
  `SysClockFrom`. The simulator leaves OSCCON1/2, OSCFRQ and OSCSTAT at 0 (Table 5-1 reset values are not modelled) and OSCCON2 is read-only,
  so `SysClockHz` is only checked to agree with `SysClockFrom` of the live registers; its real values need hardware (D6).
- M8 library breadth: everything on the M8 list is done (`lcd` and `oled` below).

## Arrays completed (2026-10-25)
- Array initialisers `Dim a(n) As T = (…)` (parser `dim_init`, sema `array_init`, lowering `array_init`), `E-DIM-ARRAY` for a wrong count.
- `Const` arrays in the back end: `Base::Flash`, `FlashObj` tables emitted after the string literals, `point_tblptr` in `codegen.rs`; constant indices fold; whole-array assignment to RAM is a flash-to-RAM `St::Copy`; `ByRefConst` array parameters take a RAM copy made at start-up.
- `Bit`/`Boolean` arrays: packed eight to a byte when only indexed, one byte per element when used as a whole (`ByRef`, copy, initialiser, structure field) (D47). Test: `tests/exec/bit_packed.bas`.
- `Bound(a)` of an array parameter (D49); a bit of an element picked at run time, of a structure field in such an element and of a `ByRef` parameter (`bit_read`/`bit_write` in `lower.rs`, read-modify-write of the byte; the index may not contain a call).
- Copies and clears of whole arrays and structures over 255 bytes (chunked loops in `copy_mem`/`clear_mem`).
- Tests: `tests/exec/arrays_full.bas` (optimised and `-O0`), negative tests `array_init_*`, `const_array_write`. The old `W-BITARR` test file became `tests/valid/bit_array.bas`.
- Still not done: arrays of strings, multi-dimensional arrays, array-returning functions, `Const` arrays of floats, a call inside the index of a bit, `Inc`/`Dec` of such a bit, a bit-array element passed `ByRef`.

## M8 — lcd and oled (done 2026-10-25)
- `lib/lcd.bas` (module `Lcd`): HD44780U, 4-bit, from `~/Projects/HD44780.pdf` (instruction table 6, Figure 24 initialisation, DDRAM map, bus timing). No busy-flag read (fixed waits).
- `lib/oled.bas` (module `Oled`): SSD1309 128 x 64 over I2C (8.1.5) or 4-wire SPI (8.1.3), from `~/Projects/Solomon_SSD1309_v1.1.pdf` (command tables 9-1..9-5, power-on 8.8). Relies on Reset values (8.4) for geometry/COM pins; text is a 5 x 7 font from the public domain X11 `5x7` font (not from the data sheet).
- The compiler has no `Const` arrays yet, so the font lives in an `Asm` block (`db` data read with `TBLRD`). That exposed a bug in `asm.rs::words_of`: a raw `db` line counted as one word, so the call/branch range selection was wrong for programs over 1K words. It now counts operands.
- Tests `tests/exec/lib_lcd.bas`, `lib_oled.bas` (optimised and `-O0`): refusals, pin set-up, final pin levels, font bytes read from flash. Nothing runs on a panel (D6); there is no pin model in the simulator.

## aht30 module (done 2026-10-25, 0.1.11)
- `lib/aht30.bas` (module `Aht30`): AHT30 over the `I2c` module, from the Aosong data sheet (Sep 2023). `Aht30Start` / `Aht30Fetch` / `Aht30Measure`, CRC8 over the 6 data bytes, results in 1/100 degree C (`Integer`) and 1/100 %RH (`Word`) using 32-bit integer maths (no Float).
- Test `tests/exec/lib_aht30.bas`: status 4 without a bus, outputs untouched. The conversion was checked in the simulator against Python for raw values 0, 0xFFFFF and a mid-range frame. Nothing runs on a sensor (D6).

## Clock set-up in source (done 2026-10-25)
- Decision: `Clock` stays informational (as with `Declare Xtal`); the hardware is set in source. Written up in `docs/CLOCK.md`.
- `lib/intosc.bas` (module `IntOsc`): start-up writes `OSCFRQ` / `OSCCON1` for `Clock` (64, 48, 32, 16, 12, 8, 4, 2, 1 MHz, and 1 MHz / 2..32), bounded
  waits on `OSCCON3.ORDY` and `OSCSTAT.HFOR`; `SetClock(mhz)`, `SetClockDiv(mhz, shift)` for run-time changes (library timing is not updated, by design).
  Facts from DS40002043F 5.3.1, 5.6.1-5.6.5, Table 5-1.
- Preprocessor `#if` / `#elseif` implemented (`src/pp.rs`: expression evaluator, `scan_header` for `_clock` / `_device`); `#constant` / `#variable` still unsupported.
  The old negative test `pp_if_unsupported` was replaced by `pp_if_bad`, `pp_constant_unsupported`; positive test `tests/exec/pp_if.bas`.
- `W-CLOCK` (`sema.rs::check_clock_setup`): `Clock` differs from the `RSTOSC` speed and nothing sets the oscillator. Earlier docs claimed the
  compiler rejects a `Clock` / `RSTOSC` mismatch; nothing checked it. This warning is that check.
- Tests: `tests/exec/lib_intosc.bas`, `lib_intosc_div.bas`, `pp_if.bas`; `tests/negative/intosc_bad_clock.bas`; `tests/valid/clock_*.bas`. The simulator does not model
  `ORDY`, `HFOR`, `OSCCON2`; the switch itself needs hardware (D6).

## IntOsc start-up trimmed, bit-branch peephole (done 2026-10-25)
- `lib/intosc.bas` start-up no longer calls `Apply`: it writes `OSCCON1` / `OSCFRQ` with the constants and calls `Settle` twice, so `Apply` and its
  five variables are linked only when the program calls `SetClock` / `SetClockDiv`. `OSCCON2` is still read to pick the write order (the reset
  divider depends on `RSTOSC`, DS40002043F Table 5-1: 1:4 for 110). `my_src/first_test` (16 MHz blink): 129 -> 98 words, 11 -> 7 RAM bytes.
- Peephole `pass_bit_branch` (see above): the same program 98 -> 89 words. A `return` ends the dead-`WREG`/flags scan only after `WREG` was
  overwritten (it may carry the result, ABI). Unit test `bit_test_compare_becomes_skip_branch`; simulator suite passes.
- 0.1.2: `Settle` waits for `ORDY` and `HFOR` in one bounded loop (one counter, one budget) instead of two; the liveness scan in `pass_bit_branch`
  now follows `btfsc/btfss` + `bra` (both paths must be dead). `my_src/first_test`: 89 -> 75 words (`Settle` 41 -> 27). Test
  `bit_branch_sees_through_a_skip_over_a_branch`.

- 0.1.3: every successful build ends with a flash and RAM bar against the chosen device (`driver::usage_summary`): flash bytes of
  `memory.program.size`, RAM bytes against `usable_gpr` (system RAM excluded). Colour (green / yellow from 75% / red from 90%) only on a
  terminal with `NO_COLOR` unset, so the VS Code task terminal and logs stay plain.

## Float (done 2026-10-25, 0.1.4)
- `Float` (IEEE-754 binary32) works end to end: variables, constants, arrays, parameters, results, `+ - * /`, unary minus, `Abs`, the six
  comparisons, mixed integer and Float expressions, and `Float(x)` / `Byte(f)` / `Integer(f)` / ... conversions (truncating). D51.
- The arithmetic is `lib/floatlib.bas`, written in the language on 32-bit patterns; the loader adds it when a source mentions `Float`
  (`project.rs`), the lowerer calls it (`lower.rs`: `flt_call`, `to_float`, `value_for`, `float_binary`). Unused routines are not linked.
- Verified in the simulator against Python's exact float32 results: ~1,400 random + edge arithmetic cases (add, sub, mul, div incl. ties,
  cancellation, overflow, underflow, infinities, NaN, signed zero), 1,111 conversion and comparison checks. All bit-exact. The kept tests:
  `tests/exec/float_basic.bas` (language level), `lib_floatlib.bas`, `lib_floatlib_conv.bas`, `lib_floatlib_cmp.bas`; build test
  `float_programs_build_with_the_float_module`.
- Limits: no denormals (flushed to zero), no `Str`/`Print` of a Float yet, no `Sqr` etc., not usable in `Select` / `For` / `Inc`.
  Size: a program using `+ * /` carries roughly 2,500 words of Float code; assembly versions of the routines would be smaller (D51).


## Device descriptions for PIC16F17126 / PIC16F17146 (0.1.12)

- `devgen` gained the `16Exxx` (enhanced mid-range) family table: reset 0000h, single interrupt vector 0004h (DS40002343F p.36-37).
  `devices/16F17126.toml` and `16F17146.toml` are generated from PIC16F1xxxx_DFP 1.32.471 and cross-checked by `scripts/check-devices.sh`
  against hand-written `*.expect.toml` files (Table 1 p.1, Table 9-1 p.36, Sec. 8.1/8.4 p.24).
- Not compilable yet: no `pic16e` code generator, so `Device = 16F17146` reports `E-DEVICE` saying so. Errata (DS80001009) not yet reviewed.


## Library made device-independent, step one (0.1.18 - 0.1.20)

- `#if _has(REG)` and `_has(REG.FIELD)`: true when the device description defines that register or bit field. The loader reads the
  register list from the file named by `Device =`, so a new part gets it with no compiler change.
- Ported: `gpio`, `intosc`, `system`, `timer`, `serial`, `adc` (PIC18F27/47Q10 output byte-identical; the PIC16F17126/46 branches are
  checked against DS40002343F / DS80001009E and by preprocessing only, because there is no `pic16e` code generator).
- **Still to do** (listed with the reasons in `docs/LIBRARY.md`, "Device support"): `serial2`, `i2c`, `spi`, `pwm`, `lcd`, `oled`
  (PIC18 table reads), `eeprom` (different NVM registers). **Every new device or family must review that table** (DEVICE-FORMAT.md
  checklist step 8, PLAN §9.3 step 5).

## Event extensions (done 2026-10-25, 0.1.23)
- Comparison: `=`/`<>` between event variables of one type, or an event variable and a handler (`sema.rs` `relational`;
  the lowerer already compared the bytes).
- Arrays of events: the `E-DIM` refusal is gone (initialisers are still refused); `Tbl(i)(args)` calls through the
  indexed element (`lower.rs` `call_stmt` no longer requires a plain variable).
- Parameters: `Event(ByVal ...)` types and handlers (`ast.rs` `EventType(Ident, Vec<Param>)`, `EventDecl.params`; `sema.rs`
  `event_params`, `event_sig`, `Ty::EventAny(handler)`). One dispatcher per parameter list (`lower.rs` `EvDisp`), its first
  parameter the handler number; each arm copies the dispatcher's parameters into the handler's.
- Implicit `Save`: an event call directly in an `Interrupt` body outside `Save` is wrapped in `St::Save` of the working
  registers (`call_stmt`, `in_isr`); the codegen adds the frames of everything the dispatcher reaches. `E-ISR-CALL` no longer
  applies to events; `tests/negative/event_in_isr.bas` was removed.
- `Module.Variable`: sema resolves it to the symbol and leaves the member in `parts`; `place_inner_parts` now skips it
  (it had been `E-BACKEND`, "the member ... is not supported").
- Library: `Timer0/1/2OnExpire` + `Timer0/1/2Service`, `SerialOnRx` + `SerialRxService` (modules still declare no `Interrupt`; unused,
  they cost no flash or RAM).
- Tests: `tests/exec/events_array_cmp.bas`, `events_params.bas`, `events_isr.bas`, `lib_timer_event.bas` (simulator); negative
  `event_arg_count`, `event_sig_mismatch`, `event_byref_param`; valid `event_params`. The result variables of the exec tests are
  `Volatile` (no longer needed, see below).

## Exec tests keep unread variables (done 2026-10-25, 0.1.24)
- Since 0.1.17 the peephole pass `pass_write_only` deletes `movwf v` for a variable nothing in the program reads, so 39 of the simulator
  tests (which read their result variables from RAM after the run) failed in the optimised build. `basil --keep-vars` now turns that
  pass off (`Target::keep_vars`, `peephole::Env::keep_writes`); `scripts/exec-test.py` always passes it. The default build is unchanged.
  The simulator suite passes again, optimised and `-O0`.


## Smaller start-up code (done 2026-10-25, 0.1.25)
- `lib/intosc.bas`: for `Clock` >= 1 MHz the start-up code no longer compares against `OSCCON2` (the new divider is 0, so the
  other order was dead code), and waits with a new `WaitSettle()` Sub instead of `Settle()`, whose Boolean nobody read.
  `Settle()` now calls `WaitSettle()`. The 18F27Q10 blink example went from 127 to 103 words.
- `peephole::pass_halt_loop` drops `__halt: bra __halt` when the main program ends in an endless loop (102 words).
- `tools/pic-config`: Clock drop-down that prepends `Device`/`Clock` and appends `Include "intosc"`, with a `CSWEN` warning.
- Not done: `movlw 0 ; movwf` to `clrf` (the delay counters are in cycle-exact code; the `TBLPTR` bytes are label parts) and
  `bcf` after `clrf` of the same register.


## OLED drawing commands (done 2026-10-26, 0.1.30)
- `lib/oled.bas`: `OledBitmap` (Const image straight to the display), and a 1024-byte frame buffer with `OledPixel`, `OledPoint`,
  `OledBufFill/Clear`, `OledUpdate`, `OledLine` (Bresenham, clipped), `OledRect`, `OledFillRect`, `OledBufBitmap`, `OledBufChar`,
  `OledBufText`. The buffer is not linked unless a program calls one of them.
- The font table is now a `Const Font(475)` array instead of an `Asm` block (text-only program 625 -> 604 words); the old table had
  one stray trailing byte.
- `tests/exec/lib_oled.bas` checks the buffer logic in the simulator. Nothing runs on a panel (D6).

## Flash self-write library (done 2026-10-26, 0.1.31)
- `lib/flashwrite.bas`: `FlashReadWord`, `FlashEraseSector`, `FlashWriteWord`, `FlashUpdateWord`, `FlashSectorAddr`; word addresses
  (0..65535), 128-word sectors. Unlock codes from Table 12-4, registers from 12.5.1-12.5.5, sequences from Examples 12-3..12-5 (DS40002043F).
- Errata 1.9.1 (DS80000832G p.7): two all-zero `NOP`s after each `BSF NVMCON1,x`, in the same `Asm` block (checked in the emitted .S).
  1.6.2 (no writes above 85 C) is documentation only; 1.6.1 is handled by clearing `NVMERR` before and reading it after each operation.
- `tests/exec/lib_flashwrite.bas`: the simulator does not model flash reads, so it checks `NVMADR`, `NVMEN`, `GIE` restore, `NVMERR`,
  and `TBLPTRL`/`TABLAT` left by the sector read-modify-write. A scratch run showed `NVMERR` clear after SECRD, SECER and SECWR.
  `FlashEraseSector` rejects a sector above 511 (it would wrap onto a lower one). Nothing runs on hardware (D6).

## Overloading, multi-dimensional arrays, string arrays, structure initialisers, Reentrant (done 2026-10-26, 0.1.32)
- Overloading: `declare_routine` keeps further routines of a name in `Analysis::overloads` (the scope table holds the first);
  `pick_overload` scores each candidate (exact type 0, widening 1 + width/8, narrowing 100) and records the winner per call
  designator in `Analysis::call_targets`, which the lowerer's `callee_of` follows. Tests: `tests/exec/overload.bas`, negatives
  `overload_duplicate`, `overload_ambiguous`.
- Multi-dimensional arrays: `DimItem::more_dims`; the array stays a flat `Ty::Array` (row-major) and `Analysis::dims` /
  `md_index` give the lowerer each dimension, so `apply_parts` folds `i*stride + j*...` into the existing byte offset.
  Never bit-packed. Test: `tests/exec/multidim.bas`.
- Arrays of strings and String fields of structure array elements picked at run time: `point_str` adds the element offset to
  the FSR; an index that itself reads an array, or aliasing between two run-time elements, is still `E-BACKEND`.
  Tests: `strarray.bas`, `structstr.bas`.
- Structure initialisers `Dim p As T = (a, b, ...)` for numeric, Boolean, Char and String fields. Test: `structinit.bas`.
- `Reentrant`: caller-save. A call to a routine that can reach the caller again pushes the caller's variables and `__TMP`
  bytes with `movff x, PREINC2` and pops them with `movff POSTDEC2, x` (the device has no PREDEC); the result is read
  before the pop. `__SWSTK` is 32 x the largest push, and exists only if something recurses. Test: `reentrant.bas`.
  Not done: forward declarations (so no mutual recursion in source), a depth check, XINST frame addressing (PLAN 7.2).

## CI and releases (done 2026-10-26, 0.1.33)
- `.github/workflows/ci.yml`: `cargo test --workspace` on Linux, macOS and Windows for every push to `main` and every pull request;
  tests needing `pic-as` or the simulator skip themselves there. A pull request gets the label `ci: passing` or `ci: failing`.
- `.github/workflows/release.yml`: pushing a tag `vX.Y.Z` builds `basil` for Linux x86_64, macOS arm64, macOS x86_64 (cross-built on the
  arm64 runner; the `macos-13` Intel runner never started) and Windows x86_64, packs each with `lib/`, `devices/` and the docs, and
  attaches them to a GitHub release. To release: bump `version` in `Cargo.toml`, commit, `git tag vX.Y.Z`, `git push origin vX.Y.Z`.
  The release also carries `Basil_Manual.pdf`, built in CI from `docs/MANUAL.md` by `scripts/build-manual-pdf.sh` (pandoc + weasyprint).
  A tag cannot be reused after a failed build; bump the version instead (`v0.1.32` has a tag but no release).
- The release binaries have been built by CI but not run on macOS or Windows.
- `tests/exec/arith_mulconst.bas` takes about 2 minutes to compile with a release build (31,088 words) and much longer in a debug build;
  it is generated by `scripts/gen-arith-tests.py`. Run the other programs with `--basil target/release/basil` for a quick regression.

## Smaller Float code and call sites (done 2026-10-26, 0.1.34)
- `lib/floatlib.bas` is now assembly (D55). `my_src/first_test/main.bas` (an OLED Float self-test) went from 5107 to 2775 words;
  `lib_floatlib` runs in about a third of the cycles. New tests: `lib_floatlib_edge.bas` (against a port of the old algorithms) and
  `float_compare.bas` (every comparison on every pair of 0, -0, 1, -1, inf, -inf, NaN, 0.5, as a value and as an `If`).
- Compiler: an `Asm` block now defines the scratch registers it names (`__A0`..`__D3`), links and records a call to any routine it names, and
  a function whose `Asm` block stores into `<ROUTINE>__RESULT` gets neither `W-NORESULT` nor the clear of `Result` on entry.
- Calls whose arguments contain another call (`codegen.rs::do_call`): only values computed before the last call wait in `__TMP`; constants
  are stored at the end, and the last call's value and every argument after it go straight into the parameters.
- Peephole: scratch-register writes before a call to a user routine are dead (only the `__` helpers read them).
- `x Xor k` / `x Or k` on several bytes no longer emits a `bsf STATUS, 0` per zero byte of `k`.


## PIC18-Q41 support: PIC18F04/05/06/14/15/16Q41 (done 2026-10-26, 0.1.35)
- Devices: `devices/18F04Q41.toml` … `18F16Q41.toml`, generated by `devgen` from `PIC18F-Q_DFP 1.31.492` and cross-checked against
  DS40002214G / DS40002242F (`*.expect.toml`; the pack's 18-byte configuration sector is an accepted difference, the NVM buffer bank is
  `system_ram_bytes`). Facts and their pages: `docs/FACTS-18F-Q41.md`. Data sheets and errata are in `docs/` (not tracked).
- `devgen`: a `JoinedSFRDef` with one byte member (`DAC1DAT`) is an ordinary SFR; the device file carries the hardware stack depth
  (`hw_stack`: 31 on the Q10, 127 on the Q41, 16 on the 16F) and `E-STACK` uses it; the expect file takes `system_ram_bytes`,
  `hw_stack_levels` and `[accepted."…"]`.
- Compiler: the Access Bank is two ranges (`0500h..055Fh` RAM and `0460h..04FFh` SFR on the Q41), `movff` becomes `movffl` above `0FFFh`
  (the sizes the branch relaxation uses stay exact), the interrupt controller is `INTCON0` (`Enable` sets only `GIE` without priorities,
  `Disable` is a single `bcf`), a handler's vector word is a `goto`, hardware saves `FSR0..2`/`PRODL/H` as well as `WREG`/`STATUS`/`BSR`
  (so they are not saved in software and `RETFIE, FAST` is used for both priorities), `MVECEN` is forced off for a program with a handler
  (`E-CONFIG` if the program asks for it), and `_FlashBytes`, `_EepromBytes`, `_RamBytes` are predefined constants.
- Fixed on the way: the configuration words cleared every bit the pack's `implemented` mask omits. On the Q41 that cleared `DEBUG` and
  `WRTAPP` (debug mode, application flash write-protected: every self-write failed in the simulator); they now stay at 1, as in
  Microchip's own output. On the Q10 the bits concerned are `CONFIG4L`/`CONFIG6L` bits 3:2 (`WRT2`, `WRT3`, `EBTR2`, `EBTR3`), now 1.
- Libraries ported: `gpio`, `delay`, `intosc`, `system`, `timer`, `serial` (UART1), `serial2` (UART2), `adc` (12 bits, `AdcMax`; the 16F
  was also 12-bit and used 1023: fixed), `eeprom`, `flashwrite`, `spi` (SPI1), `lcd`, `i2c` (software host on two pins: the I2C1
  peripheral counts bytes in hardware and cannot carry the step-by-step API), `pwm` (channels 1..6 = PWM1S1P1 … PWM3S1P2), `oled`
  and `aht30` (over the software I2C). Q10 output of every ported module is byte-identical to before (compared on the assembly).
- Tests: `tests/exec_q41/*` (simulator), the portable `tests/exec` programs run with `exec-test.py --device 18F16Q41`
  (`BASIL_MDB=1 cargo test q41`), `q41_*` build tests for all six parts, `tests/negative/q41_mvecen_with_handler.bas`. Simulator limits:
  no UART shift-out, no vectoring on `SWIF` (the timer interrupt tests now use aliases chosen with `_has(PIR3.TMR0IF)`).
- Not done: a hardware I2C1 driver, `floatlib` on the Q41, hardware runs. Nothing was run on a real part, and the I2C transfer code ran against no bus.
