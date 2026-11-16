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

## Larger programs after review 3, 2026-11-12 (0.1.190)

`bench/large/run.sh`, flash in bytes, PIC18F27Q10, XC8 v4.00. Sinks equal to the `-Os` values in basil-sim.

| program | basil 0.1.181 | basil 0.1.190 | XC8 -Os | XC8 -O2 | basil vs -Os |
|---|---:|---:|---:|---:|---:|
| a_algo | 1592 | 1376 | 1826 | 2062 | 0.75 |
| b_dsp | 2662 | 2376 | 2606 | 2878 | 0.91 |
| c_text | 1520 | 1300 | 1738 | 1896 | 0.75 |
| d_ctrl | 1240 | 1128 | 1390 | 1538 | 0.81 |
| total | 7014 | 6180 | 7560 | 8374 | 0.82 |

Cycles to `__halt` (basil-sim): a_algo 83372 -> 75801, b_dsp 84200 -> 78275, c_text 60199 -> 37762, d_ctrl 35917 -> 27285.
The same sources for the PIC16F18346: 5135 -> 4685 words. What changed is listed in `docs/EFFICIENCY.md` section 12.4.


## Larger programs after the 0.1.191 passes, 2026-11-12 (0.1.192)

Same setup as above. Flash in bytes, PIC18F27Q10; the 16F column is words, PIC16F18346.

| program | basil 0.1.190 | basil 0.1.191 | XC8 -Os | basil vs -Os | 16F 0.1.190 | 16F 0.1.191 |
|---|---:|---:|---:|---:|---:|---:|
| a_algo | 1376 | 1338 | 1826 | 0.73 | | 960 |
| b_dsp | 2376 | 2364 | 2606 | 0.91 | | 1738 |
| c_text | 1300 | 1296 | 1738 | 0.75 | | 1017 |
| d_ctrl | 1128 | 1120 | 1390 | 0.81 | | 938 |
| total | 6180 | 6118 | 7560 | 0.81 | 4685 | 4653 |

Sinks equal in basil-sim (PIC18) and MDB (PIC16F17146). Cycles, `bench/kernels` and `bench/random` were not
re-measured for this step; the kernel table above is from before review 3.


## Peripheral-module programs, 2026-11-12 (0.1.199, 0.1.200, 0.1.201)

`bench/modules/m1..m4`: four programs that call the library modules (`gpio`, `pinio`, `serial`, `adc`, `eeprom`,
`timer`, `i2c`, `spi`, `pwm`, `shift`), each with an XC8 twin written at register level (XC8 has no peripheral
library). `bench/modules/cmp.sh` builds all of them. PIC18F27Q10, 64 MHz, XC8 v4.00. Flash and data RAM in bytes
(basil: words x 2 and the RAM total of `--report`; XC8: the "Program space" and "Data space" lines).

| program | modules | basil 0.1.199 | 0.1.200 | 0.1.201 | RAM | XC8 -Os | RAM | XC8 -O2 | RAM | 0.1.201 / -Os |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| m1_logger | gpio serial adc eeprom timer | 1158 | 1150 | 1150 | 43 | 1439 | 45 | 1539 | 45 | 0.80 |
| m2_i2cnode | gpio pinio serial i2c timer | 1340 | 1288 | 1288 | 44 | 1366 | 45 | 1478 | 46 | 0.94 |
| m3_motor | gpio pinio adc pwm shift eeprom timer | 1896 | 1794 | 1542 | 50 | 1573 | 56 | 1701 | 56 | 0.98 |
| m4_spiflash | gpio pinio spi serial eeprom timer | 1066 | 976 | 976 | 24 | 924 | 25 | 998 | 26 | 1.06 |
| total | | 5460 | 5208 | 4956 | 161 | 5302 | 171 | 5716 | 172 | 0.93 |

0.1.199 was 3% larger than XC8 `-Os` in total; 0.1.200 (constant-argument copies of routines,
`docs/EFFICIENCY.md` section 13) is 2% smaller; 0.1.201 (the `pwm` library, below) is 7% smaller, and 13% smaller
than `-O2`. RAM is within a few bytes everywhere, and 10 bytes under XC8 in total.

Read this with the following in mind:

* The programs were **built, not run**. The C twins use the register sequences of the library modules (checked
  against DS40002043F, e.g. PPS output codes TX1 09h, CCP1 05h, CCP2 06h, MSSP1 SCK/SCL 0Fh, SDO/SDA 10h, p.287) and
  compile against the device pack's headers, but nothing compared their behaviour in the simulator.
* The library does more than the twins: pin numbers are run-time arguments and are validated, `PwmStart` handles four
  channel types and polarity, bus routines time out and return a status. The C twins have fixed pins, and the same
  bounded waits and status codes for the I2C and SPI paths. A C twin without that generality would be smaller still;
  a basil program that wrote the registers itself would be too.
* Where the C leaves a PPS input at its power-on default (RX1PPS, SSP1CLKPPS, SSP1DATPPS) it still writes it, as the
  library does; leaving those out would save about a dozen bytes per program.
* `m3_motor` was the one loss (1794 against 1573 at 0.1.200) and is fixed in the library, not the compiler (0.1.201,
  1542 bytes, 50 bytes of RAM; the twin has 56): `PwmStart` no longer writes `CCPTMRS` on the Q10 (all four fields
  reset to Timer2, DS40002043F p.359 and p.367: -20 words), restarts a running channel by releasing only a pin it
  leaves instead of an inlined `PwmStop` (-20 words), and `PwmPercent` works out `(PwmSteps / 4) * pct / 25` in a Word
  instead of `PwmSteps * pct / 100` in a LongWord (the two are equal because `PwmSteps` is `4 * n`, `n <= 256`), which
  drops the 32-bit multiply and divide (-86 words). `tests/exec/lib_pwm_pct` pins the duty register for several
  percentages. What is left against XC8 is `PwmStart` at 212 words (it validates a run-time pin and checks the other
  channels' pins) and the routines that take pin numbers (`Pinio`, `Shift`).

## Larger programs and library tests, 0.1.200, 2026-11-12

`bench/large/run.sh`, flash in bytes, PIC18F27Q10, XC8 v4.00 (`-Os`); the 16F column is words, PIC16F18346. Sinks are
equal to the `-Os` values in basil-sim (PIC18) and MDB (PIC16F17146).

| program | basil 0.1.199 | basil 0.1.200 | XC8 -Os | basil vs -Os |
|---|---:|---:|---:|---:|
| a_algo | 1314 | 1314 | 1826 | 0.72 |
| b_dsp | 2292 | 2038 | 2606 | 0.78 |
| c_text | 1296 | 1296 | 1738 | 0.75 |
| d_ctrl | 1108 | 1108 | 1390 | 0.80 |
| total | 6010 | 5756 | 7560 | 0.76 |
| 16F18346, words | 4617 | 4539 | | |

Library test programs that call routines with differing constants shrank the most (words, PIC18F27Q10):
`lib_spi` 547 to 357, `lib_i2c` 650 to 437, `lib_pulse` 832 to 730, `lib_bits` 510 to 452, `lib_system` 460 to 396,
`lib_floatlib_cmp` 2178 to 1702, `lib_pwm_out` 314 to 282. None grew (the pass only keeps a change that builds smaller).

Compile time: a program with a routine called with differing constants costs up to 12 more trial builds (a few
seconds for the largest library test, `lib_glcd`: 1.3 s to 9 s); a program with nothing to copy, or an IR larger than
4000 nodes (`tests/programs/library_all.bas`), costs nothing.

## PIC16 bank placement trial (2026-11-15)

Compared with `da4b7da`, using the same optimized sources and PIC16F18346:

| `bench/large` | Flash words before | Flash words after |
|---|---:|---:|
| a_algo | 911 | 911 |
| b_dsp | 1594 | 1594 |
| c_text | 1005 | 1005 |
| d_ctrl | 891 | 861 |
| Total | 4401 | 4371 |

`d_ctrl` keeps 237 reported RAM bytes; bank-selection instructions decrease from 43 to 31, and basil-sim cycles
from 37905 to 37158. Its sink remains 67006, also checked in the `-O0` reference build and on PIC16F17146.
The other three optimized programs pass their simulator expectations. Ten generated PIC16 programs (seeds
1–10, 25 operations) remain at 5243 total words, with no individual flash or reported RAM regression. This is a
measured improvement for the control benchmark, not a general percentage claim. See EFFICIENCY.md §15 for the
placement algorithm, acceptance check and limits.

## Proven local-array initialization (2026-11-15)

Compared with `fae23d5`, using `tests/exec/array_init.bas` and storage optimizations enabled:

| Target | Flash words before → after | RAM before → after | basil-sim cycles before → after |
|---|---:|---:|---:|
| PIC18F27Q10 | 148 → 138 | 47 → 47 bytes | 1208 → 1074 |
| PIC16F17146 | 193 → 181 | 52 → 52 bytes | 1652 → 1516 |

The initialized arrays lose their entry clears; a partially initialized sibling array retains its clear and
reads zero from its unwritten element after frame reuse. Results match the baseline and `-O0` builds on both
cores. All four `bench/large` image sizes and reported RAM totals remain unchanged on PIC18F27Q10 and PIC16F18346.
This is a focused result, not a general reduction claim. See EFFICIENCY.md §16 for proof limits and repeatable
simulator commands using the harness's new `--no-keep-vars` option.

## Current local build versus XC8 v4.00 (2026-11-15)

Latest local release: `fae23d5` plus the uncommitted array-initialization pass, version 0.1.256. The local basil symlink was verified after a release rebuild. Exact binary SHA-256: `c6946821696fa30c4e5593716f8815d1f67fcfa710740fde345721581ebc4f45`.

target/benchmarks/latest/report.md contains the full tables, methodology and raw-artifact locations. Suite totals below use bytes for PIC18 flash and instruction words for PIC16; RAM is summed per-program bytes. Negative differences favour Basil.

| Suite | Device | Flash Basil / XC8 -Os | Flash difference | RAM difference |
|---|---:|---:|---:|---:|
| large | 18F27Q10 | 5752 / 7560 B | -23.9% | -5.1% |
| large | 16F18346 | 4371 / 4337 words | +0.8% | -3.2% |
| modules | 18F27Q10 | 4658 / 5302 B | -12.1% | -7.6% |
| random | 18F27Q10 | 8908 / 9606 B | -7.3% | +7.9% |
| random | 16F18346 | 5243 / 5765 words | -9.1% | +6.2% |
| kernels | 18F27Q10 | 1538 / 2165 B | -29.0% | -9.1% |

The large-program cycle totals (including startup) are:

| Device | Basil | XC8 -Os | XC8 -O2 | vs -Os | vs -O2 |
|---|---:|---:|---:|---:|---:|
| 18F27Q10 | 201016 | 525513 | 484339 | -61.7% | -58.5% |
| 16F18346 | 466081 | 540075 | 640111 | -13.7% | -27.2% |

All 24 large-program executions match their expected sinks in basil-sim. All 33 PIC18 kernel binaries also match their sinks in an independent basil-sim run. The established MPLAB X v6.35 harness measures kernel intervals, with marker scaffold/call costs removed: Basil is smaller on every kernel and faster on 8/11 versus -Os, 9/11 versus -O2.

Random tests use seeds 1–10, 25 operations, on each device. Peripheral and random comparisons are size-only; hardware behaviour was not revalidated. These repository-owned integer/peripheral sources are not an independent benchmark sample, and the results are not a general guarantee. Notable limits: PIC16 b_dsp uses 1594 words versus 1458 for XC8 -Os, and random-program RAM totals favour XC8 despite Basil flash savings.

## PIC16 code pages versus table pages (2026-11-16)

First flash-placement step: omit blanket page selections when the entire executable program fits in the reset
page and neither typed code nor verified assembly can change or observe the page latch. Tables may extend into
later pages. The conservative assembler remains the fallback; general latch-flow analysis and routine reordering
are not yet implemented. See EFFICIENCY.md §17 for the full improvement plan and proof limits.

`tests/exec_p16/float_random.bas`, PIC16F17146, compared with the local release immediately before this step:

| Build | Flash words before → after | RAM before → after | `movlp` before → after |
|---|---:|---:|---:|
| Optimized | 3991 → 3969 | 36 → 36 bytes | 22 → 0 |
| Harness with observed counters (`--keep-vars`) | 3999 → 3977 | 38 → 38 bytes | 22 → 0 |

In basil-sim the observed-counter build improves from 162122 to 161332 cycles. Both error counters remain zero,
as in the baseline and `-O0` reference. A generated 2100-NOP cross-page case retains paging and remains at 2185
words and 4314 cycles, with expected result 110. These are focused measurements; the existing four large PIC16
benchmarks are below the paging threshold and are not expected to benefit from this step.

The Timer0 interrupt regression extended with a 2050-byte table also passes in baseline, optimized and `-O0`
builds. Its image is 2658 → 2651 words with 100 RAM bytes unchanged. Timer phase changes total execution cycles
from 142864 to 143126 despite fewer instructions; this pass guarantees the page invariant, not a universal timing
improvement. All eight large-program builds retain their flash and RAM totals.

## PIC16 DSP addresses, call-local reuse and page tracking (2026-11-16)

Measured from the local build at the start of this work, with the same benchmark sources and XC8 reference:

| PIC16F18346 | Before words | After words | Reported RAM before / after |
|---|---:|---:|---:|
| a_algo | 911 | 911 | unchanged |
| b_dsp | 1594 | 1525 | 164 / 164 bytes |
| c_text | 1005 | 1005 | unchanged |
| d_ctrl | 861 | 859 | 237 / 237 bytes |
| Total | 4371 | 4300 | unchanged |

DSP remains 67 words (4.6%) larger than XC8 -Os's recorded 1458 words, down from 136 words (9.3%). Savings
come from full-width doubled-Byte array addresses and Word-array walking, without page-placement changes.
All four optimized PIC16 sinks pass in basil-sim. PIC18 large-program flash remains 5752 bytes.

Extending phase-local storage reuse to known calls saves two bytes in `local_reuse_calls.bas` on PIC18
(20 → 18 reported bytes, unchanged 72 words) and PIC16F17146 (27 → 25 bytes, unchanged 114 words). Seeds 1–10 of the existing 25-operation random suite show no
additional saving from this extension: PIC18 4454 words / 453 reported RAM bytes and PIC16 5243 words / 463
reported RAM bytes, unchanged. The random RAM gap remains open.

Guarded PCLATH page-bit tracking reduces a generated cross-page A/B-call fixture from 2202 to 2200 words
and five to three selections, retaining 10 RAM bytes. Basil-sim returns 133 for baseline, optimized and `-O0`;
cycles are 4343 → 4341 for baseline/optimized. This fixture includes a 2100-NOP routine, repeated calls into
page one, and calls selecting page zero after a return from page one. It is a focused result. See EFFICIENCY.md
§§19–21 for mechanisms, fallbacks and validation limits.

Validation: 145 unit tests and the 75-test backend suite pass, along with the additional call-storage
backend regression. The PIC18 optimized and `-O0` simulator gates pass (227 execution programs plus
library models). The full PIC16 gate exposes an existing `lib_timer_hw` expectation mismatch:
`LTH_R7` expects 188 but reports 184, reproduced with the baseline binary in both optimized and `-O0`
builds. This is not counted as a passing PIC16 timer check.
With that already-failing timer fixture excluded, all 120 remaining PIC16 execution programs pass in both
optimized and `-O0` builds. The new Word-array and call-storage fixtures also pass with storage trials enabled.
The manual's optimisation section and its regenerated PDF cover both reset-page elimination and guarded
multipage tracking, including assembly/alias fallbacks and inspection commands.
