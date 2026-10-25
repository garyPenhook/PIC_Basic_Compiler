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
24 bytes / 1 byte RAM, another BASIC compiler 32 / 26, **basicc 14 / 1** (the start-up `clrf` of `x` goes in M5).

## After M5 hardware multiply, 2026-10-24

| kernel | basicc B | RAM | cyc | was cyc |
|---|---:|---:|---:|---:|
| add32 | 128 | 17 | 4808 | 57208 |
| fixmul | 128 | 12 | 7437 | 33463 |

The other kernels are unchanged. `add32` is now 0.26× XC8 `-O2` in cycles; `fixmul` is 1.9×
(its `For` loop and the accumulator traffic remain, M5 `DECFSZ` and peephole items).

## After M5 counted loops, 2026-10-24

| kernel | basicc B | RAM | cyc | was B | was cyc |
|---|---:|---:|---:|---:|---:|
| add32 | 130 | 18 | 4710 | 128 | 4808 |
| cmpchain | 64 | 6 | 3222 | 62 | 3421 |
| crc8 | 72 | 6 | 6769 | 70 | 6831 |
| div16 | 190 | 17 | 32232 | 188 | 32280 |
| fixmul | 102 | 11 | 5294 | 128 | 7437 |
| mul8 | 70 | 9 | 1906 | 68 | 2004 |
| sum16 | 46 | 6 | 1806 | 44 | 2004 |

`bitbang` and `state` are unchanged. Each counted loop costs a hidden counter byte and two code
bytes where the old compare was already cheap; it wins where the compare was wide (`fixmul`'s
16-bit `Step 7` loop).

## After M5 frame overlay, in-place read-modify-write and the peephole pass, 2026-10-24

| kernel | basicc B | RAM | cyc | was B | was RAM | was cyc |
|---|---:|---:|---:|---:|---:|---:|
| add32 | 108 | 18 | 3610 | 130 | 18 | 4710 |
| bitbang | 34 | 4 | 125 | 34 | 4 | 182 |
| cmpchain | 64 | 6 | 3222 | 64 | 6 | 3222 |
| crc8 | 70 | 6 | 6257 | 72 | 6 | 6769 |
| div16 | 174 | 17 | 31832 | 190 | 17 | 32232 |
| fixmul | 78 | 11 | 3578 | 102 | 11 | 5294 |
| mul8 | 54 | 9 | 1106 | 70 | 9 | 1906 |
| state | 72 | 6 | 1580 | 74 | 5 | 1877 |
| sum16 | 46 | 6 | 1806 | 46 | 6 | 1806 |

Size relative to XC8 `-Os`: median **0.64**, worst 0.81 (crc8). Cycles relative to XC8 `-O2`: median
**0.94**, worst 1.04 (div16); `fixmul` and `mul8` are at or below XC8. The M5 gates above are met.
None of the kernels has more than one routine, so frame overlay does not show here (its test is
`tests/exec/overlay.bas`: sibling routines share storage); the gains are `x = x op <expression>`
folded into the variable (`mul8`, `fixmul`, `add32`) and the peephole pass (dead accumulator
copies, a redundant `xorlw 0` after `andlw`, a branch to the next instruction, repeated `movlw`).

## Why the numbers look like this

* Size is already below XC8 because nothing is emitted that is not used (no runtime, one static
  frame, helpers only when reached) and branches are relaxed to their short forms.
* Cycles lost in the M4 baseline where the generator was naive; M5 added the hardware multiply,
  counted `DECFSZ` loops, in-place updates and the peephole pass (sections above). What is left is
  scratch-to-scratch copies (`movff __C0, __A0`) and the bit-store patterns (PLAN pass 8).

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

## Interrupt with multiply and divide — 2026-10-24

Kernel `isrmuldiv`: 50 passes; each does a 16-bit multiply and a 16-bit divide in the main program,
raises `TMR0IF` in software and waits for the handler, which does a multiply by 5, a divide by 7 and a
`Mod` 13 on its own 16-bit state. The handler therefore runs exactly 50 times in every build, so the
three `sink` values agree (and do). Cycles include the interrupt entry, context save and exit.

| kernel | basicc B | RAM | cyc | XC8 -Os B | RAM | cyc | XC8 -O2 B | RAM | cyc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| isrmuldiv | 464 | 35 | 53456 | 582 | 45 | 51994 | 608 | 45 | 54338 |

Size is 0.80 of XC8 `-Os`; cycles are 0.98 of `-O2` and 1.03 of `-Os`. The C kernel sets `PEIE` as
well as `GIE`: DS40002043F p.199 says the `PIR0` flags (including `TMR0IF`) are not gated by `PEIE`,
but the MDB simulator does not deliver the Timer0 interrupt without it (without it the XC8 build
never leaves its wait loop). basicc's `Enable` sets both bits, so it was not affected.
