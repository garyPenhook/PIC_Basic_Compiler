# Remaining assembly efficiency opportunities

Review of current source and fresh default optimized `bench/large` listings, 2026-11-17.
The initial review made no compiler changes; subsequent implementation is noted below.
Counts below are observed output or explicitly identified estimates. Unimplemented
transformations have not been simulator-validated.

## Baseline

Generated with `target/release/basil -S --report`. For PIC16, changed the device to
16F18346, clock to 32, and oscillator configuration to HFINT32.

| Program | PIC18F27Q10 bytes | PIC16F18346 words |
| --- | ---: | ---: |
| a_algo | 1314 | 907 |
| b_dsp | 2022 | 1500 |
| c_text | 1292 | 1003 |
| d_ctrl | 1108 | 859 |
| Total | 5736 | 4269 |

These match the latest recorded sizes. Listings from this review are in
`/tmp/pic-eff-review` (temporary, not a repository dependency).

## 1. PIC16 signed division by a power of two

Implemented after this review; see `docs/EFFICIENCY.md` section 27 for the
policy, measurements and validation. The remaining text records the original finding.

Highest-priority speed candidate. `src/codegen16/expr.rs::muldiv` special-cases
power-of-two multiplication but otherwise uses the general division helper.
In b_dsp, Sine `/4`, Lowpass `/8`, PID `/8`, plant `/16`, Mean `/32` and RMS `/32`
all still call `__sdiv2` or `__sdiv4`. Four of these sites run in 32-iteration loops.

PIC18 already implements bias followed by arithmetic shift in
`src/codegen.rs::div_signed_pow2`, and signed remainder in `mod_signed_pow2`.
Port the semantics using enhanced mid-range instructions and an explicit size
comparison. Negative division must truncate toward zero: arithmetic shift alone
is wrong, for example -9 / 8 must produce -1. Check negative exact multiples,
minimum signed values, zero, width boundaries and remainder sign.

Likely substantial cycle savings; flash savings depend on the shift sequence and
whether other divisions still need the helper. Do not count helper removal in
b_dsp: its `/160` still needs general division.

## 2. Descending walks and adjacent elements

Implemented for single descending element copies using stationary source and
destination pointers, stepped at the loop tail. DSP improves from 1472 to 1455
words and 214171 to 208571 simulator cycles, with RAM unchanged at 164 bytes.
Overlap, bank crossings and index-wrap fallbacks are covered; general descending
expression walks remain open. See EFFICIENCY.md section 28. The original
opportunity analysis follows.

PIC16 FIR's `hist(i) = hist(i - 1)` loop still builds two full FSR0 addresses per
iteration. The current listing has nine instructions for the source address and
eight for the destination, before counting loads, stores and temporary staging.
It repeats seven times per FIR call, across 32 calls.

Extend walk recognition to constant descending loops and fixed element offsets.
Keep a pointer to the destination and read the source at offsets -2 and -1,
then write offsets 0 and 1, stepping the pointer by -2. This should remove most
of those 17 address instructions per iteration, with setup paid once per loop.
That is a local instruction-count opportunity, not a measured final saving.

Start with fixed bounds, step -1, one array, no calls or escaped/volatile storage.
Preserve descending copy order because source and destination overlap. Check
linear RAM-bank boundaries, Continue, empty loops and Byte/Word index wrap.
Existing entry points: `src/codegen16/stmt.rs::walk_plan`, shared
`src/codegen.rs::walk_block` and `stream_scan`.

## 3. PIC16 bank-aware producer retargeting

FIR still emits `__A -> K_FIR__RESULT -> K_F` for both bytes. The listing contains
four move instructions for this last copy, plus bank selections. Build the result
directly into K_F when the physical result bytes are dead until overwritten.

PIC18 already has a control-flow-aware overwrite proof; PIC16 needs destination
bank handling and alias checks throughout the producer. Removing four moves is
the gross local opportunity; bank-selection changes determine the net saving.
Lowpass also retains result staging and is a second useful fixture.

See `docs/EFFICIENCY.md` sections 23–25. Preserve interrupt-visible objects,
address-taken aliases, skip behavior, flags and `--keep-vars` semantics.

## 4. Eliminate initialization of a partially used local array

PIC18 ToDec still clears all 12 bytes of `tmp` on entry, although this routine
writes every byte it subsequently reads. The zero-input path explicitly writes
tmp(0); other paths write the prefix [0,n) and read that prefix in reverse.

The emitted clear is six words: two-word LFSR, MOVLW, CLRF, DECFSZ and BRA.
Removing it saves approximately 50 executed cycles per call for this specific
12-byte sequence, excluding any downstream layout effects.

An array-clear candidate already exists at `src/opt.rs::without_array_clears`.
Extend its proof to a variable-length initialized prefix and its reverse traversal,
rather than adding another general dead-store pass. Bounds and path coverage
must be proved; preserve initial-zero reads in other programs. Consider both cores.

## 5. Share the shift present in both Isqrt branches

PIC18 a_algo Isqrt still emits the five-instruction `r >> 1` sequence in each
branch. RMS has the same source structure. A structured IR transformation could
share the shift while retaining the conditional subtraction and addition.

The duplicate shift costs five words per site before control-flow changes.
Do not move it above the comparison: that comparison needs the old r, and the
shift clobbers flags. A rewrite may need a retained decision or another branch,
reducing the net saving. Measure flash and cycles separately.

## 6. PIC16 peephole coverage and multiply policy

`pass_shared_compare`, `pass_same_load` and `pass_forward_unary` in
`src/peephole.rs` explicitly return without doing work on PIC16. Port only after
finding qualifying listing patterns; two-operand syntax, bank state and indirect
read effects need core-specific handling. Their absence alone is not a savings
measurement.

`src/codegen16/helpers.rs::mul_helper` terminates wide multiplication early only
under Optimize=Speed. Default `__mul4` performs all 32 iterations even when the
multiplier has few significant bits. Evaluate a shared early-exit helper or
narrow-operand specialization. Signed negative operands are sign-extended, so
early exit alone will not shorten those cases. The wide OR test also adds work
on long multipliers; benchmark representative operand distributions before
changing the default policy.

## Suggested implementation order

1. PIC16 power-of-two division: existing PIC18 semantics and many hot call sites.
2. Descending adjacent-element walks: concentrated repeated addressing in FIR.
3. PIC16 result producer retargeting: smaller, directly visible copy savings.
4. Prefix initialization proof and shared shifts.
5. Other peephole ports and multiply policy after targeted measurements.

Validate each implementation with optimized and -O0 execution, all four large
benchmark sizes, and the existing backend checks. Include signed arithmetic,
physical aliases, bank crossings and retained-variable builds where relevant.
