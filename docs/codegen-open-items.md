# Code generation: open items (2026-11-12)

Open items left after review 3 (`docs/EFFICIENCY.md` section 12.4, basil 0.1.190).
Committed as 0.1.191; 0.1.192 adds unit tests and review fixes; 0.1.193 and 0.1.194 are the IR-level items and their review fixes; 0.1.195 is the dense `Select` as a computed jump. Files: `src/peephole.rs`, `src/opt.rs`,
`tests/exec/param_result.bas`, `abs_idiom.bas`, `narrow_result.bas`, `sub_reassoc.bas`, `docs/MANUAL.md`, `scripts/gate.sh`, and this file.

## Where it stands

| | 0.1.190 | 0.1.191 | 0.1.194 |
|---|---:|---:|---:|
| PIC18F27Q10, `bench/large`, four programs | 6180 bytes | 6118 bytes | 6108 bytes |
| PIC16F18346, same sources | 4685 words | 4653 words | 4642 words |

Per program now: PIC18 a_algo 1330, b_dsp 2364, c_text 1294, d_ctrl 1120; 16F 957, 1732, 1015, 938.

**Checked (0.1.194; 0.1.195 is under "Dense `Select`" below):** `scripts/gate.sh` (PIC18 optimised and `-O0`) and, at 0.1.193, `scripts/gate.sh 16`
(PIC16F17146 in MDB) pass. `cargo test --release` passes. Self-review (`/code-review`) was run on the IR-level diff
and its findings dealt with.

**Full `BASIL_MDB=1 cargo test --release` (0.1.194):** 53 of 54 backend tests passed. `p180_programs_in_simulator`
failed once on `static_local` (16F18056: values shifted between symbols, `SL_H` without a memory dump). The same
program passes alone on that part, optimised and `-O0`, and the test passes when run by itself (684 s), so it is
taken as an MDB fault under the parallel load, not a compiler fault; the cause is not found. No clean full-suite run
yet.

**Not checked yet:**
- A second full `BASIL_MDB=1` run, to see whether the `static_local` failure comes back.

## Done

### Follow-ups
- **Gate script committed form:** `scripts/gate.sh` (`gate.sh`, `gate.sh 16`, `gate.sh sizes`). It runs
  `tests/exec`, `bench/large` and the library-model folders (`exec_rtcc`, `exec_glcd_*`, `exec_epaper`,
  `exec_pins`), optimised and `-O0`, and prints the `bench/large` sizes for both cores. The 16F list is read
  from `P16_PORTABLE` in `tests/backend.rs`.
- **Regression test for the result-parameter loop fix:** `LastRead` in `tests/exec/param_result.bas` (new
  expectation `T_G=84`). The old `LastOf` case passed without the guard because its loop became a count of
  passes; the new body reads the loop variable. Confirmed: fails with the `results.contains` guard in
  `opt::free_loop_ends` removed (R1 49 for 48), passes with it, also at `-O0`.
- **Manual:** `docs/MANUAL.md` has a `#option Optimize` paragraph that says what `Speed` changes, including
  that equal branch ends are no longer shared.

### Compiler (`src/peephole.rs`, PIC18 unless noted)
- `pass_shared_compare` (R6, shared compare): `If a = b ... ElseIf a < b` on the same operands does one
  `subwf` and tests Z then C. `BinSearch` lost 6 words.
- `pass_cpfs_held` (R6, bubble-sort compare, partly): `movf A,w; subwf B,w; bc` with `B` already in `WREG`
  becomes `cpfsgt A; bra`. One word. Both elements are still stored to temporaries (the swap needs them).
- `fsr_flow` / `pass_lfsr_flow` (R12, facts across labels, FSR part): forward data-flow of what FSR0..2 hold,
  so an `lfsr` goes when every way into a label already loaded it (the sieve `While`, `BinSearch`,
  the insertion sort).
- `pass_same_load` (R12): a value loaded into `WREG` a second time by the same instructions is not loaded
  again (`a(j - 1)` tested, then copied). A fault found by the gate while writing it (scratch registers were
  not counted as inputs of the held value; `arith_byte`, `arith_shortint`, `div_mod_share` failed) is fixed.
- `pass_forward_unary`: `comf S,w; movwf T; ...; movf T,w` makes the value again at the read, so an inlined
  `Result = Not x` used in the next statement loses its copy (`Crc32`, 8 words).
- `pass_write_only` (both cores): a store to a byte `v+k` of a variable nothing reads now goes, not only a
  one-byte variable. This is the whole of the 16F gain.

### IR level (0.1.193)
- `(n - 1) - i` (`opt::fold`): `(x - c) - v` becomes `x - (v + c)` when `v` is a plain variable, so the PIC18 emits
  `incf i, w; subwf n, w` (2 words) instead of `decf n, w; subwf i, w; sublw 0`. `ToDec` -1 word PIC18; 16F -2 words.
  `tests/exec/sub_reassoc.bas` (Byte, Word, Integer, LongInt, ShortInt, with wrap).
- Narrow result (`opt::coalesce_results`): `Result = r` with `r` a wider local of a routine that calls nothing makes
  `r` the result object; callers read its low bytes. `Isqrt` -4 words PIC18, 16F -9 words over `bench/large`.
  `tests/exec/narrow_result.bas` (high bytes must not leak; a routine with a call is left alone).
- `Abs` idiom: nothing to do. `If v < 0 Then v = 0 - v` already compiles to the 6-word `Abs` sequence
  (`btfss v+1,7; bra; comf; negf; movlw 0; addwfc`), the same as `Abs(v)`; pinned by `tests/exec/abs_idiom.bas`.
- `bench/large` at 0.1.194: PIC18 6108 bytes, 16F 4642 words.

### Dense `Select` as a computed jump (0.1.195, R11)
- Data sheets read first: PIC18 `PCL` is read to latch PC[20:8] into PCLATU:PCLATH and any write of PCL loads them
  back (DS40002214G 9.1.2 p.60; Q10 DS40002043F 11.1.3.1 p.113), the example puts the table at `nn00h` so the add of
  W to PCL cannot overflow (p.62); 16F `BRW` is PC + 1 + W, W unsigned (DS40002343F p.596). No erratum names either.
- Shape (`dense_shape`, shared by both generators): an `If` chain whose every test is `x = const` (or an `OrElse` of
  them) on one non-volatile Byte/ShortInt variable, at least four values, table of at most 100 slots, chosen when
  `n + 6` (PIC18; 5 on the 16F) is under 2 words (3 on the 16F) a value; `Optimize = Speed` adds a word a value. `Select`
  and `On n GoTo` lower to such chains, as do hand-written `If`/`ElseIf` chains. The code: `[addlw -lo]; sublw n-1;
  bnc default; (PIC18: rlncf; addwf PCL | 16F: brw)` then `bra` entries, in reverse order since W counts from the end.
- PIC18 only: `movf PCL, w` first, then `Item::Fit(true)..Fit(false)` makes the assembler put `nop`s in front so that
  latch, dispatch and table share one 256-byte block (sizes are those at assembly, so it follows branch relaxation).
- Table `bra` reach (16F 256 words): `add_table_stubs` measures the code to each target at its largest and routes
  far ones through a `Br` stub placed after the table.
- Interrupts: a handler that reads PCL saves PCLATH/PCLATU (`Regs::scan`; the vectored controller does it itself).
  An interrupt between the latch and the `addwf` would otherwise land on the handler's page.
- Peephole: the dispatch and table are in `Keep` regions; `jump_table` lets `fsr_flow` and
  `pass_redundant_movlb_flow` send state to every entry (control reaches an entry by the jump, not by falling
  through); `pass_copy_prop` looks through `Fit`/`Keep` markers. Unit tests: both flows, `Fit` in `asm.rs`.
- Tests: `tests/exec/select_dense.bas` (lo 0 and not 0, gap, list arm, duplicate in an `If` chain, signed, top of the
  byte, arm that changes the subject), `select_dense_many.bas` (20 tables so some are moved to the next block),
  `select_dense_far.bas` (stubs, both cores), `select_dense_isr.bas` (`engine: mdb`; fails there without the PCLATH
  save, passes in basil-sim either way because basil-sim does not model PCLATH).
- `bench/large` at 0.1.195: PIC18 6108 bytes (unchanged), 16F 4624 words (-18, all in `d_ctrl`).
- Review (`/code-review high`) findings dealt with: with a C link on PIC18 the dense `Select` is not used (the linker
  places the code, so the 256-byte blocks `Fit` pads for are unknown); `jump_table` returns nothing unless the run of
  `bra` ends at `Fit(false)`/`Keep(false)`; `#line` written once per padding run; the PCLATH/U hardware save is cited
  (DS40002214G p.121).
- Left as is: `Fit` padding only grows during layout (a rare layout can keep more `nop`s than needed); the two
  `dense_switch` methods (`codegen.rs`, `codegen16/stmt.rs`) are near copies; `largest_words` counts a `Raw` line as
  one instruction (the reach margins cover it, untested with long inline-assembly arms).
- Checked: `scripts/gate.sh 16` (PIC18 and PIC16F17146, optimised and `-O0`) and the library unit tests pass. Full
  `BASIL_MDB=1 cargo test --release` not run for 0.1.195.
- basil-sim and MDB differ in cycles on these programs (`select_dense_many` 14201 against 14052): not looked into.

## Still to do

### From the review list, not started
Both cores
- Peephole facts across labels for `WREG` and scratch contents (only the FSRs are done).
- Entry clear of a local array (`ToDec`).
- Three-variable rotate (`Fib`, 28 words, 20 possible).

PIC18
- Array walks for Word/Long elements, two arrays in one loop (FIR), `arr(i + k)`.
- Overlaid results (`K_FIR__RESULT` under `K_PID__D`).
- Operand that reads the destination (`sink + Isqrt(..) + Isqrt(sink)`).
- `Integer * Byte` inline with two `mulwf`.

16F
- Copy propagation, load reuse and `moviw k[FSR0]`, bank placement, counted walk with `decfsz`,
  `__mul4` early exit outside `Optimize = Speed`.
- 16F forms of `pass_shared_compare`, `pass_same_load` and `pass_forward_unary` (all return at once on
  that core).
- Done in 0.1.199: `effect16` now carries the scratch-byte fact (`w_scr`) of the PIC18 model, so on the 16F
  `movwf __A0; movf __A0, w` loses the reload (`bench/large` 16F 4624 to 4617 words). A scan of the four listings found
  no other straight-run reload on the 16F, and only 3 loop-head `movf X, w` after a label on the PIC18 (all with a
  back edge that reloads), so WREG facts across labels would save about 3 words: not worth the pass.

Seen while reading the listings, not on the original list
- `Isqrt`: both arms of the `If` hold the same `r = r >> 1` (5 words twice).

### Follow-ups not done
- `bench/kernels` (`scripts/bench.py`) and `bench/random` not re-measured; the kernel table in
  `docs/BENCHMARKS.md` is still stale. Best done once, after the code-generation work stops.
- README size claim still quotes 7092 bytes against 7560.
- `docs/EFFICIENCY.md` 12.4, `docs/PROGRESS.md` and `docs/BENCHMARKS.md` do not yet record this work.
- Hardware check: everything is simulator-only; nothing has run on a real part.

## To pick up again
1. `scripts/gate.sh 16`, then `cargo test --release`.
2. Unit tests for the five new passes, self-review of the diff, update the three docs.
3. Continue with the list above. The IR-level items are done (see below), except `Rms`, which calls a routine and so keeps its copy.
