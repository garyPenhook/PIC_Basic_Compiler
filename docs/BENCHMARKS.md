# Benchmarks

Produced by `scripts/bench.py` (kernels in `bench/kernels/NAME.bas` and `NAME.c`). Sizes are
program bytes and data-RAM bytes of the whole image including start-up code; cycles are the
simulator's count between two markers (MPLAB X `mdb`, PIC18F27Q10), with the C marker-call
overhead measured on an empty kernel and subtracted. Every kernel leaves a result in `sink`; the
script fails if the three builds disagree. Comparators are used as black boxes (PLAN §2): XC8
v4.00 `-Os` / `-O2`.

**Size correction (0.1.26).** The C kernels need `mark_a()`/`mark_b()` functions and calls that the
BASIC kernels replace with labels: 22 B per kernel (40 B empty harness against 18 B bare `main`).
The tables below dated before 0.1.26 include that and overstate basil's size advantage (total 0.69
there; 0.80 once corrected). `bench.py` now subtracts it from the XC8 sizes (`--raw` keeps it).
The kernels are tiny, written alongside the compiler, and the optimiser was tuned on them, so they
are not an independent sample.

## Baseline — M4, 2026-10-23 (first code generator, no optimisation passes yet)

| kernel | basil B | RAM | cyc | XC8 -Os B | RAM | cyc | XC8 -O2 B | RAM | cyc |
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
24 bytes / 1 byte RAM, another BASIC compiler 32 / 26, **basil 14 / 1** (the start-up `clrf` of `x` goes in M5).

## After M5 hardware multiply, 2026-10-24

| kernel | basil B | RAM | cyc | was cyc |
|---|---:|---:|---:|---:|
| add32 | 128 | 17 | 4808 | 57208 |
| fixmul | 128 | 12 | 7437 | 33463 |

The other kernels are unchanged. `add32` is now 0.26× XC8 `-O2` in cycles; `fixmul` is 1.9×
(its `For` loop and the accumulator traffic remain, M5 `DECFSZ` and peephole items).

## After M5 counted loops, 2026-10-24

| kernel | basil B | RAM | cyc | was B | was cyc |
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

| kernel | basil B | RAM | cyc | was B | was RAM | was cyc |
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

* Size is below XC8 mostly on arithmetic-heavy kernels because nothing is emitted that is not used (no runtime, one static
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

| kernel | basil B | RAM | cyc | XC8 -Os B | RAM | cyc | XC8 -O2 B | RAM | cyc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| isrmuldiv | 464 | 35 | 53456 | 582 | 45 | 51994 | 608 | 45 | 54338 |

Size is 0.80 of XC8 `-Os`; cycles are 0.98 of `-O2` and 1.03 of `-Os`. The C kernel sets `PEIE` as
well as `GIE`: DS40002043F p.199 says the `PIR0` flags (including `TMR0IF`) are not gated by `PEIE`,
but the MDB simulator does not deliver the Timer0 interrupt without it (without it the XC8 build
never leaves its wait loop). basil's `Enable` sets both bits, so it was not affected.

## Re-run at 0.1.25, 2026-10-25

`scripts/bench.py` now builds the basil side with `--keep-vars`. The kernels only write `sink`, and
since 0.1.17 the write-only peephole pass deleted that store (`cmpchain` then left 0 in `sink`
against XC8's 201, a mismatch that looked like a miscompile but was not). XC8 keeps the store, so
`--keep-vars` is the like-for-like build.

| kernel | basil B | RAM | cyc | XC8 -Os B | RAM | cyc | XC8 -O2 B | RAM | cyc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| add32 | 108 | 18 | 3610 | 196 | 21 | 17166 | 218 | 21 | 18350 |
| bitbang | 34 | 4 | 125 | 62 | 3 | 165 | 62 | 3 | 165 |
| cmpchain | 64 | 6 | 3222 | 88 | 5 | 3224 | 88 | 5 | 3224 |
| crc8 | 70 | 6 | 6257 | 86 | 4 | 6376 | 86 | 4 | 6641 |
| div16 | 174 | 17 | 31832 | 292 | 18 | 29380 | 306 | 18 | 30746 |
| fixmul | 78 | 11 | 3578 | 104 | 8 | 3725 | 110 | 8 | 3870 |
| isrmuldiv | 456 | 35 | 53258 | 582 | 45 | 51994 | 608 | 45 | 54338 |
| mul8 | 54 | 9 | 1106 | 97 | 7 | 1109 | 99 | 7 | 1110 |
| state | 72 | 6 | 1580 | 94 | 4 | 1532 | 102 | 4 | 1857 |
| sum16 | 46 | 6 | 1806 | 72 | 6 | 1807 | 74 | 6 | 1808 |

Total flash 1156 B against 1673 B for XC8 `-Os` (0.69; median 0.69, range 0.55 `add32` / `bitbang` to
0.81 `crc8`). Total RAM 118 B against 121 B: basil uses 1-3 bytes more on six kernels, less on
`add32`, `div16` and `isrmuldiv`, and the same on `sum16`. All sinks agree in the three builds.

## Re-run at 0.1.26, 2026-10-25 (XC8 marker scaffolding removed from sizes)

| kernel | basil B | RAM | cyc | XC8 -Os B | RAM | cyc | XC8 -O2 B | RAM | cyc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| add32 | 108 | 18 | 3610 | 174 | 21 | 17166 | 196 | 21 | 18350 |
| bitbang | 34 | 4 | 125 | 40 | 3 | 165 | 40 | 3 | 165 |
| cmpchain | 64 | 6 | 3222 | 66 | 5 | 3224 | 66 | 5 | 3224 |
| crc8 | 70 | 6 | 6257 | 64 | 4 | 6376 | 64 | 4 | 6641 |
| div16 | 174 | 17 | 31832 | 270 | 18 | 29380 | 284 | 18 | 30746 |
| fixmul | 78 | 11 | 3578 | 82 | 8 | 3725 | 88 | 8 | 3870 |
| isrmuldiv | 456 | 35 | 53258 | 560 | 45 | 51994 | 586 | 45 | 54338 |
| mul8 | 54 | 9 | 1106 | 75 | 7 | 1109 | 77 | 7 | 1110 |
| state | 72 | 6 | 1580 | 72 | 4 | 1532 | 80 | 4 | 1857 |
| sum16 | 46 | 6 | 1806 | 50 | 6 | 1807 | 52 | 6 | 1808 |

Total flash 1156 B against 1453 B for XC8 `-Os` (0.80). Per kernel the ratio ranges from 0.62
(`add32`) to 1.09 (`crc8`), median about 0.89; `state` is equal and `crc8` is larger. XC8's own
18 B start-up is left in. Gains are concentrated in `add32`, `div16`, `mul8` and `isrmuldiv`; on
the small control-flow kernels the two compilers are within a few bytes. The "about as fast" claim
holds (cycles unchanged). RAM is not an advantage: basil is 1-3 B larger on six kernels.

## Larger programs, 2026-11-05 (0.1.138) — basil is larger than XC8

Four programs of 1.5 to 3 KB, each written twice (BASIC and C, same algorithms, no libraries, results
forced out through `LATB`/`LATC` or a volatile `sink`), PIC18F27Q10, whole-image program bytes. The final
`sink` value was identical in the simulator for basil and XC8 `-Os` in all four.

| program | basil | XC8 -Os | XC8 -O2 | basil / -Os |
|---|---:|---:|---:|---:|
| algorithms (sorts, CRC16/32, sieve, gcd, isqrt, fib) | 2382 | 1826 | 2062 | 1.30 |
| fixed-point DSP (FIR, PID, RMS, Q15) | 3104 | 2606 | 2878 | 1.19 |
| text formatting and parsing | 1788 | 1738 | 1896 | 1.03 |
| command state machine, matrix, RLE | 1466 | 1390 | 1538 | 1.05 |
| total | 8740 | 7560 | 8374 | 1.16 |

On code of this size basil is 16% larger than XC8 `-Os` and 4% larger than `-O2`, so the small-kernel
advantage above does not generalise. The loss is largest on 32-bit loops and 16-bit `Mod`.

### After L1/L2 (0.1.139) and L6/L3 (0.1.140)

Same four programs, program bytes; the simulator `sink` still matches XC8 `-Os` in all four.

| program | 0.1.138 | 0.1.139 | 0.1.140 | XC8 -Os | basil / -Os |
|---|---:|---:|---:|---:|---:|
| algorithms | 2382 | 2280 | 2248 | 1826 | 1.23 |
| fixed-point DSP | 3104 | 3102 | 3090 | 2606 | 1.19 |
| text formatting and parsing | 1788 | 1786 | 1770 | 1738 | 1.02 |
| command state machine | 1466 | 1464 | 1448 | 1390 | 1.04 |
| total | 8740 | 8632 | 8556 | 7560 | 1.13 |

0.1.141 (element reuse): algorithms 2238, total 8546 (1.13 of `-Os`); the bubble-sort swap no longer reloads
`data(j)` and `data(j+1)`, and the algorithms program runs in 87997 cycles instead of 92060.

0.1.142 (16x16 signed multiply): `Integer * Integer` widened to `LongInt` (`acc + v*v`, `acc + a*b`) calls
`__smul4`, four hardware multiplies, instead of `__mul4`; fixed-point DSP program 3090 to 3082 bytes
(larger-program total 8546 to about 8538), and each such multiply is faster.

0.1.143 (shared sum): `If acc >= r + b Then acc = acc - (r + b)` builds `r + b` in `__A` once; the second copy goes when
nothing in between writes `__A` or either operand. Fixed-point DSP program 3082 to 3050 bytes (1541 to 1525 words).

0.1.156 (M1/M2, `docs/EFFICIENCY.md` §10): a call on the right of an operator no longer makes the left variable be
saved first when the callee cannot write it, and `x = (x op a) op b …` (constant shifts allowed) is worked out in
`x` itself. Program bytes, simulator `sink` equal to XC8 `-Os` in all four:

| program | 0.1.155 | 0.1.156 | XC8 -Os | basil / -Os |
|---|---:|---:|---:|---:|
| algorithms | 2206 | 1742 | 1826 | 0.95 |
| fixed-point DSP | 3036 | 2746 | 2606 | 1.05 |
| text formatting and parsing | 1746 | 1624 | 1738 | 0.93 |
| command state machine | 1442 | 1284 | 1390 | 0.92 |
| total | 8430 | 7396 | 7560 | 0.98 |

0.1.157 (M3/M4): a routine ending `Result = v` returns in `v`, and entry clears of locals that are never read before
being written go. Total 7396 to 7244 bytes (algorithms 1670, fixed-point DSP 2722, text 1602, command state machine
1250; 0.96 of XC8 `-Os`), `sink` unchanged in all four.

0.1.158 (M5/M6): zero-extended values stored without `__A`, constant hidden loop limits folded, entry tests that cannot
fail dropped. Total 7244 to 7124 bytes (algorithms 1618, fixed-point DSP 2722, text 1540, command state machine 1244;
0.94 of XC8 `-Os`), `sink` unchanged in all four.

0.1.159 (M7/M8): constant multiplies read a plain multiplicand where it is, and array stores of a staged byte read the
source directly. Total 7124 to 7092 bytes (algorithms 1598, fixed-point DSP 2714, text 1536, command state machine
1244; 0.94 of XC8 `-Os`), `sink` unchanged in all four.
