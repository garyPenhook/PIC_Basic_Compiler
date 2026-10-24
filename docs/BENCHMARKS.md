# Benchmarks

Produced by `scripts/bench.py` (kernels in `bench/kernels/NAME.bas` and `NAME.c`). Sizes are
program bytes and data-RAM bytes of the whole image including start-up code; cycles are the
simulator's count between two markers (MPLAB X `mdb`, PIC18F27Q10), with the C marker-call
overhead measured on an empty kernel and subtracted. Every kernel leaves a result in `sink`; the
script fails if the three builds disagree. Comparators are used as black boxes (PLAN §2): XC8
v4.00 `-Os` / `-O2`.

## Baseline — M4, 2026-10-23 (first code generator, no optimisation passes yet)

| kernel | basicc B | RAM | cyc | XC8 -Os B | RAM | cyc | XC8 -O2 B | RAM | cyc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| add32 | 172 | 22 | 57208 | 196 | 21 | 17166 | 218 | 21 | 18350 |
| bitbang | 34 | 3 | 182 | 62 | 3 | 165 | 62 | 3 | 165 |
| cmpchain | 62 | 5 | 3421 | 88 | 5 | 3224 | 88 | 5 | 3224 |
| crc8 | 68 | 4 | 8175 | 86 | 4 | 6376 | 86 | 4 | 6641 |
| div16 | 188 | 16 | 32280 | 292 | 18 | 29380 | 306 | 18 | 30746 |
| fixmul | 152 | 15 | 33463 | 104 | 8 | 3725 | 110 | 8 | 3870 |
| mul8 | 68 | 8 | 2004 | 97 | 7 | 1109 | 99 | 7 | 1110 |
| state | 74 | 5 | 1877 | 94 | 4 | 1532 | 102 | 4 | 1857 |
| sum16 | 44 | 5 | 2004 | 72 | 6 | 1807 | 74 | 6 | 1808 |

Size relative to XC8 `-Os`: median **0.70**, best 0.55 (bitbang), worst **1.46** (fixmul).
Cycles relative to XC8 `-O2`: median **1.11**; outliers are the multiplications by a constant
(`fixmul` 8.6×, `add32` 3.1×, `mul8` 1.8×), which go through the generic shift-and-add helper.

Start-up reference point from PLAN §7A.4 (`x = 5`, then `x = x + 1` forever, `x` a byte): XC8
24 bytes / 1 byte RAM, Swordfish 32 / 26, **basicc 14 / 1** (the start-up `clrf` of `x` goes in M5).

## After M5 hardware multiply, 2026-10-24

| kernel | basicc B | RAM | cyc | was cyc |
|---|---:|---:|---:|---:|
| add32 | 128 | 17 | 4808 | 57208 |
| fixmul | 128 | 12 | 7437 | 33463 |

The other kernels are unchanged. `add32` is now 0.26× XC8 `-O2` in cycles; `fixmul` is 1.9×
(its `For` loop and the accumulator traffic remain, M5 `DECFSZ` and peephole items).

## Why the numbers look like this

* Size is already below XC8 because nothing is emitted that is not used (no runtime, one static
  frame, helpers only when reached) and branches are relaxed to their short forms.
* Cycles lose where the generator is naive: multiplication by a constant and 16×16 products use
  the shift-and-add helper instead of `MULWF`/`MULLW` (M5, pass 6), `For` loops compare and branch
  where a count-down `DECFSZ` loop would do (M5), and values travel through the `__A` accumulator
  where a peephole would keep them in place (M5, pass 8).

## Targets, calibrated from this table (PLAN §7A.4, D18)

The placeholders in the plan were "+20 % of XC8 `-Os` at M5" and "at or below `-Os` at M9". The
baseline already meets the size ones, so they are tightened; cycles are the open front.

| Gate | Size (vs XC8 `-Os`) | Cycles (vs XC8 `-O2`) |
|---|---|---|
| M5 | median ≤ 0.85, no kernel > 1.25 | median ≤ 1.15, no kernel > 2.0 |
| M9 | median ≤ 0.75, no kernel > 1.0 | median ≤ 1.0, no kernel > 1.25 |
| Always | no kernel regresses > 3 % in size or cycles without a note here | |

Re-run `scripts/bench.py --md` after any change to code generation and update the table with the
compiler revision.
