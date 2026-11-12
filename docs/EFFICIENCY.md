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
| P4 | Division and `Mod` by a constant | reciprocal multiply, verified exhaustively at compile time (**Byte done, 0.1.59**; **Word done under `Optimize = Speed`, 0.1.60**; **LongWord by a byte constant done, 0.1.114**, with a byte-divisor helper `__divk4` instead of a reciprocal multiply, which would be ~100 words per site; not under Speed, not signed) | Byte `/10`: 7 words, no helper | 120→7 (Byte), 314→41 (Word) | 0 | medium |
| P5 | `/` and `Mod` of the same operands | **done, 0.1.113** (`peephole::pass_div_share`); one helper call serves both | −1 call | 634→315 | 0 | low |
| P6 | `lib` decimal printing | table-driven repeated subtraction (**done: `SerialWriteWord` 0.1.94; `LcdWriteWord`, `Serial2WriteWord` and `OledWriteWord` 0.1.112**) | −68 B (5-digit test) | 5109→439 | 0 | low |
| P7 | `Min`, `Max`, `Abs` | skip-instruction forms (`CPFSGT`/`CPFSLT`, sign test) (**Byte `Min`/`Max` done, 0.1.61**; **ShortInt `Abs` done, 0.1.62**; **signed Byte and 16/32-bit `Abs`, `Min`, `Max` done, 0.1.64**) | Byte Min/Max 14→4 words; Integer `Abs` 44→6 | 14→4; 44→6 | −1..2 B temp | low |
| P8 | Byte-indexed array access | `lfsr` + `PLUSW0` (arrays ≤ 128 elements) (**done for one-byte elements, 0.1.62**) | 12→4 words | 13→5 | 0 | low |
| P9 | Float helpers | pass operands and result in `__A`/`__B` like `__mul4` (**done, 0.1.54**; `FMul`/`FDiv` bodies 0.1.55) | PIC18 `float_basic` 1281→1111 words; 16F17146 1598→1178 | −24 per op; `FMul` −27/−8, `FDiv` −8/−8 once (PIC18/mid-range) | −61 B | medium |
| P10 | `Float * 2^k`, `/ 2^k` | exponent add, no `FMul`/`FDiv` (**done, 0.1.71**, F3) | −345 words when they were the only users | 218→≈20 | −12 B | medium |
| P11 | Signed compare | fold constant bias; sign-bit test against 0 (**done, 0.1.62**) | `i<0` 13→2 words; `i<K` 11→8 | 13→3 (`i<0`) | −2 B scratch | low |
| P12 | Word `± 1`, constant compares | `infsnz/incf`, `decf/btfss`, `subfwb` (**done, 0.1.65 / 0.1.68**, W5 and W7) | `x+1` 4→2; `x>K` 9→5 | 4→2; 11→7 | 0 | low |
| P13 | `FDiv` | 26 quotient bits instead of 32 (**done, 0.1.72/0.1.73**, F5; now 25 steps) | 0 | 1010→≈820 | 0 | medium |

Everything in the table applies to code in the Access Bank; see §3.6 for banked variables.

## 3. Integers

### 3.1 Byte (and ShortInt)

Already tight and left alone: `a + b`, `a And/Or/Xor`, `a * b` and `a * K` (`MULWF`/`MULLW`), `a << k` (repeated
`ADDWF WREG` for small k, `MULLW` beyond), `a >> 4` (`SWAPF`+mask), `a Mod 2^k`, `a / 2^k`, compare chains, `a = a + 1` (`INCF`).

| Finding | Now | Proposed | Measured |
|---|---|---|---|
| **B1** (**done, 0.1.70**) `c = a - b` is computed reversed and negated: `movf a,w; subwf b,w; sublw 0` | 4 words | `movf b,w; subwf a,w` | 4→3 cycles |
| **B2** (**done, 0.1.61**) `Min(a,b)`/`Max(a,b)` use a branch-free mask with a hidden temp (`__main__TMP`) and a `movlw 1/0` flag | 14 words | `movf b,w; cpfsgt a; movf a,w` (Min), `cpfslt` (Max): skip-instruction select | 14→4 and 13→4 cycles; Min(5,9)=5 and Max(5,9)=9 checked |
| **B3** (**done, 0.1.64**) `Abs(sb)` | 17 words | `movf sb,w; btfsc sb,7; negf WREG` | 17→4 cycles; −5→5, 7→7, −128→128 |
| **B4** (**done, 0.1.70**) `a / K`, `a Mod K` through `__div1` (8-iteration loop) | 118-122 cycles | `a/10 = (a·205)>>11`: `movf a,w; mullw 205; rrncf PRODH,w; rrncf WREG,w; rrncf WREG,w; andlw 0x1F` (7 words with the store); `Mod` adds `mullw K; movf PRODL,w; subwf a,w` | /10: 120→7; Mod 10: 122→10; a=200 checked |
| **B5** (**done, 0.1.70**) `a Mod b` result path: `movff __C0,__A0; movf __A0,w` | 3 words | `movf __C0,w` | counted |
| **B6** (**done, 0.1.70**) `a >> 1` is `movf a,w; rrncf WREG,w; andlw 0x7F` | 3 words | `bcf STATUS,0; rrcf a,w` | 4→3 cycles; 201→100 |
| **B7** (**done, 0.1.70**) `c = -a` with a *Byte* target is evaluated in 16 bits | 9 words | `movf a,w; sublw 0` (the ShortInt case already does this) | counted |

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
| **W3** (**done for a different destination, 0.1.66**) `x << 4` / `x >> 4` use the generic loop | 15 words, 33 cycles | nibble swap: `swapf hi,f; movlw 0xF0; andwf hi,f; swapf lo,f; movlw 0x0F; andwf lo,w; iorwf hi,f; movlw 0xF0; andwf lo,f` | 33→9; 1001<<4=16016 |
| **W4** (**done for `<< 8` and `>> 8`, checked 0.1.111**; `Byte(x And 255)` still emits a useless `andlw 0xFF`, 1 word) `x >> 8`, `x << 8`, `x And 255`, `x / 256`, `x Mod 256` stage through `__A1` | 5 words | `movff x+1,x; clrf x+1` and the like | 5→3 cycles; 1001>>8=3 |
| **W5** (**done, 0.1.65**) `x = x + 1` / `x = x - 1` | 4 words | `infsnz x,f; incf x+1,f` and `decf x,f; btfss STATUS,0; decf x+1,f` | +1: 4→2 (255→256, 65535→0); −1: 4→3 (256→255, 0→65535, 5→4) |
| **W6** (**already done**, found so in 0.1.69) `x * K` (K constant) ends with `movff __C0,__A0; movff __C1,__A1` before the store | 18 words | store `PRODL`-derived bytes straight to the destination | 18→13 cycles (`x*10`, 123→1230) |
| **W7** (**done, 0.1.68**) `x > K`, `x >= K` stage K into `__B0:__B0+1` first | 9 words | `movf x,w; sublw lo; movlw hi; subfwb x+1,w; bc/bnc` | 11→7 cycles; 1500>1000 |
| **W8** (**done, 0.1.67**) `x >= 256`, `x > 255`, `x < 256` (byte-boundary compares) | 7-9 words | `movf x+1,f; bnz/bz` (2 words) | counted |
| **W9** (**done, 0.1.67**) `x = 0` / `x <> 0` tests byte by byte | 4 words (Word), 8 (Long) | `movf x,w; iorwf x+1,w; bnz` (3 / 5 words) | counted; a few cycles slower on the early-exit path, so size-only: apply under `Optimize = Size` |
| **W10** `i / 2^k` (**done for `/`, k = 1..8, 0.1.63; `Mod` 0.1.64**), `i Mod 2^k` for signed types call `__sdiv2` | 344-348 cycles | `i/2`: `rlcf i+1,w; movlw 0; addwfc i; addwfc i+1; rlcf i+1,w; rrcf i+1; rrcf i` (7 words); general k: add `(i>>15) And (2^k-1)` then arithmetic shift | 348→7; −1234→−617, −1→0, −32768→−16384, 32767→16383, 1235→617 |
| **W11** (**done, 0.1.68**) `x = a * 256 + b`, `(a << 8) Or b`: the "pack two bytes" idiom | 11 words | `movff a,x+1; movff b,x` | counted |
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
| **A1** (**done, 0.1.62**) `c = arr(a)`, `arr(a) = b` for a Byte index build a 16-bit address in `__A`, add the base, copy it to `FSR0` | 12 words | `lfsr 0,arr; movf a,w; movf PLUSW0,w` (`PLUSW0` offsets by the *signed* W, so valid only when the array has ≤ 128 elements; elements beyond that keep the current path) | 13→5; 77 read back |
| **A2** (**done for `+ 1` / `- 1`, 0.1.69**) read-modify-write `arr(a) = arr(a) + 1` computes the address twice and parks the value in `__main__TMP` | 27 words | `lfsr 0,arr; movf a,w; incf PLUSW0,f` | 27→4 cycles; −1 B temp |
| **A3** (**already done**, found so in 0.1.69) Word arrays, `x = warr(a)`: `movff POSTINC0,__A0; movff POSTINC0,__A1; movff __A0,x; movff __A1,x+1` | 8 words | `movff POSTINC0,x; movff POSTINC0,x+1` (P3) | counted |
| **A4** (**done, 0.1.70**) Word index doubling (`rlcf` through `__A`, 16-bit add) | ≈14 words | `movf a,w; addwf WREG,w` then `PLUSW0` while `a < 64`; keep `FSR0` loaded across several accesses to the same array | counted |
| **L1** (**done for a loop variable that is read afterwards, 0.1.101**; a loop whose body reads the variable still has a hidden byte) counted `For` loop with a Byte variable | `clrf v; movlw n; movwf H; … dcfsnz H; bra; incf v; bra` + 1 hidden byte | when the body never reads `v`, count with `v` itself (no hidden byte); otherwise unchanged | counted |

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
existing signed exec tests exercise `flag_branch`, so the 8-bit `bov/bn/bra/bnn` tail was left alone (replaced in 0.1.162, below).

**0.1.162.** The N/OV form was tried for every width (`subwf..subwfb; btfsc STATUS,OV; xorlw 0x80; bn`) and `tests/exec/signed_ov_cmp.bas` (`scripts/gen-signed-ov-tests.py`: ShortInt, Integer and LongInt at the edges of their ranges, `< <= > >=`, variable/variable, variable/constant and constant/variable) passes in basil-sim but fails in MDB on every Integer and LongInt sum, and no erratum mentions it, so the multi-byte compare keeps the bias. What changed: Y's top byte is biased in W right before the last `SUBWFB` (`XORLW` changes only N and Z, DS40002043F p.629, so the borrow survives) instead of through `__D3`: 2 words fewer for a variable/variable compare, and `__D3` is no longer used by compares. The single-byte compare (no borrow in; MDB agrees) now flips W's sign when OV is set and branches once on N: `btfsc STATUS,3; xorlw 0x80; bn` replaces `bov; bn; bra; bnn` (1 word fewer). b_dsp 2714 → 2690 bytes.

**0.1.163.** The `K < y` → `y >= K + 1` fold (constant moved to the right so it goes in through `movlw` instead of `__B`) now covers signed compares too, for a variable `y` and for a computed one; it is skipped when K is the largest value of the type (`0x7F..FF` signed). Integer `x > 100`: 14 → 8 words. A signed compare that ends up against 0 (`x > -1`) is a sign-bit test, 2 words. b_dsp 2690 → 2672 bytes.

**0.1.164.** The fold moved to the top of `ord_jump` (`const_right`), so every compare with a constant reaches the special cases in one form, and a computed value against a constant is compared in `__A` instead of through a temporary. Benchmarks unchanged; `signed_ov_cmp` 16154 → 15342 bytes.

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
| **F1** (**done**: the register convention of P9, 0.1.54/0.1.55) operands and result travel through the callee's frame (`FLOATLIB_FADD__A/__B/__RESULT`) and are copied again into `__A`..`__D` by the routine's first and last instructions. The integer helpers (`__mul4`, `__div4`) already take `__A`/`__B` directly. | Calling convention for the `FLOATLIB_*` entry points becomes: caller loads `__A` (and `__B`), result left in `__A`; `FSub` becomes `btg __B3,7` + fall into `FAdd` | prologue + epilogue: FAdd/FMul/FDiv 24 words each, `Cmp` 16, `FFromLong`/`FToLong` 16 each, `FSub` −26 ⇒ **≈150 words (300 B, about 17 % of the 868-word library: Add 200, Sub 30, Mul 195, Div 150, Cmp 86, FromLong 32, ToLong 92, Pack 53, FromMag 30)**, 12 B of frame RAM, 24 cycles per operation. Call sites do not grow |
| **F1b** (**done** with F1) with F1, a chain keeps its intermediate in `__A`: `f3 = f1 * f2 + f3` today stores the product to `FADD__A` (4 `movff`) between the calls | | −8 words and −8 cycles per intermediate |
| **F2** (**done, 0.1.71**) spill order: `f3 = f1 + a` parks `f1` in `__main__TMP` (4 `movff` out, 4 back) while `FFromLong(a)` runs | For `+`, `-`, `*` with a plain variable first and a FloatLib call second, evaluate the call first (`a - b` becomes `(b Xor sign) + a`); the variable is then loaded straight into `__B` | −16 words, −16 cycles per such expression (measured with F8: `f + b` 305→239 cycles) |
| **F3** (**done, 0.1.71**) `Float * 2^k`, `/ 2^k` (constant, e.g. `* 2.0`, `/ 2.0`, `* 0.5`) call the full multiply (218 cycles) or divide (≈1010) | add *k* to the exponent: result is `x` unchanged for ±0, infinity and NaN, a signed zero when the new exponent is ≤ 0 (the library flushes denormals), infinity when it reaches 255. One shared routine, about 20 words with the three guards | Measured: `f * 2.0` and `f / 2.0` 36 cycles net of the call-site loads (was 218 and 1036); `FScale` is 53 words on PIC18. When these are the only uses, `FMul` (195 words) and `FDiv` (150 words) drop out of the image |
| **F4** (**done, 0.1.71**) compare with zero (`If f > 0.0`, `f < 0.0`, `f = 0.0`) builds a 4-byte zero and calls `Cmp` | A new register routine `FSign` (20 words since 0.1.75, one operand, answers like `Cmp(x, 0)`: -1, 0 for a zero or a denormal, 1, 2 for NaN) is called instead of `Cmp`; `0.0 < f` is turned into `f > 0.0`. A routine rather than inline code, because the same code is needed for both cores | −4 words per site (no 4-byte zero is built); measured `If f > 0.0` 48→10 cycles net. `Cmp` drops out when nothing else compares |
| **F5** (**done, 0.1.72**) `FDiv` ran **32** restoring iterations at ≈31 cycles; a 24-bit mantissa quotient needs a guard bit, one normalisation bit and a sticky bit: **26** | The first quotient bit is always 1 (the dividend is pre-normalised), so 25 steps give the 24 mantissa bits and the guard bit and the non-zero remainder is the sticky bit; the 25-bit quotient is aligned to bit 31 with one `rrcf` chain (9 instructions) | Measured `f / g` 984→799 cycles net (−19 %); bit-exact on `float_muldiv`, `lib_floatlib*` and 250 random pairs of `gen_float_vectors.py` on both cores |
| **F6** (**not done, option-gated**) `f / K` for a constant `K` is a divide at 1010 cycles; `f * (1/K)` is not bit-identical to IEEE division | offer it only behind an explicit option (e.g. `#option FastFloat`) with the documented 1-ulp difference | 1010→217 |
| **F7** (**not done**) `Cmp` returns −1/0/1/2 in W (since P9) and the caller re-tests it (`xorlw 0xFF; bnz`) | return the outcomes in `Z`/`C`/`N` so the caller branches directly | Only the `xorlw` is left to save: 1 word and 1 cycle per site, and the flags would have to be written to STATUS by `Cmp` (3-4 more library words, and PIC16 has no `N`), so it pays back only with several comparisons |
| **F8** (**done, 0.1.71**) `Byte`/`Word` to `Float` went through the 32-bit `FFromLong` (zero-fills the upper bytes at the call site) | `FFromByte` / `FFromWord` (about 14 and 16 words) read only `__A0` (`__A1:__A0`) and enter `FromMag` with the magnitude already moved up, so no whole-byte shifts run; unsigned sources only (`ShortInt`/`Integer` still use `FFromLong`) | Measured: `h = b` 113→66 cycles net, `h = w` 164→134; 3 `clrf` fewer at each call site |

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

**When the special cases are used (0.1.73).** `FScale`, `FSign` and `FFromByte`/`FFromWord` each add a routine, so on the
OLED Float self-test (one `* 2`, one compare with zero, other multiplies and compares still needed) they made the image 64
words *larger* (2610 → 2674). `lower` therefore lowers a Float program twice: a dry run counts the places each case applies
(`FloatSites`) and `FloatPlan::for_sites` keeps a case only when its call-site saving (3 words per scaling site, 4 per zero
compare, 3/2 per Byte/Word source) plus the general routines that drop out (`FMul` 158, `FDiv` 141, `Cmp` 67, `FFromLong` 18
words) outweigh the new routine. The same program now builds to 2604 words. The routine sizes are constants in `lower.rs`
(`W_FMUL` …); they are the PIC18 sizes and are also used for the mid-range core. F2 (operand order) costs nothing and is always on.

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

* The simulator/silicon question about `SUBWFB` and OV (§4) is unresolved: no erratum for the parts here mentions it and the data sheet only says OV is affected, so it needs a real part. The signed compare stays carry-only.
* The "operand fits a byte" divide estimate is a projection, not a measurement.
* `Select` and `Boolean`/`Bit` operations were examined in 0.1.115 (PROGRESS.md). Left: `f = (x = 3)` could be `clrf f / movf / xorlw / btfsc Z / incf f` (5 words against 6) when `f` is not read in the test.
* The measurements are PIC18F27Q10 in the simulator; the PIC18-Q41 parts have the same instruction set and the same helpers, but the
  access bank is not at the same addresses (`__A` landed at 0x500 in one project built for a Q41 part), so the BSR rule in §3.6 needed a look there: checked in 0.1.115, the bank logic is driven by the device's access ranges and is correct on the Q41.

## 9. Larger-program findings (0.1.138, 2026-11-05)

Four 1.5 to 3 KB programs written in BASIC and C (algorithms, fixed-point DSP, text formatting, command state
machine) came out **16% larger** than XC8 `-Os` in total (8740 against 7560 bytes; table in `docs/BENCHMARKS.md`),
so the small-kernel advantage does not carry over. Sources and `run.sh` were in the session scratchpad, not the
repo; step 1 below puts them in `bench/large/`. Counts are instruction counts from the `.S` files *(counted)*, not
measured image deltas, and nothing in this section is implemented.

**Where the bytes go.** `movff` is 2 words. a_algo has 225 of them (38% of the image), b_dsp 263 (34%); 139 and
202 of those move operands through `__A`/`__B`/`__C`. The gap is mostly operand shuffling and generic helpers.

| # | Where | Change | Estimate |
|---|---|---|---|
| L1 (done 0.1.139) | `(x And 2^k) <> 0` on Word/LongWord (CRC, bit loops) copies to `__A`, masks, clears the upper bytes and tests all of them (~13 words) | narrow `And` with a constant to the bytes the mask touches; emit `btfsc`/`btfss` (2 words) | about -11 words per site |
| L2 (done 0.1.139) | `x = (x >> 1) Xor K` goes through a 4-byte copy-in and copy-out (8 `movff`) although the plain shift is already in place | shift the destination in place, then apply the constant bytes to it | about -16 words per site (CRC32, CRC16, LFSR, `isqrt`) |
| L3 | array access repeats `movf j,w` + a 2-word `lfsr`; the bubble-sort swap rereads `data(j)` it already holds in a temp | keep FSR0 live across adjacent accesses, `POSTINC0` for `a(j)` then `a(j+1)`, reuse a value held in a temp (block-local value numbering) | about -3 to -6 words per extra access |
| L4 | Integer * Integer is sign-extended to 32 bits and sent to the 67-word `__mul4` | signed 16x16->32 helper from four `MULWF` (about 20 words); same for Word x Word, Byte x Word | about -30 to -45 words per site; `__mul4` drops out of 16-bit-only programs |
| L5 | `Integer32 / constant` (e.g. `acc / 160`) calls the 73-word `__sdiv4` | choose a 16-bit helper when range analysis shows the dividend fits; extend constant division to signed operands | about -45 words when `__sdiv4` becomes unused |
| L6 | dead copies: `movff A->RESULT` then `RESULT->A` after an inlined function (16 words for a LongWord); `movwf __A0` / `movf __A0,w`; `movwf RESULT` + `movwf TMP` never read | peephole and liveness over scratch and temp bytes, extending P3 to inlined calls and returns | about -4 to -16 words per function |
| L7 | constant-start loops emit `clrf j / movf j,w / subwf limit / bnc` for a first test that cannot fail; array-element compares go through `TMP`/`TMP+1`; 16-bit `Mod` by a constant such as 251 or 255 | skip the provable first test; compare from W; use the `__div2` path | a few words per site |

**Order.** (1) Add `bench/large/` with the four programs and the simulator sink-equality check (basil against XC8
`-Os`), gating every step together with `cargo test --release`. (2) L1 and L2. (3) L6 and L3. (4) L4 and L5, which
touch helper selection in `lower.rs`/`codegen.rs`. (5) Re-measure after each step, record it in
`docs/BENCHMARKS.md`, bump the version by a patch step, and change the README claim only as far as the data allows.

**Risks to check for each item.** FSR0/FSR1 kept live across statements must be saved by the interrupt context save.
Flags (carry, zero) must not be assumed from an instruction the new sequence no longer emits. A value reused from a
temp is valid only until a call, an ISR-visible variable or another store to the same array can change it. Scratch
`__A`/`__B`/`__C` are shared with the helpers, so no dead-copy removal across a `call`.

**Progress (0.1.139).** `bench/large/` holds the four programs, `run.sh` and the sink expectations (`exec-test.py` checks
`K_SINK` against the value XC8 `-Os` produced). L1 (`and_test` in `codegen.rs`: `btfsc`/`btfss` for a one-bit mask, `movlw`/`andwf`
for several bits, one test per non-zero mask byte) and L2 (`(x >> k) Xor K` shifted into the destination, then the constant folded in
byte by byte) are implemented, `-O1` and up only. Program bytes, basil: a_algo 2382 to 2280, b_dsp 3104 to 3102, c_text 1788 to 1786,
d_ctrl 1466 to 1464; total 8740 to 8632 (1.14 of `-Os`). Tests: `tests/exec/and_mask_test.bas`, `tests/exec/shift_fold_const.bas`.

**Progress (0.1.140).** Part of L6 and L3 is implemented in `peephole.rs`, `-O1` and up:
* `pass_redundant_lfsr` drops `lfsr n, X` when FSR n already holds X in the same straight run (`PLUSW`/`INDF`
  accesses leave the pointer alone; auto-increment forms, labels, calls, raw text and any other FSR mention forget it).
  Interrupt handlers save the FSRs they use, so reuse is safe.
* `pass_wreg` tracks `movwf __A0` / `movf __A0, w` as W and the scratch byte being equal, so the reload goes.
* `pass_copy_back` drops `movff R, A` after `movff A, R` when neither byte was written since. Pairs naming a scratch
  byte are forgotten at a `Fence` (no scratch value is carried past a statement); keeping them made `b_dsp` miscompile,
  which the simulator sink check caught.

Program bytes: total 8632 to 8556 (1.13 of `-Os`; table in `docs/BENCHMARKS.md`). Not done: reusing a value already
held in a temp (`t = data(j)` rereads), and the inlined-function result copies that cross a statement end, which need
a code generator change rather than a peephole. Tests: `second_lfsr_of_the_same_array_goes`,
`reload_of_a_scratch_byte_just_stored_from_w_goes`, `copy_back_after_a_store_goes` and its Fence case.

**Progress (0.1.141).** `pass_load_reuse` finishes L3: a load `movf i,w; [addlw k]; lfsr 0,A; movf PLUSW0,w; movwf h`
becomes `movf r,w` when an earlier load of the same element went into a byte `r` that neither it, `i`, nor `A` has been
written since (an indirect store, label, call or unknown instruction forgets everything). The `lfsr` goes too when FSR0
is not used before its next load; with `addlw` the pass requires carry and overflow to be dead. `pass_copy_back` now
compares plain bytes by address (`X` and `X+0`). Bubble sort: 5 and 4 words saved in the swap; algorithms 2248 to 2238
bytes, 92060 to 87997 cycles. Test: `element_already_in_a_temp_is_not_loaded_again`.

**Progress (0.1.142).** `gen_mul` recognises two operands that are both sign-extended 16-bit values and loads only
their low two bytes, then calls `__smul4` (unsigned 16x16 from four `MULWF`, less each operand shifted up 16 where the
other is negative). The call site shrinks by about 22 words; the helper costs about 45, so it pays from the third site.
Test: `tests/exec/smul_wide.bas`.

**Progress (0.1.143).** `pass_sum_share` (peephole): a wide sum built in `__A` (`movff` of the first operand, then
`movf`/`addwf`/`addwfc` of the second) is not built again while `__A` still holds it, as in `if acc >= r + b then acc =
acc - (r + b)`. Nothing between the two copies may write `__A` or either operand, no label may let another path in, and
`WREG` and the flags must be dead after the dropped copy. Saves 16 words per use (DSP program 3082 to 3050 bytes). Test:
`sum_still_in_scratch_is_not_built_again`.

**Progress (0.1.144).** `narrow_highword` (peephole, run in `codegen.rs` once the image is known to end below 64 KB, absolute
code only): `movlw highword(S); movwf X; movlw 0; addwfc X, f` (the indexed table address) and `movlw highword(S); movwf X`
become `clrf X`, since every symbol in the image then has a zero upper byte and the add cannot carry into it. The clear
stays because a flash write elsewhere may leave `TBLPTRU` non-zero. Applied only when the next instruction reads neither W
nor Z. Program bytes: total 8474 to 8430 (b_dsp 3050 to 3036, c_text 1770 to 1746, d_ctrl 1448 to 1442). Test:
`highword_set_becomes_a_clear`; `tests/exec/addressof.bas` expects the routine and table addresses 4 bytes lower.

## 10. Second larger-program review (0.1.155, 2026-11-08)

The four `bench/large/` programs build to 8430 bytes against 7560 for XC8 `-Os` (11.5% larger). In the listings,
`movff` is 624 of 3454 instructions (about 30% of the image); most of those move values through `__A`,
`__main__TMP` and `Result` without need. Word counts below are counted from the `.S` files *(counted)*, not measured
image deltas.

| # | Where | Change | Estimate |
|---|---|---|---|
| M1 | `sink = sink Xor Crc32(48)`: a call on the right makes `bin_multi` (and the shift/compare paths) copy the left variable to `__main__TMP` first, combine in `__A`, then copy `__A` back to `sink` | skip the copy when the callee (transitively) cannot write the variable; apply the result to the variable in place when the destination is the left operand | 16-24 words per statement; about 150 words in a_algo |
| M2 | `r = (r >> 1) + bt` copies `r` to `__A` (8 words), shifts and adds there, copies back (8 words) | evaluate `x = (x op k) op y` in the destination when no later operand reads `x` (L2 generalised) | about 16 words per site (isqrt, RMS) |
| M3 | `movff v -> RESULT` in the callee, `movff RESULT -> __A`/dest in the caller; inlined calls copy `__A -> RESULT -> dest` | give `v` the storage of `Result` when the last statement is `Result = v`; forward an inlined result straight to its destination | 4-16 words per routine |
| M4 | `entry_clears` keeps clears of locals written inside a loop that runs at least once, or written before every read (`j`, `t`, `k`, `s` in the sorts, MatMul, Crc16, Gcd, Fib) | replace `written_first` with "not live at entry" | about 25 words over the set |
| M5 | zero-extended bytes routed through `__A` (`clrf __A2 ... movff __A2, X+2`); `movlw 0; xorwf X+n` (a no-op) | clear the destination byte directly; drop Xor/Or with known-zero bytes | 2-12 words per site |
| M6 | a loop limit that became constant after argument propagation stays in a hidden variable (`movlw 0x2F; movwf H5`, `xorwf H5`) and the first test of `For j = 0 To e` is kept | fold the hidden limit to a constant; drop a first test that cannot fail (L7) | about 5 words and 1 RAM byte per loop |
| M7 | `x * k + c` builds the product in `__C`, copies it to `__A`, adds, copies to the destination | add in `__C`, or build into the destination | 4-11 words per site |
| M8 | `a(i) = v` goes `movf v,w; movwf TMP; ...; movff TMP, PLUSW0`; inlined parameters loaded via `__A` | `movff v, PLUSW0`; load the parameter directly | 2-4 words per site |
| M9 | `SINT(idx + 1)` after `SINT(idx)` recomputes `TBLPTR`; `movff TABLAT, __A0 ... movff __A0, V` | reuse the post-incremented pointer; `movff TABLAT, V` | about 14 words in Sine |
| M10 | counted loops index arrays with `movf i,w; lfsr` on every pass | pointer set once, `POSTINC0`; `decfsz` count when `i` is not otherwise read | 3+ words per loop |

Peepholes (1-3 words each): `movlw 2^k; iorwf F,f` to `bsf` (BSF affects no status bits, DS40002043F p.627, so W, Z, N must be
dead); `movf X,w; addlw 1/0xFF` to `incf/decf X,w` with dead flags; `op X,w; movwf X` to `op X,f` with W dead; the
self-copy `movf T,w; movwf T`; keep W known across `movff R, PLUSW0`; `x = 0 - x` as `comf/negf/btfsc Z/incf` (NEGF, p.661);
Byte `>> 4..7` through `swapf` (p.627); fold `(a And m) >> k` masks; `> 0` on unsigned as `movf X,f; bnz`; the dead
`movff i, __A0` before a table address; helpers placed within `rcall` range.

**Order.** M1 and M2 first (one analysis: a write set per routine, then in-place evaluation), then M3 and M4, M5 and M6,
then the peepholes. Each step gated by the `bench/large` sink check, the `-O0` differential and `cargo test --release`.

**Progress (0.1.156).** M1 and M2, `-O1` and up, PIC18 back end (`codegen.rs`):
* `ir::routine_effects` gives each routine the variables it and everything it calls may write and read, or `None`
  when unknown (raw `Asm`, any `ByRef` access, `Extern`/register-call routines, a `Save` of a routine's frame).
  `Gen::calls_spare(e, v, no_read)` holds when no call in `e` writes `v` (or reads it, with `no_read`), `v` is not
  `Volatile`, no interrupt handler uses it (an unknown handler blocks everything), and `v` is a global or a variable
  of the routine being generated. The last rule matters: frames of routines that are never live together share
  addresses, so another routine's variable may sit on the callee's bytes; the routine being generated reaches the
  callee, so its own frame never overlaps it.
  An access through an indirect-file register (`INDFn`, `POSTINCn`, `POSTDECn`, `PREINCn`, `PLUSWn`) makes a routine
  unknown, like a `ByRef` access: it reaches whatever RAM its FSR points at.
* The six operand paths that saved a memory left operand before a right operand holding a call (`bin_byte`,
  `bin_multi`, `prep_ab`, `mul8`, the equality and ordered compares) take it from `Gen::left_src`, which skips the save
  when `calls_spare` holds.
* `store`: `x = x op f()` folds into `x` when the call spares it (`fold_into`; a zero-extended narrower operand is
  built at its own width and the missing bytes taken as zero). `Gen::spine` takes a left-leaning chain over `x`
  (`((x op a) op b) …`, with constant shifts of the running value) of at least two steps and applies each to `x` in
  order; after the first change no operand may read `x` (by name or through a pointer: `ByRef`, `INDFn`) and no
  call in it may read or write it. `a op (x …)` is taken right side first only when `a` is a constant or neither side
  has a call, since that moves `a` after the calls on the other side.

Program bytes: total 8430 to 7396 (0.98 of `-Os`; table in `docs/BENCHMARKS.md`). Test: `tests/exec/call_operand_inplace.bas`
(callees that write the variable, read it, write it through `ByRef`, write it after the first step; zero-extended
Byte results; a later step that reads the shifted variable) and `tests/exec/call_operand_order.bas` (a callee writing
through `INDF0`, call order under a commutative operator, a later step reading through `ByRef`). Not done: `codegen16`
(mid-range core).

**Progress (0.1.157).** M3 and M4, `-O1` and up (the IR, so both back ends):
* `opt::coalesce_results`: a routine ending `Result = v` (`v` a scalar local of the same type) makes `v` its result and
  drops the copy, when nothing in it reads `Result`, writes it other than by top-level clears (which go), or can leave
  before the copy (`Return`, a jump, a label), nothing else writes it, `Asm` names neither, and the routine is reached
  only by plain calls (not through its address, from `Asm` or from C).
* `ir::may_read_unset` replaces `written_first` for the entry clears of scalar locals and `Result`: a structured walk
  that keeps the clear only when some path may read the variable before writing all of it. An `If` sets it when every
  arm and the `Else` do; a `For` with constant bounds that runs at least once, or a `Count`, carries what its body sets
  when nothing in the body leaves or restarts the loop; a `While` never does; `Asm`, jumps, labels, a `Save` of it and
  partial writes count as reads. `Volatile` locals and strings keep the old rule.
* Calling-side copies of `Result` into `__A` were already forwarded by the peephole, so no codegen change was needed there.

Program bytes: total 7396 to 7244. Tests: `call_operand_order.bas` (an early `Exit` leaving `Result` 0, a read of
`Result` before the final copy, a local set on one path only).

**Progress (0.1.158).** M5 and M6, `-O1` and up:
* `store` (PIC18): a zero-extended value that needs code (`sink = Crc16(48)`, `t = data(i)`) is worked out at its own
  width and stored, and the upper bytes of the destination cleared, instead of building all bytes in `__A` and copying
  them out (2 words per extended byte). Xor/Or with the zero bytes of a zero-extended operand had already gone with M1
  (`fold_into` takes the missing bytes as zero, which `chain` skips).
* `opt::propagate_locals` also tracks hidden variables and puts what it knows into a `For`'s start and limit (worked
  out once, before the loop), so a limit that became a constant after argument propagation (`For i = 0 To n - 1`,
  `n` always 48) is folded and its hidden byte goes; a `Select` subject that is constant resolves the same way.
* `for_loop`: the entry test is also skipped when the start is the lowest value of the type counting up (the highest
  counting down) and the limit has the variable's width and signedness: no such limit can fail it (L7).

Program bytes: total 7244 to 7124. Test: `tests/exec/loop_entry_zext.bas` (limits 0 and 255 for a Byte loop from 0, a
signed loop from -32768, a loop counting down from 255, the folded hidden limit and `Select`, zero-extended Byte and
Word stores).

**Progress (0.1.159).** M7 and M8, `-O1` and up, PIC18:
* `gen_mul` by a constant: a multiplicand that is a plain variable private to this code (`Gen::var_private`: not
  `Volatile`, not used by an interrupt handler, since a byte may be read once per factor byte) is read where it is,
  so the partial products are summed in `__A` directly instead of in `__C` and copied over (`mul_partials_from`;
  2 words a byte: `seed * 25 + 13849`, `n * 3 + 1`, `lcg * 5 + 1`).
* `pass_stage_store` (peephole): `movf X, w` + `movwf T` (or `movff X, T`), an index set up in `WREG`/an FSR, then
  `movff T, <indirect>` becomes `movff X, <indirect>` when the window neither writes `X` nor touches `T`, the
  first instruction after the staging overwrites `WREG`, the flags `movf` sets are dead, and `T` is not read again on
  any path before it is written (`byte_dead_paths`, which follows branches and statement ends, since a temporary may be
  reused across one by `pass_load_reuse`). `X` is a compiler-placed RAM byte or `TABLAT`.
* Review fixes to M4: a write to part of a variable (`w.Byte0 = k`, `Result.Byte0 = k`) no longer counts as setting
  all of it; a `Break` in an inner loop no longer stops the outer loop's write from counting.

* Test tooling: `scripts/dma_sim.py` took the first stop whose address equalled `__halt` as the halt, but MDB prints a
  watchpoint (a data address) and a breakpoint (a program address) the same way; when the code shrank so that `__halt`
  landed on 0xE8, the DMASELECT watchpoint ended the replay and `lib_dma_abortmove` read all zeros. `Event.is_halt` also
  requires the PC to be at `__halt` (tests in `scripts/test_dma_sim.py`).
* 0.1.160: `pass_stage_store` missed a write to the source when the source was a scratch byte (`movff __A0, T`, then
  `__A0` reloaded for the FSR, then `movff T, POSTINC0`): a scratch byte's writes are tracked locations (`Eff::writes`),
  not `wmem`. The X-10 `Xin` result in `tests/exec_pins/lib_pins_model.bas` caught it; unit test
  `staged_byte_is_stored_from_its_source`.
* Not from this work: `lib_system` failed on the PIC18F16Q41 (`LY_WC` 2, expected 0) on 0.1.155 as well. Fixed in
  0.1.161: a basil-sim fault, not the compiler's (see `docs/PROGRESS.md`).

Program bytes: total 7124 to 7092. Test: `tests/exec/partial_write_clear.bas`.

## 11. Random library programs against XC8 (0.1.167, 2026-11-10)

`bench/random/`: `gen.py` writes a seeded random program in BASIC and in C. Each program takes 2 or 3 of the library
modules `adc`, `serial`, `eeprom`, `bits` and `delay`, plus core statements (Word arithmetic, a 32-bit multiply, a
divide, array loops, port writes), 16 operations in an endless loop; every input is read from a port, so nothing folds.
The C side calls `lib.h`, a port of the library routines used (same logic, same register writes, the library's `Const`
values as `#define`s, taken from basil's own output), for the PIC18F27Q10 at 64 MHz and the PIC16F18346 at 32 MHz.
`run.py` builds each pair with basil and XC8 v4.00 `-Os` and `-O2`. Sizes only: the pairs were not run, so behaviour is
not checked to be identical (C's integer promotions differ slightly from BASIC's).

Seeds 1-12. Flash in bytes on the PIC18 and in words on the 16F (each tool's own unit):

| Part | basil | XC8 -Os | XC8 -O2 | basil vs -Os | basil vs -O2 |
|---|---|---|---|---|---|
| 18F27Q10 | 10626 | 10310 | 11700 | +3.1% | −9.2% |
| 16F18346 | 6905 | 6028 | 7130 | +14.5% | −3.2% |

By module: `adc` + `serial` programs are 14-17% smaller than `-Os` on the PIC18 (about 1-2% on the 16F); `bits`,
`serial`, `adc` + `delay` 3-8% larger on the PIC18 and 3-23% on the 16F; `eeprom` + `delay` programs (seeds 6-8) 22-35%
larger on the PIC18 and 31-48% on the 16F. RAM: basil 46-56 bytes in every program, XC8 32-62 (less without `adc`).

### What needs to improve

Found by comparing routine sizes in seed 8 (`eeprom` + `delay`), XC8 sizes from its `.sym` start/end symbols:

| # | Where | basil | XC8 -Os | Change |
|---|---|---|---|---|
| X1 | Repeated statement sequences | each copy in full | identical sequences moved into shared blocks (`PL1`..`PL14`, procedural abstraction) | an outlining pass over the final items for repeated runs of 4+ words; the generator repeats statements, so this weighs more here than in real programs |
| X2 | `LongWord(a) * b`, both operands 16 bits | `__mul4`, a 32 × 32 helper of 67 words (PIC18) | `__lmul` 38 words | multiply zero-extended Word operands as 16 × 16 → 32 (four `mulwf` partials); a smaller `__mul4` when speed is not asked for |
| X3 | `buf(i) = buf(i) + i * x` | 15 words: element to `__main__TMP`, add, `movff` back through `PLUSW0` | in `-Os` shared via X1 | add into the element in place (FSR0 to the element, `addwf INDF0, f`), about 8 words; related to M8 and M10 |
| X4 | `EepromWrite` / `EepromRead` on the 16F | 75 / 40 words | 48 / 31 | the 16F result and argument copies through `__A` (argument copies done in 0.1.169, module review 7) |
| X5 | 16F program body | 453 words in seed 8 | 148 plus its shared blocks | the 16F back end lacks the PIC18's result coalescing, copy forwarding and staging passes (M1-M3, M8 have no 16F counterpart) |
| X6 | Argument set-up for `EepromWrite(k + (PORTB And 15), y)` | computed in `__A`, then 2 × `movff` into the parameter | built in the parameter | compute a parameter in place when nothing else in the call's arguments reads it |
| X7 | RAM | 46-56 bytes whatever the program | 32-62 | scratch `__A..__D` and per-module state are reserved whether or not used much; check the overlay of scratch with locals |

Where basil already wins: `serial` and `adc` routines (constant baud and clock arithmetic folded, short polling
loops), `__div2` (28 words against `__lwdiv` 37), and `EepromRead` on the PIC18 (21 words against 17 + `SetAddr` 7).

**Order.** X2 and X3 are small, general and safe; X5 is the largest gap and belongs with the 16F half of M1-M3; X1 is a
new pass and should come last, measured on `bench/large` and the library tests as well as here so the random
programs' repetition does not overstate it.

### Measured again with 0.1.172 (2026-11-10)

The same 12 programs (seeds 1-12, `gen.py OUT $s 16`), XC8 v4.00, after module reviews 1-9 and their compiler changes. Flash in
bytes on the PIC18, in words on the 16F:

| Part | basil | XC8 -Os | XC8 -O2 | basil vs -Os | basil vs -O2 | at 0.1.167, vs -Os |
|---|---|---|---|---|---|---|
| 18F27Q10 | 10534 | 10310 | 11700 | +2.2% | −10.0% | +3.1% |
| 16F18346 | 6446 | 6028 | 7130 | +6.9% | −9.6% | +14.5% |

Per program, basil against `-Os` (PIC18 / 16F): smaller in r01 (−14.0% / −7.3%), r02 (−17.2% / −6.6%) and r12 (−4.7% / −1.5%), and
on the 16F in r05 (−1.7%); about level in r10 (+0.3% / +4.3%); larger in r03-r05, r09, r11 (+2% to +8% / +7% to +17%); and well
larger in r06 (+18.2% / +20.3%), r07 (+22.0% / +22.3%) and r08 (+33.6% / +35.5%), the `eeprom` + `delay` programs. RAM is
46-52 bytes (PIC18) and 48-56 (16F) against XC8 32-59 on most programs; basil is lower only in the `adc` + `serial` ones
(r01, r02, r12).

The 16F gap halved (+14.5% to +6.9%) and the PIC18 one fell by a third. What is left is concentrated in three programs:
r06-r08 are 18-36% larger on both parts, and without them basil is within a few percent of `-Os` on the PIC18 and about +6% on the 16F.

### Priority to fix

Ranked by words recovered across these programs and by how many real programs the change reaches:

| Priority | Item | Why this order |
|---|---|---|
| 1 | **X5, 16F copy forwarding and result coalescing** (copy forwarding and result retargeting done in 0.1.175; in-place evaluation left) (the 16F half of M1-M3 and M8) | The whole remaining 16F gap (+6.9%, +17% in r09, +35% in r08) and the largest cost in every 16F module review (`SetAddr`, `FlashWriteWord`, `EepromWrite`). Every 16F program gains, library or not. |
| 2 | **X3 and X6, in-place array update and parameters built in place** (PIC18) | The `eeprom` + `delay` programs are +18% to +34% on the PIC18 and these two are the statements they repeat. General, small, safe. |
| 3 | **X4, 16F `EepromWrite` / `EepromRead`** | 75 / 40 words against 48 / 31; mostly closed by item 1, so re-measure after it before doing anything module-specific. |
| 4 | **X2, 16 × 16 → 32 multiply** | 67 words for `__mul4` against 38; the saving is in any program that multiplies two Words into a LongWord, one helper at a time. |
| 5 | **X7, RAM** | basil is above XC8 on most programs (49 against 36 in r07). Smaller effect on flash, but every program pays it and the small parts have little RAM. |
| 6 | **X1, outlining repeated sequences** | A new pass, and the generator repeats statements on purpose, so these programs overstate it. Last, and measured on `bench/large` and the library tests first. |

The next module reviews (`floatlib` onward) will keep finding gaps of the item 1 kind; fixing it first means their measurements start from the
better 16F baseline.

## 12. Third review: whole compiler output, both cores (0.1.181, 2026-11-11)

**Method.** The four `bench/large/` programs were built with `basil -S --report` for the PIC18F27Q10 and, with only
the `Device`, `Clock` and `RSTOSC` lines changed, for the PIC16F18346, and the listings were read against the source.
Sizes at this version: PIC18 7014 bytes (a_algo 1592, b_dsp 2662, c_text 1520, d_ctrl 1240); 16F 5135 words (1213,
1840, 1077, 1005). The helpers (`__div2`, `__div4`, `__mul2`, `__mul4`, `__smul4`, `__sdiv4`, the 16F `__mul2` and
`__udiv2`) were read as emitted.

**How far to trust this.** Nothing here is implemented and no proposed sequence was assembled or run: every word and
cycle figure is *(counted)* from the listing (`movff`, `lfsr`, `call` = 2 words; a taken branch = 2 cycles). Each
"after" sequence must go through the simulator sink check, the `-O0` differential and `cargo test --release` like
every earlier step. Instruction facts checked in the data sheets for this review: `RLCF f, W` leaves `f` alone and
puts the old bit 7 in C (DS40002043F p.666, flags C, Z, N p.627); `CPFSGT`/`CPFSLT` skip on `f > W` / `f < W`
(DS40002043F p.646-647); `MOVIW k[FSRn]` / `MOVWI k[FSRn]` take a signed offset of -32..31 and leave the FSR
unchanged (DS40001839E p.406). The other sequences use only instructions in the forms the compiler already emits.

Where the PIC18 bytes still go: `movff` is 376 of 2989 instructions; 138 of them load `__A`/`__B` from a variable and
92 store `__A`/`__C` to one. b_dsp alone has 93 and 43.

### 12.1 Ranked summary

| # | Change | Core | Where in the compiler | Flash *(counted)* | Cycles |
|---|---|---|---|---|---|
| R1 | Single-use locals and inlined-call parameters/results forwarded instead of stored and reloaded | both | `opt.rs` (inliner, a forward-substitution pass), `peephole::pass_copy_back` | 4-16 words per site; about 60 words in b_dsp, 20 in a_algo | same count |
| R2 | Sign- or zero-extended operand added/xored into a wider variable without building it in `__A` | PIC18 | `codegen.rs` `fold_into` / `bin_multi` | -8 words per 16-into-32 signed accumulate (5 sites in b_dsp) | -8 |
| R3 | `For` loop end: increment first when the variable is not read after the loop | both | `for_loop` (both back ends) | -1 word per loop (34 loop ends in the four programs) | -1 per pass |
| R4 | Array walks as pointer walks (`POSTINC0`, `MOVIW FSRn++`), count with `decfsz` | both | `for_loop` + element access (M10, still open) | 3-6 words per loop | about half of a simple loop body |
| R5 | Unary `Not` / `0 - x` through W or in place | PIC18 | `store`, unary lowering in `codegen.rs` | `Not` 32-bit 20 -> 8 words; `v = 0 - v` 10 -> 4 | same count |
| R6 | Compare with the left operand already in W: `cpfsgt`/`cpfslt`/reversed `subwf` instead of a temporary | PIC18 | `ord_jump` | -2 to -3 words per site | -2 to -3 |
| R7 | Dead `bc` path in `__div2`/`__div4` | PIC18 | `emit_helper` "div" | `__div2` 28 -> 23, `__div4` 46 -> 37 | -1 per quotient bit |
| R8 | Constant-table reads: byte index arithmetic, reuse `TBLPTR` for the next element | PIC18 | const-array read in `codegen.rs` (M9, still open) | 13 -> 7-8 words; a following `T(i+1)` 13 -> 0 | same count |
| R9 | 16F: ports of what the PIC18 already has (bit tests, zero-extended stores, load reuse, self-copies, FSR reuse) | 16F | `codegen16/*`, `peephole::optimise16` | CRC16 bit loop 32 -> about 12 words; 2-4 words per array access | large in bit loops |
| R10 | Multiply by a constant: build in the destination; 16F `__mul2` with a byte multiplier | both | `gen_mul` / `mul_partials_from`, 16F `__mul2` | PIC18 -3 to -5 words per site | 16F about half of 200 |
| R11 | `Select` on a dense range; shared case tails; `bra` to a `return` | both | `Select` lowering, `peephole` | 1 word per two cases; 2-3 words per shared tail | 2 per exit |
| R12 | Peepholes listed in section 10 and not yet done, plus new ones | both | `peephole.rs` | 1-3 words each, 25+ sites | same count |
| R13 | Quotient and remainder shared across a statement in between | both | `pass_div_share` or IR | -13 words in `ToDec` | one divide per digit |
| R14 | Signed compare with a constant: sign-bit pre-test, no low-byte subtract when the low byte is 0 | PIC18 | `ord_jump` | 8 -> 7 words; 8 -> 4 when the low byte is 0 | -1 to -4; frees `__D2` |
| R15 | Small items: start-up zero runs merged, `Result` coalescing for parameters and narrowed locals, arithmetic shift in scratch | both | `startup`, `opt::coalesce_results`, `shift_acc` | 1-5 words each | |

### 12.2 Detail

**R1. Values stored only to be loaded again.** The largest remaining class. Seen:
* A local assigned once and used once in the next statement: `d = SINT(idx + 1) - v` then `(d * frac) / 4` emits
  `movff __A0, D; movff __A1, D+1; movff D, __A0; movff D+1, __A0+1` (8 words, all removable since `d` is dead);
  `s = ...; samples(i) = s` in `Gen`; `t = v; t = t * num; Result = t / den` in `Scale` (24 words of copies);
  `t = a Mod b; a = b; b = t` in `Gcd` (`movff __C -> T` then `T -> B`, 4 words, 4 cycles a pass).
* Inlined calls. Parameters that the body only reads are copied anyway (`movff K_PLANT, K_PID__PV`,
  `movff K_Y, K_LOWPASS__Y`, `movff K_MODE, K_EXEC__OP`, and `K_LOWPASS__X`/`K_FIR__X`, stored from `__A` and never
  read from memory again). Results go through the callee's `Result` (`movff __A, K_FIR__RESULT` then
  `K_FIR__RESULT -> K_F`; `__A -> K_MEAN__RESULT -> __A`; `K_PID__OUT -> K_U -> __A`).
* `data(i) = Rnd()` in `Fill`: `movff K_SEED+1, K_RND__RESULT; movf K_RND__RESULT, w; movwf K_FILL__TMP; ...;
  movff K_FILL__TMP, PLUSW0` where `movff K_SEED+1, PLUSW0` would do (-4 words, -4 cycles a pass);
  `pass_stage_store` sees one stage, not two.

Proposal: at IR level, when inlining, substitute a `ByVal` parameter by its argument when the argument is a plain
variable or constant, the body never writes the parameter and nothing in the body writes the argument (same write-set
test as `calls_spare`); forward-substitute a scalar local that has one definition and one use in the following
statement when no operand of the definition is written in between; let an inlined `Result` take the storage of the
assignment's destination when the destination is not read in the body. The same conditions as M1 apply for
`Volatile` and interrupt-visible variables. On the PIC18 a general `pass_retarget` like the 16F's `pass_retarget16`
(a value finished in `__An` and then copied to `D` is built in `D`) would remove most of the 92 `movff __A, var`.

**R2. Extended operands.** `sink = sink + f` (`f` an Integer, `sink` a LongInt) is 17 words:
`movff F, __A0; movff F+1, __A1; movlw 0; btfsc __A1, 7; movlw 0xFF; movwf __A2; movwf __A3`, then eight words of
add. Without the scratch: `movf F, w; addwf SINK, f; movf F+1, w; addwfc SINK+1, f; movlw 0; btfsc F+1, 7;
movlw 0xFF; addwfc SINK+2, f; addwfc SINK+3, f` (9 words; `movlw` and `btfsc` leave the carry). Five sites in b_dsp
(the three accumulates of the main loop, `Mean`, `MinMax`). Related: `sink = sink + Isqrt(1000000) + Isqrt(sink)`
keeps the running sum as four bytes in `__main__TMP` (53 words from the first call to the store). Saving the first
*result* at its own width (2 bytes), making the second call, then adding both into `sink` is about 25 words; the
rule is "an operand that reads `x` is evaluated to a temporary of its own width first, then the spine runs in `x`".
Also `If n >= r + bt`: the sum is built as `movff r -> __A` (8 words) then `addwf __A, f` (8 words); the W-routed
three-address form of P1 with `__A` as its destination is 12 words (-4 words, -4 cycles; -2 for 16 bits).

**R3. Loop ends.** `For i = 0 To 47` ends `movf i, w; xorlw 0x2F; bz out; incf i, f; bra top` (5 words, 6 cycles a
pass); the 16F form is 6 words. The variable must keep its last value after the loop (LANGUAGE.md, D33), which is
why the test comes first. When the variable is not read after the loop (the common case, and already known for L1):
`movf i, w; incf i, f; xorlw 0x2F; bnz top` (4 words, 5 cycles; correct for a limit of 255 and for a hidden variable
limit with `xorwf H, w`, because the old value is tested). 16F: `movf i, w; incf i, f; xorlw K; btfss STATUS, 2;
bra top` (5 words). Counting down, `For i = 7 To 1 Step -1` ends `decf i, w; bz out; decf i, f; bra top` and becomes
`decfsz i, f; bra top` under the same condition (-2 words, -3 cycles a pass). 34 loop ends in the four programs.

**R4. Pointer walks (M10).** Every element access in a counted loop is `movf i, w; lfsr 0, A; <op> PLUSW0` (4 words,
4 cycles) plus the 5-word loop end. `For i = 0 To 63: flags(i) = 1: Next` is 12 words and 13 cycles a pass
(`movlw 1; movwf TMP; movf i, w; lfsr; movff TMP, PLUSW0` + loop end); as `lfsr 0, flags; movlw 64; movwf H;
L: movlw 1; movwf POSTINC0; decfsz H, f; bra L` it is 8 words and 5 cycles a pass. Same for the `cnt = cnt +
flags(i)` sum, the CRC loops over `data(i)`, `Mean`/`Rms` over `samples(i)`, and (two pointers, FSR0 and FSR1) the
FIR `hist(i) * coef(i)` and `hist(i) = hist(i - 1)`. Conditions: the body has no call and no other use of that FSR,
the index is the loop variable (plus a constant), the loop variable is not otherwise needed or is kept alongside.
Smaller steps on the way: a constant stored to an element does not need the temporary (`clrf PLUSW0; incf PLUSW0, f`
for 1, `setf PLUSW0` for 255, or load the constant before the index when the index goes through an FSR add); a
loop-invariant `lfsr` inside a `While` can be hoisted when every path into the loop has it (R12, flow-aware state).

**R5. Unary operators.** `Result = Not crc` (LongWord) copies to `__A` (8 words), `comf` four times, copies out (8
words): `comf crc, w; movwf Result` per byte is 8 words, and with the following `sink = sink Xor Result` it could be
`comf crc, w; xorwf sink, f` per byte (28 -> 8 words). `v = 0 - v` (twice in b_dsp) is 10 words through `__A`:
`comf v+1, f; negf v; movlw 0; addwfc v+1, f` (4 words, the sequence `Abs` already uses). `If v < 0 Then v = 0 - v`
is `Abs` and could be recognised as such.

**R6. Compares with an operand in W.** `If data(mid) < key`: `movf PLUSW0, w; movwf TMP; movf KEY, w; subwf TMP, w;
bc` (5 words) where `cpfsgt KEY; bra` (2 words) follows the load directly; `data(j - 1) >= k` likewise. In the
bubble sort both elements are stored (`TMP`, `TMP+1`) and reloaded: `... movwf TMP; incf j, w; movf PLUSW0, w;
cpfsgt TMP; bra` is 9 words against 13. An `If a = b ... ElseIf a < b` chain on the same operands (`BinSearch`)
could share one `subwf` (Z for the first test, C for the second) instead of reading the element twice (-6 words).

**R7. Divide helpers.** `__div2` and `__div4` test the carry out of the remainder shift (`bc _L92`) and carry a
second copy of the subtract for it. With the remainder cleared on entry the carry can never be set: before shift
*k* the remainder is at most the top *k* - 1 bits of the dividend, so after the last shift it still fits the width.
The 16F `__udiv2` already has no such path. Removing it: `__div2` 28 -> 23 words, `__div4` 46 -> 37, one cycle less
per quotient bit. Check first that no caller enters either helper with a non-zero `__C` (`__divk4`, the
`Optimize = Speed` short path) and run `div_const_*`, `arith_*` exhaustively. Separately, the still-open "operand
fits a byte" item of section 3.4: `v / 10` and `v Mod 10` on a Word run the full 16-bit loop (about 19 cycles a bit).
Also `__mul2` forms the product in `__C` and copies it to `__A` (`movff` x 4, 8 words): ordering the partial
products so the low byte of `__A` is overwritten last saves about 3 words and 3 cycles.

**R8. Constant tables.** `v = SINT(idx)` builds a 16-bit index in `__A` (`movff idx, __A0; clrf __A1; bcf; rlcf;
rlcf; movlw low; addwf; movwf TBLPTRL; movlw high; addwfc; movwf TBLPTRH; clrf TBLPTRU`, 13 words). For a table
whose scaled index fits a byte: `bcf STATUS, 0; rlcf idx, w; addlw low(T); movwf TBLPTRL; movlw high(T); movwf
TBLPTRH; clrf WREG; addwfc TBLPTRH, f; clrf TBLPTRU` (9 words), or 7 when the table is placed so that it does not
cross a 256-byte boundary. `SINT(idx + 1)` right after `SINT(idx)` repeats all 13 words although `TBLPTR` already
points there after the two `tblrd*+` (M9). `movff TABLAT, __A0; ...; movff __A0, V` should be `movff TABLAT, V`.

**R9. 16F gaps against the PIC18 back end.** Counted in `a_algo` for the PIC16F18346:
* `(crc And $8000) <> 0` copies to `__A`, masks and tests both bytes (11 words); the PIC18's `and_test` gives
  `btfss crc+1, 7` (L1 is not in `codegen16`).
* `crc = crc << 1` emits `movf crc, w; movwf crc; movf crc+1, w; movwf crc+1` first (two self-copies, 4 words, in
  both arms) and a dead `movf crc+1, w` after; `t = t << 8` emits `clrf t+1; movwf t+1` and then xors a byte it has
  just cleared (`clrf t; movf t, w; xorwf crc, f`). The CRC16 bit loop is 32 words on the 16F against 15 on the PIC18.
* `sink = Crc16(48)`: `clrf __A2; clrf __A3; ...; movf __A2, w; movwf sink+2; movf __A3, w; movwf sink+3` (M5).
* Array access: `movwf FSR0L; movlw 0x20; movwf FSR0H` before every access, six times in a row in the bubble sort
  with `FSR0H` unchanged; `data(j)` and `data(j + 1)` could share one pointer with `moviw 0[FSR0]` and
  `moviw 1[FSR0]`; the swap rereads both elements (no `pass_load_reuse` on the 16F).
* 16F bank selects: 222 `movlb` in the four programs (97 in b_dsp, 5 % of its instructions). Placing the variables
  that one routine uses together in one bank, with scratch `__A`..`__D` in common RAM, is the lever; not measured.

**R10. Multiply by a constant.** PIC18 `seed = seed * 25 + 13849`, `n = n * 3 + 1`, `lcg = lcg * 5 + 1` build in
`__A` and copy back (`movff __A0, x; movff __A1, x+1`). The low byte of `x` is not read again after its `mullw`, so
`PRODL` can go straight to `x`, the high sum to `x+1`, and `+ 1` becomes `infsnz x, f; incf x+1, f`: 18 -> 13 words
for `n * 3 + 1`. `p = e * 3` stores the high byte through `__A1` (`movff PRODH, __A1; ...; movff __A1, P+1`, -2
words). `d * frac` (Integer by Byte) calls `__mul2` after zero-extending the byte: two `mulwf` inline are about 9
words and 9 cycles against the call. On the 16F `seed * 25` loads four bytes and calls the shift-and-add `__mul2`,
which always runs 16 passes; an exit when the remaining multiplier is zero (or an 8-pass entry for a byte
multiplier) halves the time for byte constants, and shift-and-add inline wins for constants with two or three bits.

**R11. `Select` and case tails.** `Select state` copies the subject to a hidden byte and tests it with `xorlw`
chains, but W is reloaded (`movf H, w`) at every second case, so half the tests cost 3 words instead of 2. For a
dense range (9 consecutive cases in `Exec`) a computed jump is about 15 words and constant time against about 23
words and up to 25 cycles. `clrf K_STATE; bra _L22` appears four times in `Machine` (tail merging, 2 words each);
`bra _L22` where `_L22:` is `return` should be `return` (same size, 2 cycles less).

**R12. Peepholes.** From the section 10 list, still present in the output: `movf X, w; addlw 1 / 0xFF` (13 sites) ->
`incf X, w` / `decf X, w` with dead C/DC; `op X, w; movwf X` -> `op X, f` with W dead (`addwf S, w; movwf S`,
`rrcf REGS, w; movwf REGS`, `addwf WREG, w` forms); the self-copy `movf T, w; movwf T` (insertion sort);
`(a And 63) >> 2` masks twice (`andlw 0x3F; rrncf; rrncf; andlw 0x3F` -> one `andlw 0x0F` after the rotates). New:
* Known-zero bytes: `clrf T` followed by `movf T, w; xorwf X, f` (or `iorwf`/`addwf` with known carry) is a no-op.
* `c = c + (v And 1)` -> `btfsc v, 0; incf c, f` (4 -> 2 words).
* `Integer(lcg >> 12)`: byte move, then a counted loop of four `rrcf` -> `swapf lcg+1, w; andlw 0x0F`.
* Arithmetic shift in scratch uses `movf __A1, w; rlcf WREG, w; rrcf ...`; the in-place form already uses
  `rlcf X+3, w` (1 word and 1 cycle less per step; four loops in b_dsp).
* `(n - 1) - i` is computed as `movf n, w; addlw 0xFF; subwf i, w; sublw 0`; `incf i, w; subwf n, w` is 2 words, and
  `n - 1` is already in the loop's hidden limit.
* `If c Then x = (x << 1) Xor K Else x = x << 1`, `c` the bit shifted out: shift once, `bnc` over the xor (CRC16
  13 -> 8 words in the bit loop, CRC32 21 -> 14).
* Peephole state (known W, known FSR, known scratch contents) is dropped at every label. A label reached only by
  one forward branch, or where all predecessors agree, can keep it: this removes the repeated `movf mid, w;
  lfsr 0, data` in `BinSearch` and the `lfsr` inside the sieve's `While`.

**R13. Divide and `Mod` apart.** `ToDec` stores `v Mod 10` into the buffer and then computes `v / 10`: two
`__divk4` calls per digit because a statement sits between them. Carrying the quotient across the store (it touches
only `TMP`, `WREG` and FSR0) or pairing them in the IR removes one call (13 words and one 32-bit divide per digit).

**R14. Signed compare with a constant.** `If pidI > 2000` is `movf x+1, w; xorlw 0x80; movwf __D2; movlw lo;
subwf x, w; movlw hi^0x80; subwfb __D2, w; bnc` (8 words). For a non-negative constant, `btfsc x+1, 7; bra skip`
followed by the unsigned compare (5 words) is 7 words, usually fewer cycles, and needs no `__D2`; a negative
constant uses `btfss`. When the low byte of the constant is 0 (`out > 4095` is `out >= 0x1000`) the low subtract is
emitted as `movlw 0x00; subwf x, w` and can go: `movf x+1, w; xorlw 0x80; addlw -(hi^0x80)` and one branch
(4 words). The same low-byte rule applies to unsigned compares.

**R15. Small items.**
* Start-up zeroing emits one 5-word loop per run of variables (two on the PIC18, two loops and six `clrf` on the
  16F in a_algo); runs separated by a few bytes that are initialised afterwards anyway can be one loop.
* `opt::coalesce_results` takes only a local of the same type: `Result = a` with `a` a `ByVal` parameter (`Gcd`)
  and `Result = r` with `r` wider than `Result` (`Isqrt`, `Rms`: the low bytes could be the result) still copy
  (4 words each).
* `ToDec` clears its 12-byte local array on every call (5 words and 40 cycles); `may_read_unset` handles scalars only.
* Element updates with a constant index (`regs(0) = regs(0) << 1`) go `movf; addwf WREG, w; movwf` instead of the
  one-instruction in-place form scalars get.
* `Fib`'s `t = a + b; a = b; b = t` is 28 words; per byte `movf b, w; addwf a, w; movff b, a; movwf b` is 20
  (`movff` leaves the carry), a pattern match on a rotate of three variables.

### 12.3 Suggested order

1. R7, R12, the `bra`-to-`return` part of R11 and the `rlcf f, w` item: small, local, and checked by the existing
   exhaustive arithmetic tests.
2. R3 (needs only the "not read after the loop" fact that L1 already computes), then R5, R6 and R14 in `codegen.rs`.
3. R1 and R2: the largest PIC18 gain; one IR pass and one peephole, with the M1 safety rules.
4. R9: the 16F ports, each one already proven on the PIC18.
5. R4 and R8 (pointer and `TBLPTR` reuse), then R10, R11's jump table and R13.

Re-measure `bench/large` on both cores and `bench/random` after each step and record the figures in
`docs/BENCHMARKS.md`.
