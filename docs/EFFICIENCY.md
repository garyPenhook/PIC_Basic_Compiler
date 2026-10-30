# Efficiency opportunities in math and other operations

Analysis of basil 0.1.35, PIC18 back end, from the integer types up to `Float`. Nothing in this file is
implemented yet: it is the worklist for the next optimisation passes (PLAN §7A.3), ordered by payoff. Goal 4 of
the plan applies: one word saved is worth saving.

## 1. Method, and how far to trust the numbers

* **Code shape** comes from `basil -S --keep-vars` on one-statement probes (PIC18F27Q10, access-bank variables
  unless a section says otherwise). "Words" are instruction words in the emitted `.S` (a `movff`, `call`, `lfsr`
  is 2 words, everything else 1; 1 word = 2 bytes of flash).
* **Cycles** are the MDB simulator's stopwatch between two `Asm` marker labels, one execution of the statement
  (the harness is the same as `scripts/bench.py`'s). "Before" is basil's current output; "after" is a hand-written
  `Asm` block of the proposed sequence, run in the same harness. Every "after" result was compared with the value
  the current compiler produces (edge values listed where they matter). Image sizes from the linker include
  unrelated start-up code, so savings below are counted from the instruction listings, not from image deltas.
* **Arithmetic constants** (division by reciprocal multiply) were checked exhaustively on the host
  (every 8-bit and 16-bit dividend) and the generated sequence was run in the simulator.
* **Datasheet facts** used, confirmed in the data sheets (DS40002043F = PIC18-Q10, DS40002242F/214G = PIC18-Q41):
  `SUBWFB` affects N, OV, C, DC, Z (DS40002043F p.674); `PLUSWx` adds the *signed* value of W to FSRx
  (DS40002043F §11.4.3.2 p.121); `CPFSGT`/`CPFSLT` compare unsigned (DS40002242F p.827-828); `NEGF` affects
  N, OV, C, DC, Z (DS40002043F p.626). `MULLW`, `MOVFF`, `PLUSW` and the signed flags are PIC18 features: a future
  PIC16-enhanced back end (`pic16e`, not built yet) needs its own cost table; the PIC16F17126's `SUBWFB` has no
  N or OV (DS40002343F p.607).
* **Not measured** items are marked *(counted)*: instruction counts only.

## 2. Ranked summary

| # | Where | Change | Flash | Cycles | RAM | Risk |
|---|---|---|---|---|---|---|
| P1 | Word/Long `+ - And Or Xor` into a *different* destination | route bytes through W (`movf/addwf/movwf`) instead of `__A` copy-in/copy-out (**done, 0.1.56**) | 16-bit −6 words, 32-bit −12 words per op | 12→6, 24→12 | 0 | low |
| P2 | Word/Long shifts, `* 2^k`, `/ 2^k` on a variable | shift in place; byte moves for k ≥ 8; a counted loop instead of nibble swaps for k = 4 (**done, 0.1.57**) | `x<<1` 11→3 words; `x<<4` 15→9 | 11→3; 33→9 | 0 | low |
| P3 | Result forwarding (`movff __C,__A` / `movff __A,dst`) | store the producer's register straight to the destination (**done, 0.1.58**) | −4 words per multiply/array read/shift | −4 | 0 | low |
| P4 | Division and `Mod` by a constant | reciprocal multiply, verified exhaustively at compile time (**Byte done, 0.1.59**; **Word done under `Optimize = Speed`, 0.1.60**; Long not yet) | Byte `/10`: 7 words, no helper | 120→7 (Byte), 314→41 (Word) | 0 | medium |
| P5 | `/` and `Mod` of the same operands | one helper call serves both | −1 call | 634→315 | 0 | low |
| P6 | `lib` decimal printing (`LcdWriteWord`, `Serial2WriteWord`, …) | table-driven repeated subtraction | −68 B (5-digit test) | 5109→439 | 0 | low |
| P7 | `Min`, `Max`, `Abs` | skip-instruction forms (`CPFSGT`/`CPFSLT`, sign test) (**Byte `Min`/`Max` done, 0.1.61**; **ShortInt `Abs` done, 0.1.62**; **signed Byte and 16/32-bit `Abs`, `Min`, `Max` done, 0.1.64**) | Byte Min/Max 14→4 words; Integer `Abs` 44→6 | 14→4; 44→6 | −1..2 B temp | low |
| P8 | Byte-indexed array access | `lfsr` + `PLUSW0` (arrays ≤ 128 elements) (**done for one-byte elements, 0.1.62**) | 12→4 words | 13→5 | 0 | low |
| P9 | Float helpers | pass operands and result in `__A`/`__B` like `__mul4` (**done, 0.1.54**; `FMul`/`FDiv` bodies 0.1.55) | PIC18 `float_basic` 1281→1111 words; 16F17146 1598→1178 | −24 per op; `FMul` −27/−8, `FDiv` −8/−8 once (PIC18/mid-range) | −61 B | medium |
| P10 | `Float * 2^k`, `/ 2^k` | exponent add, no `FMul`/`FDiv` | −345 words when they were the only users | 218→≈20 | −12 B | medium |
| P11 | Signed compare | fold constant bias; sign-bit test against 0 (**done, 0.1.62**) | `i<0` 13→2 words; `i<K` 11→8 | 13→3 (`i<0`) | −2 B scratch | low |
| P12 | Word `± 1`, constant compares | `infsnz/incf`, `decf/btfss`, `subfwb` | `x+1` 4→2; `x>K` 9→5 | 4→2; 11→7 | 0 | low |
| P13 | `FDiv` | 26 quotient bits instead of 32 | 0 | 1010→≈820 | 0 | medium |

Everything in the table applies to code in the Access Bank; see §3.6 for banked variables.

## 3. Integers

### 3.1 Byte (and ShortInt)

Already tight and left alone: `a + b`, `a And/Or/Xor`, `a * b` and `a * K` (`MULWF`/`MULLW`), `a << k` (repeated
`ADDWF WREG` for small k, `MULLW` beyond), `a >> 4` (`SWAPF`+mask), `a Mod 2^k`, `a / 2^k`, compare chains, `a = a + 1` (`INCF`).

| Finding | Now | Proposed | Measured |
|---|---|---|---|
| **B1** `c = a - b` is computed reversed and negated: `movf a,w; subwf b,w; sublw 0` | 4 words | `movf b,w; subwf a,w` | 4→3 cycles |
| **B2** `Min(a,b)`/`Max(a,b)` use a branch-free mask with a hidden temp (`__main__TMP`) and a `movlw 1/0` flag | 14 words | `movf b,w; cpfsgt a; movf a,w` (Min), `cpfslt` (Max): skip-instruction select | 14→4 and 13→4 cycles; Min(5,9)=5 and Max(5,9)=9 checked |
| **B3** `Abs(sb)` | 17 words | `movf sb,w; btfsc sb,7; negf WREG` | 17→4 cycles; −5→5, 7→7, −128→128 |
| **B4** `a / K`, `a Mod K` through `__div1` (8-iteration loop) | 118-122 cycles | `a/10 = (a·205)>>11`: `movf a,w; mullw 205; rrncf PRODH,w; rrncf WREG,w; rrncf WREG,w; andlw 0x1F` (7 words with the store); `Mod` adds `mullw K; movf PRODL,w; subwf a,w` | /10: 120→7; Mod 10: 122→10; a=200 checked |
| **B5** `a Mod b` result path: `movff __C0,__A0; movf __A0,w` | 3 words | `movf __C0,w` | counted |
| **B6** `a >> 1` is `movf a,w; rrncf WREG,w; andlw 0x7F` | 3 words | `bcf STATUS,0; rrcf a,w` | 4→3 cycles; 201→100 |
| **B7** `c = -a` with a *Byte* target is evaluated in 16 bits | 9 words | `movf a,w; sublw 0` (the ShortInt case already does this) | counted |

B4 detail. For unsigned `n < 2^W` and a divisor `k`, `n/k = (n·m)>>s` exactly when `m = ceil(2^s/k)` fits the
multiplier width; a host search over every dividend found a single-byte multiplier for **199 of the 254** byte
divisors (k = 3: 171,9; 5: 205,10; 10: 205,11; 100: 41,12) and a single-word multiplier for **652 of 1024** word
divisors up to 1024 (10: 52429,19; 3: 43691,17). Divisors that fail (7, 11, 14, 21 … for bytes; 7, 100, 1000 … for
words) need a 17th multiplier bit (add-back) or a pre-shift of an even divisor (`/100 = (x>>2)/25`); the compiler
should run the exhaustive check at compile time (256 or 65536 cases) and fall back to the helper when no cheap
form exists. A reciprocal sequence also removes `__div1` (18 words) from programs whose only divisions are by
constants.

### 3.2 Word and Integer

| Finding | Now | Proposed | Measured |
|---|---|---|---|
| **W1** (**done, 0.1.56**) three-address `w = x + y` copies both operands into `__A`, operates, and copies back | 12 words | `movf x,w; addwf y,w; movwf w; movf x+1,w; addwfc y+1,w; movwf w+1` (Sub: `subwf`/`subwfb` with the operand order fixed as in B1; And/Or/Xor the same, no carry) | 12→6 cycles; 1000+234=1234 |
| **W2** (**done, 0.1.57**) `x = x << 1`, `x >> 1`, `x * 2`, `x / 2` go through `__A` | 11 words | `bcf STATUS,0; rlcf x; rlcf x+1` (`rrcf` high-to-low for right) | 11→3 cycles; 1001→2002, 500 |
| **W3** `x << 4` / `x >> 4` use the generic loop | 15 words, 33 cycles | nibble swap: `swapf hi,f; movlw 0xF0; andwf hi,f; swapf lo,f; movlw 0x0F; andwf lo,w; iorwf hi,f; movlw 0xF0; andwf lo,f` | 33→9; 1001<<4=16016 |
| **W4** `x >> 8`, `x << 8`, `x And 255`, `x / 256`, `x Mod 256` stage through `__A1` | 5 words | `movff x+1,x; clrf x+1` and the like | 5→3 cycles; 1001>>8=3 |
| **W5** (**done, 0.1.65**) `x = x + 1` / `x = x - 1` | 4 words | `infsnz x,f; incf x+1,f` and `decf x,f; btfss STATUS,0; decf x+1,f` | +1: 4→2 (255→256, 65535→0); −1: 4→3 (256→255, 0→65535, 5→4) |
| **W6** `x * K` (K constant) ends with `movff __C0,__A0; movff __C1,__A1` before the store | 18 words | store `PRODL`-derived bytes straight to the destination | 18→13 cycles (`x*10`, 123→1230) |
| **W7** `x > K`, `x >= K` stage K into `__B0:__B0+1` first | 9 words | `movf x,w; sublw lo; movlw hi; subfwb x+1,w; bc/bnc` | 11→7 cycles; 1500>1000 |
| **W8** `x >= 256`, `x > 255`, `x < 256` (byte-boundary compares) | 7-9 words | `movf x+1,f; bnz/bz` (2 words) | counted |
| **W9** `x = 0` / `x <> 0` tests byte by byte | 4 words (Word), 8 (Long) | `movf x,w; iorwf x+1,w; bnz` (3 / 5 words) | counted; a few cycles slower on the early-exit path, so size-only: apply under `Optimize = Size` |
| **W10** `i / 2^k` (**done for `/`, k = 1..8, 0.1.63; `Mod` 0.1.64**), `i Mod 2^k` for signed types call `__sdiv2` | 344-348 cycles | `i/2`: `rlcf i+1,w; movlw 0; addwfc i; addwfc i+1; rlcf i+1,w; rrcf i+1; rrcf i` (7 words); general k: add `(i>>15) And (2^k-1)` then arithmetic shift | 348→7; −1234→−617, −1→0, −32768→−16384, 32767→16383, 1235→617 |
| **W11** `x = a * 256 + b`, `(a << 8) Or b`: the "pack two bytes" idiom | 11 words | `movff a,x+1; movff b,x` | counted |
| **W12** (**done, 0.1.64**) `Abs(i)`, `Min(i,j)`, `Max(i,j)` use the mask trick with 16-bit negations and `__main__TMP` | `Abs` 44 words, `Min`/`Max` ≈55 | `Abs`: `btfss i+1,7; bra end; comf i+1,f; negf i; movlw 0; addwfc i+1,f` (6 words); Min/Max: signed compare (P11) and a conditional 2-byte move (≈14 words) | Abs 44→6 cycles (−1234→1234); Min unmeasured *(counted)* |

W1's conditions: the destination may equal either source (byte *i* is written only after byte *i* of both sources
is read, and carries only move upward), but a destination that *partially* overlaps a source through an alias view
(`.Byte1` aliasing and the like) must fall back to the current path; a narrower operand supplies `movlw 0`
for its missing bytes (`x + a`: `movlw 0; addwfc x+1,w`).

### 3.3 LongWord and LongInt

All Word findings scale up: W1 saves 12 words per 32-bit add/sub/logic (**24→12 cycles**, 100000+234567=334567),
W2 saves 4 words per in-place bit shift and `<< 8/16/24` becomes byte moves:

* `l1 = l1 << 8`: 15 words today, `movff l2,l3; movff l1,l2; movff l0,l1; clrf l0` = 7 words.
* `l1 = l1 >> 16`: 10 words today, 6 after (`movff l2,l0; movff l3,l1; clrf l2; clrf l3`).
* `s1 = i` (sign-extend): 17 words, 9 when written straight into the destination.
* `l3 = l1 * 10` (42 cycles) is fine; only P3's forwarding applies (−4 words).
* `l1 = l1 + 1`: 6 words today. `infsnz` chains do not extend past 16 bits without branches (7 words worst case), so leave it.

Helper costs for reference (simulator, one call each): `__div4` 929 cycles (4000000000 / 7), signed `s1 / 10` 1048,
`__mul4` 94, `Word * Word` 34, `Byte * Byte → Word` 6. The 32-bit divide is the one place a larger algorithm may
pay off (skip leading zero bytes of the dividend: a dividend that fits 16 bits finishes in about half the time).

### 3.4 Division helpers and the number-printing libraries

* **Quotient and remainder come out of one `__divN` call** (quotient in `__A`, remainder in `__C`), but `q = v / d`
  followed by `r = v Mod d` calls it twice: 634 cycles measured against 315 for one call. A value-numbering step on
  (operands, op class) lets the second statement read `__C`. Library digit loops (`v / d`, `v Mod d`, `d / 10`) pay
  three divisions per digit today.
* **`lib/lcd.bas`, `lib/serial2.bas` (and the same pattern in other `*WriteWord`)**: a table of the five powers of
  ten with repeated subtraction measures **5109 cycles → 439** for printing 54321 (214 B → 146 B image in the
  harness). The shape, no compiler change needed:

  ```
  Const T(5) As Word = (10000, 1000, 100, 10, 1)
  For a = 0 To 4
      c = 0
      w = T(a)
      While x >= w
          x = x - w
          c = c + 1
      Wend
      ' emit digit c
  Next
  ```
* **A shared constant helper beats inlining for repeated use.** The inline `x / 10` for Word (4 `MULLW`, a 3-bit
  right shift: 41 cycles against 314) is 41 words per site against 12 words for a call plus the 28-word `__div2`
  that is usually linked anyway (one inline site costs about the same as one call plus the helper). Emit it as a shared `__divk`-style helper per constant when there are two or more sites
  and inline it for one site only under `Optimize = Speed`. Word divisors checked: 10 (multiplier 0xCCCD, shift 19;
  54321→5432, 65535→6553, 9→0 in the simulator).
* **Dividend or divisor that fits a byte**: the 16-bit loop (16 iterations of 4 `rlcf` and a 2-byte compare,
  about 19.5 cycles each) can keep an 8-bit remainder and skip the high-byte compare. Not measured; estimated at
  35-40 % fewer cycles for `Word / Byte-constant` when the reciprocal form does not apply.

### 3.5 Arrays and loops

| Finding | Now | Proposed | Measured |
|---|---|---|---|
| **A1** `c = arr(a)`, `arr(a) = b` for a Byte index build a 16-bit address in `__A`, add the base, copy it to `FSR0` | 12 words | `lfsr 0,arr; movf a,w; movf PLUSW0,w` (`PLUSW0` offsets by the *signed* W, so valid only when the array has ≤ 128 elements; elements beyond that keep the current path) | 13→5; 77 read back |
| **A2** read-modify-write `arr(a) = arr(a) + 1` computes the address twice and parks the value in `__main__TMP` | 27 words | `lfsr 0,arr; movf a,w; incf PLUSW0,f` | 27→4 cycles; −1 B temp |
| **A3** Word arrays, `x = warr(a)`: `movff POSTINC0,__A0; movff POSTINC0,__A1; movff __A0,x; movff __A1,x+1` | 8 words | `movff POSTINC0,x; movff POSTINC0,x+1` (P3) | counted |
| **A4** Word index doubling (`rlcf` through `__A`, 16-bit add) | ≈14 words | `movf a,w; addwf WREG,w` then `PLUSW0` while `a < 64`; keep `FSR0` loaded across several accesses to the same array | counted |
| **L1** counted `For` loop with a Byte variable | `clrf v; movlw n; movwf H; … dcfsnz H; bra; incf v; bra` + 1 hidden byte | when the body never reads `v`, count with `v` itself (no hidden byte); otherwise unchanged | counted |

`For x = 0 To 999` on a Word variable already uses `infsnz/incf` for the increment, so W5 only needs to reuse that
for `x = x + 1` statements.

### 3.6 Banked variables

Everything above is written for Access Bank operands. `MOVFF` takes a 12-bit address and needs no bank
select, while `movf/addwf/movwf` need `BSR`. The code generator already tracks `BSR` per block (`same_bank`), so
the rule for P1/P2/W5 is: use the W-routed form when every operand is in the Access Bank or all in the bank that is
already selected; otherwise count the extra `movlb` (1 word, only when the bank changes) against the 6-word saving
per 16-bit op and pick the cheaper. Variable allocation that puts the hot operands of one statement in the same
bank makes the W-routed form win more often.

## 4. Signed comparisons

The generated code biases both high bytes with `xorlw 0x80` into `__D2`/`__D3` and then subtracts unsigned:

* `If i < 10` is 10 words plus the branch because the constant side executes `movlw 0; xorlw 0x80; movwf __D3; movlw 0x0A`
  at run time. Folding the bias into the immediate (`movlw 0x80`) and comparing directly drops it to 7 words and
  frees `__D3`.
* `If i < 0`, `i >= 0`: 13 words → `btfss/btfsc i+1,7` and the branch (2 words) (measured 13→3 cycles with the flag materialised
  as `clrf c; btfsc i+1,7; incf c`). `If sb < 0` (8-bit) likewise: 6 words → 2 (`btfss sb,7` and the branch).
* `If i > 0`, `i <= 0`: sign test plus `movf i,w; iorwf i+1,w` ≈ 4 words against 14.
* Freeing `__D2`/`__D3` lets `__D` stay at the 2 bytes the shift counters need in programs that have no other
  user of `__D3`.

**Do not "fix" the biasing with the N/OV flags of `SUBWFB` yet.** The comment in `ord_jump` says the overflow flag of
a multi-byte subtract is not relied on, and this analysis found why: the ALU argument and the data sheet
(N, OV, C, DC, Z affected) say `N xor OV` after `SUBWF lo; SUBWFB hi` is the signed 16-bit order, a host model of
that gives no mismatch over 3.4 million pairs, **but the MDB simulator disagrees on one case**:
`SUBWFB` with `f = 0x80`, `W = 0x7F`, borrow set (so `-32768 < 32767`) returns OV = 0 where `-128 - 127 - 1 = -256`
overflows (STATUS read back as 0x67; the same instruction with `W = 1` or with no borrow gives the right OV). Whether
silicon matches the simulator is not known; hardware verification (or an erratum search) is needed before any
multi-byte signed compare uses the flags. The sign-bit and constant-folding changes above do not depend on it.
The single-byte case that was checked (`-128 - 127` with `SUBWF`, no borrow in) sets OV correctly in the simulator, and the
existing signed exec tests exercise `flag_branch`, so the 8-bit `bov/bn/bra/bnn` tail is left alone.

## 5. Float

Library routines measured (simulator, `3.14159` and `2.71828`, one call):

| Operation | Cycles | Library words | Call site |
|---|---|---|---|
| `f1 + f2` | 161 | 200 (+30 `FSub`) | 12 `movff` |
| `f1 * f2` | 217 | 195 | 12 `movff` |
| `f1 / f2` | **1010** | 150 | 12 `movff` |
| `f1 < f2` | 91 | 86 | 8 `movff` + result test |
| `f1 = a` (Byte / Word / Long) | 141 / 114 / 153 | 32 | 8-10 |
| `i = Integer(f1)` | 148 | 92 | 8 `movff` |
| `-f1`, `Abs(f1)`, copy | 12 | inline | |
| shared `Pack` + `FromMag` | | 53 + 31 | |

Constant folding of float and integer-to-float constants is already done (`f1 = 100` stores four bytes at compile time; `f1 * 10` is a
`FMul` against a folded `10.0`). `FDiv` costs 4.6× a multiply.

| Finding | Detail | Gain |
|---|---|---|
| **F1** operands and result travel through the callee's frame (`FLOATLIB_FADD__A/__B/__RESULT`) and are copied again into `__A`..`__D` by the routine's first and last instructions. The integer helpers (`__mul4`, `__div4`) already take `__A`/`__B` directly. | Calling convention for the `FLOATLIB_*` entry points becomes: caller loads `__A` (and `__B`), result left in `__A`; `FSub` becomes `btg __B3,7` + fall into `FAdd` | prologue + epilogue: FAdd/FMul/FDiv 24 words each, `Cmp` 16, `FFromLong`/`FToLong` 16 each, `FSub` −26 ⇒ **≈150 words (300 B, about 17 % of the 868-word library: Add 200, Sub 30, Mul 195, Div 150, Cmp 86, FromLong 32, ToLong 92, Pack 53, FromMag 30)**, 12 B of frame RAM, 24 cycles per operation. Call sites do not grow |
| **F1b** with F1, a chain keeps its intermediate in `__A`: `f3 = f1 * f2 + f3` today stores the product to `FADD__A` (4 `movff`) between the calls | | −8 words and −8 cycles per intermediate |
| **F2** spill order: `f3 = f1 + a` parks `f1` in `__main__TMP` (4 `movff` out, 4 back) while `FFromLong(a)` runs | For commutative `+`, `*`, evaluate the operand that needs a call first | −16 words, −16 cycles per such expression |
| **F3** `Float * 2^k`, `/ 2^k` (constant, e.g. `* 2.0`, `/ 2.0`, `* 0.5`) call the full multiply (218 cycles) or divide (≈1010) | add *k* to the exponent: result is `x` unchanged for ±0, infinity and NaN, a signed zero when the new exponent is ≤ 0 (the library flushes denormals), infinity when it reaches 255. One shared routine, about 20 words with the three guards | 218→≈20 cycles (≈1010→≈20 for `/ 2.0`); when these are the only uses, `FMul` (195 words) and `FDiv` (150 words) drop out of the image |
| **F4** compare with zero (`If f > 0.0`, `f < 0.0`, `f = 0.0`) builds a 4-byte zero and calls `Cmp` | test the exponent byte and sign bit inline (`movf b3,w; andlw 0x7F`, exponent via `rlcf b2`; NaN has exponent 255 and a non-zero fraction so it must still compare false) | ≈ −10 words per site, 91→≈10 cycles; `Cmp` drops out when nothing else compares |
| **F5** `FDiv` runs **32** restoring iterations at ≈31 cycles; a 24-bit mantissa quotient needs a guard bit, one normalisation bit and a sticky bit: **26** | The quotient is left-aligned by the `Pack` input form; running 26 steps and aligning with 6 shifts of 4 `rlcf` (30 cycles) removes ≈ 6 × 31 − 30 ≈ 156 cycles | 1010→≈850 (-16 %); bit-exactness must be re-proved against the existing `lib_floatlib*` tests and a host IEEE model |
| **F6** `f / K` for a constant `K` is a divide at 1010 cycles; `f * (1/K)` is not bit-identical to IEEE division | offer it only behind an explicit option (e.g. `#option FastFloat`) with the documented 1-ulp difference | 1010→217 |
| **F7** `Cmp` returns −1/0/1/2 in a byte which the caller re-tests (`movf RESULT,w; xorlw 0xFF; bnz`) | return the three outcomes in `Z`/`C`/`N` so the caller branches directly | −2 words per comparison site, −3 cycles |
| **F8** `Byte`/`Word` to `Float` goes through the 32-bit `FFromLong` (zero-fills the upper bytes at the call site) | a byte entry point normalises 8 bits instead of up to 32 | ≈ −60 cycles for Byte sources (estimate; unmeasured) |

### 5.1 Whole-program breakdown: the OLED Float self-test

Measured on `my_src/first_test/main.bas` (basil 0.1.35, `--report` plus the generated `.S`): 2806 words (5612 B). Words are program-memory
words; `movff`, `call` and `goto` are 2 words each.

| Part | Words | Bytes |
|---|---|---|
| Float library (`FADD` 200, `FSUB` 30, `FMUL` 195, `FDIV` 150, `PACK` 53, `CMP` 86, `FTOLONG` 92, `FFROMLONG` 32, `FROMMAG` 31) | 869 | 1738 |
| `ShowLine` (with `WriteFloat` inlined) | 261 | 522 |
| Start-up and program body | 642 | 1284 |
| OLED and I2C library | ≈650 | ≈1300 |
| String literals | 272 | 544 |

Most of the Float cost outside the library is operand shuffling, not arithmetic:

| Source | Words | Bytes |
|---|---|---|
| Program body: each of the 6 `ShowLine(..)` calls copies 2 operands into the helper frame (8 `movff`), the result into `ShowLine__V` (4 `movff`) and loads the expected constant (4 `movlw`/`movwf` pairs): ≈170 `movff` words + 46 constant-load words | ≈216 | ≈430 |
| `ShowLine`: 74 of its 130 instructions are `movff` operand copies | 148 | 296 |
| Library entry and exit copies (frame to `__A`..`__D` and back): `FADD`/`FMUL`/`FDIV` 16 + 8, `Cmp` 16 + 2, `FToLong`/`FFromLong` 8 + 8 each | ≈130 | ≈260 |

Patterns seen in the `ShowLine` code that the table above already lists as findings:

* `neg = f < 0` builds a four-byte zero (4 `clrf`), copies `f` (8 words) and calls `Cmp`, then re-tests the result (`xorlw 0xFF; bnz`): **F4** and **F7**.
* `f - Float(whole)` parks `f` in `WRITEFLOAT__TMP` (4 `movff` out, 4 back) while `FFromLong` runs: **F2**.
* Every chain step (`FSub` → `FMul` → `FAdd` → `FToLong`) stores its result to the next routine's frame (4 `movff` each): **F1b**.

The ≈430 B of program-body call-site overhead is the part F1 shrinks at the call site (operands loaded straight into `__A`/`__B`, result left in
`__A`), together with the ≈260 B of library entry/exit copies. These figures are counted from the listing; no before/after build exists for F1 yet, so
the gain is an estimate until it is implemented and re-measured with `--report`.

## 6. RAM

* **Float frames (12 bytes):** gone with F1 (the frames were already overlaid, so the saving is the whole 12 bytes, not 12 per routine).
* **`__D2`/`__D3` and `__B0:__B0+1` scratch** used by signed compares and constant staging (§3.2 W7, §4): removing them lets `__D`
  and `__B` stay at 2 bytes in programs where nothing else needs more.
* **`__main__TMP` / per-routine `__TMP`** is a hidden byte or word for `Min`, `Max`, `Abs`, array read-modify-write: P7, A2 and W12 remove it.
* **Counted-loop counters** (`<routine>__H<n>`, one byte per nested loop): L1.
* P1/P2 touch `__A` less; scratch is allocated only up to the highest byte a program still uses, so a program that is left with no
  helper call that needs `__A` would no longer allocate it (to be confirmed per program with `--report`).
* Start-up zeroing already uses `clrf` per byte for few variables and a loop for many.

## 7. Suggested order

1. **P3 and the `movlw k; xorlw 0x80` fold** — pure peephole, no new cases, immediate wins everywhere.
2. **P1 + P2 + W5** (three-address W-routed codegen, in-place shifts, 16-bit ±1) — the widest effect on ordinary programs; add the BSR cost rule from §3.6.
3. **P7, P8, P11, W10, W12** — small independent recipes, each verified by the exhaustive arithmetic tests (`scripts/gen-arith-tests.py`, `tests/exec/arith_*`).
4. **P4/P5 and the library digit loops (P6)** — the reciprocal-multiply with compile-time exhaustive check, plus division value numbering.
5. **F1 (+F1b, F2)** then **F3/F4**, then **F5/F7** — the Float calling convention first, since it changes what every later float change touches.
6. Re-run `scripts/bench.py --md` after each step and record it in `docs/BENCHMARKS.md`; every change needs the differential `-O0` comparison. Add kernels for what
   the current set does not exercise: a Word `Mod`/`/` by constant, a digit-printing loop, an array walk with a Byte index, `Min`/`Max`/`Abs`, a signed compare,
   and one Float chain (`a * b + c`, `x / 2.0`, `x > 0.0`).

## 8. Open points

* The simulator/silicon question about `SUBWFB` and OV (§4) is unresolved.
* F5, F8 and the "operand fits a byte" divide estimate are projections, not measurements.
* `Select Case` and `Boolean`/`Bit` operations were not examined here.
* The measurements are PIC18F27Q10 in the simulator; the PIC18-Q41 parts have the same instruction set and the same helpers, but the
  access bank is not at the same addresses (`__A` landed at 0x500 in one project built for a Q41 part), so the BSR rule in §3.6 needs a look there.
