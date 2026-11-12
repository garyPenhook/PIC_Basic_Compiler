# Code generation: open items (2026-11-12)

Open items left after review 3 (`docs/EFFICIENCY.md` section 12.4, basil 0.1.190).
Committed as 0.1.191; 0.1.192 adds unit tests, review fixes and the docs. The 16F gate and the unit tests now pass; the full `BASIL_MDB=1` suite was not run. Files: `src/peephole.rs`,
`tests/exec/param_result.bas`, `docs/MANUAL.md`, new `scripts/gate.sh`, and this file.

## Where it stands

| | 0.1.190 | 0.1.191 |
|---|---:|---:|
| PIC18F27Q10, `bench/large`, four programs | 6180 bytes | 6118 bytes |
| PIC16F18346, same sources | 4685 words | 4653 words |

Per program now: PIC18 a_algo 1338, b_dsp 2364, c_text 1296, d_ctrl 1120; 16F 960, 1738, 1017, 938.

**Checked:** `scripts/gate.sh` (PIC18 in basil-sim: `tests/exec`, `bench/large`, all library models, optimised
and `-O0`) passes on the working tree.

**Not checked yet:**
- `scripts/gate.sh 16` (PIC16F17146 in MDB). The 16F output changed (32 words smaller, from the
  `pass_write_only` change) and has not been run in a simulator.
- `cargo test --release` (unit tests) and the full `BASIL_MDB=1 cargo test --release`.
- No unit tests exist for the five new passes.
- The self-review pass on the diff (`/code-review`) has not been run.

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
- `bench/large` now: PIC18 6108 bytes, 16F 4642 words.

## Still to do

### From the review list, not started
Both cores
- Dense `Select` (R11) as a computed jump. Design note: it needs its own `Item` (the dispatch and the table
  together, sized in `asm.rs` relaxation), because `dead_paths`, `pass_redundant_movlb_flow` and `fsr_flow`
  follow only the fall-through after an instruction that writes PCL. The PIC18 computed-goto rules and the
  16F `BRW` instruction must be confirmed in the data sheets first.
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
