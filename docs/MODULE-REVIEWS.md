# Library module reviews

One library module at a time: build it, read the code it produces, and look for ways to make that code smaller or
faster. Each review records what was measured, what was changed, and what is left as an opportunity. A gap in the
compiler is fixed in the compiler when the fix is general (every program gains); a gap in the module's own source is
fixed in the module.

## Method

- **Size.** Every `tests/exec*/lib_*.bas`, the `tests/exec_*_parts/small.bas` programs and `tests/programs/library_*.bas`
  are built with the previous release and with the change, and the words are compared program by program. The script
  copies each program to a scratch folder, so the programs that need files from their own folder (`exec_glcd_*`,
  `exec_rtcc`, `exec_epaper`, `exec_pins`) are not in the count.
- **Probe programs.** The exec tests often pass constants, which the compiler folds, so they hide what a real call costs.
  A probe program calls every routine of the module with values read from ports, so nothing folds.
- **Correctness.** The module's exec tests on every part family that has one (MDB or basil-sim), new exec tests for
  each path a change touches, then the full suite (`BASIL_MDB=1 cargo test --release`).
- Words are flash words (PIC18: 2 bytes; enhanced mid-range: 14 bits).

## Summary

| # | Module | Status | Saving in its tests |
|---|--------|--------|---------------------|
| 1 | `adc` | reviewed (0.1.165) | 18F27Q10 119 → 113 words; every 16F part −5 |
| 2 | `aht30` | reviewed (0.1.165) | 796 → 712 words (−84, −11%) |
| 3 | `bits` | reviewed (0.1.165) | `lib_bits` 588 → 566; probe 860 → 787 (−8.5%) |
| 4 | `buttons` | reviewed (0.1.166) | `lib_buttons` 300 → 262; probe 342 → 296 (18F27Q10), 437 → 388 (16F18346) |
| 5 | `delay` | reviewed (0.1.167) | `DelaySeconds` 34 → 21 words (18F27Q10), 36 → 22 (16F18346); `delay_var` 36 → 23 / 36 → 21 |
| 6 | `dma` | reviewed (0.1.170) | `lib_dma` 284 → 226, `lib_dma_trig` 360 → 295, `lib_dma_move` 195 → 168 words (Q41) |
| 7 | `eeprom` | reviewed (0.1.168) | `lib_eeprom` 124 → 121 (18F27Q10), 229 → 189 (every 16F part, 197 in 0.1.168), 128 → 125 (Q41) |
| 8 | `timer` | reviewed (0.1.171) | all-routines probe 464 → 393 words (16F17146), 408 → 332 (16F18346), 332 → 300 (18F27Q10); `lib_timer_f152` 324 → 300 |
| 9 | `flashwrite` | reviewed (0.1.172) | all-routines probe 352 → 320 (18F27Q10), 353 → 322 (18F16Q41), 553 → 516 (16F17146); `lib_flashwrite` 343 → 311, 361 → 330, 607 → 566 |
| 10 | `floatlib` | partly reviewed (0.1.175) | all-operations probe 965 → 933 words (18F27Q10), 988 → 956 (16F18346) |
| 11 | `fmath` | reviewed (0.1.177) | `FSqr` one Newton step fewer (same bits); `FLog` 9 % fewer cycles and 26 words fewer (error 2e-7 → 2.5e-7) |
| 12 | `gpio` | reviewed (0.1.178) | module unchanged (three register-write routines); probe 32 → 29 words (18F27Q10) from a compiler change: dead start-up clears; 180 programs −31 words |
| 13 | `i2c` | reviewed (0.1.179) | typical use (init + `I2cWriteReg` + `I2cReadReg`) 389 → 309 words (18F27Q10), 554 → 422 (PIC16F17146, 13245, 18346), 469 → 460 (Q41); all-routines probe 864 → 777, 1166 → 1012 |
| 14 | `lcd` | reviewed (0.1.180) | all-routines probe 691 → 609 words, typical use 554 → 472 (18F27Q10); 885 → 789 / 689 → 608 (PIC16F17146); `lib_lcd` 693 → 599; 5 bytes of RAM |
| 15 | `oled` | reviewed (0.1.181) | no size gain; bug fixed (`OledBufText` wrapped past column 255) |
| 16 | `pinio` | reviewed (0.1.202) | 16F `PinSet` / `PinGet` 62 → 30 / 29 words, `PinOk` 20 → 8; 16F library programs −4 % (`lib_pulse` 1094 → 975, `lib_shift` 546 → 478); PIC18 `PinOk` −12 words per program; port-B-less parts no longer write port C for pins 8..15 |
| 17 | `pwm` | reviewed (0.1.203) | Probes 18F27Q10 911 → 758, 16F18346 1323 → 1106, 16F17146 1410 → 1333, 18F16Q41 1041 → 1004 words; 23 pwm-using programs 40 076 → 38 024 words (22 smaller, 1 larger); one `SetPps` for all 16F parts |
| 18 | `serial` | reviewed (0.1.204) | all-routines probe 166 → 144 (18F27Q10), 215 → 187 (16F), 167 → 145 (18F16Q41); `lib_serial` 133 → 113 / 165 → 142; `bench/modules` m1 575 → 547, m2 644 → 622, m4 488 → 470 |
| 19 | `serial2` | reviewed (0.1.205) | all-routines probe 185 → 163 (18F27Q10), 241 → 213 (16F17146, 16F18056), 186 → 164 (18F16Q41) |
| 20 | `rtcc` | reviewed (0.1.206) | all-routines probe 1487 → 1431 (18F27Q10), 1956 → 1895 (16F17146), 1628 → 1579 (18F16Q41) |
| 21 | `rtccspi` | reviewed (0.1.207) | all-routines probe 1839 → 1812 (18F27Q10), 2700 → 2664 (16F17146), 1947 → 1922 (18F16Q41) |
| 22 | `shift` | reviewed (0.1.208) | all-routines probe 570 → 524 (18F27Q10, 18F16Q41), 672 → 625 (16F17146) |
| 23 | `spi` | reviewed (0.1.209) | constant-pin programs: `lib_spi` 357 → 313 (18F27Q10), 120 → 103 (Q41), 731 → 722 (16F18056); `m4_spiflash` 470 → 436; run-time-pin probe 706 → 659 (16F17146), 417 → 425 (18F27Q10), 459 → 475 (Q41) |
| 24 | `strings` | reviewed (0.1.210) | compiler change: `Len` 17 → 12 words (18F27Q10); `lib_strings` 139 → 134, `str_basic` 542 → 532, `str_slice_ref` 629 → 559 |
| 25 | `system` | reviewed (0.1.211) | all-routines probe 299 → 278 (18F27Q10, 18F16Q41), 375 → 356 (16F17146), 418 → 389 (16F18346), 353 → 334 (16F18056, 16F15244) |
| 26 | `x10` | reviewed (0.1.212) | all-routines probe 768 → 741 (18F27Q10, 18F16Q41), 952 → 929 (16F17146, 16F18346) |
| 27 | `irremote` | reviewed (0.1.213) | all-routines probe 436 → 357 (18F27Q10, 18F16Q41), 533 → 444 (16F17146) |
| 28 | `epaper` | reviewed (0.1.214) | all-routines probe 1390 → 1167 (18F27Q10, 18F16Q41), 1950 → 1753 (16F17146); `lib_epaper` 2515 → 2307 (18F27Q10) |
| 29 | `glcd` | reviewed (0.1.215) | all-routines probe 4653 → 4354 (18F27Q10, 18F16Q41), 6715 → 6432 (16F17146) |
| 30 | `intosc` | reviewed (0.1.216) | run-time `SetClock` / `SetClockDiv` probe 152 → 137 (18F27Q10), 184 → 173 (16F17146), 149 → 141 (16F18056), 128 → 120 (16F15244) |
| 31 | `pulse` | reviewed (0.1.217) | all-routines probe 1339 → 1212 (18F27Q10), 1527 → 1390 (16F17146); `Pot` alone 325 → 254 (18F27Q10), 357 → 338 (16F17146); `PulseIn` alone 176 → 153, 213 → 176; compiler fix in `pass_repeat_test` |
| … | remaining modules | none (`floatlib` partly reviewed) | |

The compiler changes made during these reviews apply to every program. Over the 102 programs measured, 0.1.165 makes
68 smaller and none larger: 84 139 → 82 955 words (−1 184). For example `tests/programs/library_all.bas` 7302 → 7187,
`tests/exec_p180_parts/small.bas` 1692 → 1635, and `lib_i2c` on every 16F part −30.

Module 4 (0.1.166) adds: 102 programs, 69 smaller, none larger, 82 955 → 82 547 words (−408). `library_all.bas` 7187 → 7140,
`lib_pulse` 875 → 851, `lib_oled_text` (16F13) 1438 → 1423, `lib_pwm` (16F16) 1455 → 1443.

## Compiler changes found through the reviews (0.1.165)

1. **Overwritten stores (PIC18 peephole, `pass_overwritten_store`).** A store to compiler-placed RAM (`clrf`, `setf`,
   `movwf`, `movff`) that the same straight run stores to again before anything can read the byte is deleted. Found in
   `adc` (`Result = ADRESL` widens with `clrf Result+1`, then `Result.Byte1 = ADRESH` stores it again). It also removes
   loop-counter and timing-variable set-ups that `pulse` writes twice (−19 words in `lib_pulse`), and dead stores in `rtcc`
   (−16), `spi`, `glcd` and `pwm`. The run ends at a branch, a skip, a call, raw assembly, an indirect access or an
   instruction the pass does not understand; the store's own flags must be dead, and its own read must have no side
   effect (`movff SSP1BUF, X` reads a FIFO, `movff POSTINC0, X` steps FSR0: both are kept).
   A read the pass cannot place (an offset spelled `A+1+1`, which an array element's `AsWord` alias produces, or an
   absolute address) counts as a read of the byte (`tests/exec/direct_ops_overlap.bas` caught this).
2. **`bit = 0` / `bit = 1` on the enhanced mid-range core (`codegen16`, `cond_jump`).** A bit compared with 0 or 1 was
   turned into a byte (`movlw 0` / `btfsc` / `movlw 1` / `movwf __A0`) and compared; it is now one bit skip on the bit
   itself. `While AdcGo = 1 : Wend` went from 8 instructions per pass to 2. This is the largest gain of the release on
   the 16F parts (−547 words over the 16F lib tests: `flashwrite` −25..−33, `i2c` −30, `timer` −24, `eeprom` −10..−18).
3. **Skip over a branch on the enhanced mid-range core (`pass_skipbr_over_branch`).** `btfss f,b` + `bra out`, `bra top`,
   `out:` (the empty `While bit` loop) becomes `btfsc f,b` + `bra top`. The PIC18 had this pass; the 16F did not.
4. **Unsigned byte `x >> k` on the PIC18 (`shift_byte`).** The shift is a right rotate and a mask; the rotate is now the
   shortest of `rrncf` × k, `rlncf` × (8 − k) and `swapf` plus the rest. `x >> 7` is 2 words instead of 8, `x >> 6` 3
   instead of 7, `x >> 5` 3 instead of 6.
5. **Byte shifts on the enhanced mid-range core (`codegen16` `shift`).** Done in `WREG` (`lsrf`/`asrf`/`addwf WREG, w`)
   instead of `movwf __A0`, a shift per place on `__A0` and `movf __A0, w` (2 words fewer on every right shift); `swapf WREG` and
   a mask stand for the first four places of an unsigned shift (`x >> 4` and `x << 4` are 2 words instead of 6 and 4),
   and an unsigned shift by 7 is two rotates through carry and a mask (`rlf`/`rrf WREG, w`, 3 words).

New test: `tests/exec/lib_bits_rot.bas` (word rotates with the carried bit set and clear, `SwapBytes`, `GetBit` with
run-time arguments, byte shifts by 4..7 both ways, signed byte shifts, and a loop polling a bit). Checked on 18F27Q10, 18F16Q41, 16F18346,
16F17146 and 16F15244. New unit test: `peephole::tests::overwritten_store_is_deleted`.

Left for later (from the review of these changes): `pass_skipbr_over_branch` and the PIC18 `pass_skip_over_branch` do
the same inversion and could be one pass that takes both item kinds; `pass_overwritten_store` scans one straight run,
where `byte_dead_paths` follows both sides of a branch (it would need a flag to treat a `return` as a read for globals).

## Compiler changes found through the reviews (0.1.166)

1. **Unsigned compares with 0 and 1 are zero tests (both back ends).** `x > 0`, `x >= 1`, `0 < x`, `1 <= x` on an unsigned
   variable are `x <> 0`, and `x <= 0`, `x < 1` are `x = 0`. The PIC18 had turned `x > 0` into `x >= 1` and subtracted
   (`movlw 1`/`subwf`/`movlw 0`/`subwfb`/`bc`, 5 words for a Word); it is now the OR test (`movf`/`iorwf`/`bnz`, 3), and
   one byte is `movf x, f` and a branch (2, was 3). On the enhanced mid-range core the value had been copied to `__A`
   and subtracted. Found in `Counter`'s `While ms > 0`.
2. **ByRef pointer straight to FSR, and its reload dropped (PIC18).** Reaching a `ByRef` parameter's byte copied the
   pointer to `__A` and then to FSR0 (`point_fsr_a`); a plain pointer (no index, no offset) now goes straight to FSRn.
   `pass_redundant_lfsr` treats `movff S, FSRnL` / `movff S+1, FSRnH` as it treats `lfsr`: a second pair while FSRn still
   holds S goes. The value is forgotten at a label, a call, a taken branch, any other mention of the FSR, and any
   instruction that may write S or S+1 (an inlined second call stores a new pointer).
3. **`p = p ± 1` on an indirect byte is `incf`/`decf INDF0, f`** (was `movlw 1` / `subwf INDF0, f`).
4. **Step then test (`pass_repeat_test`).** `decf x, f` (or `incf`, `addwf`, `andwf`, ... with `x` as destination) followed
   by `movf x, f`: the first already set Z (and N) from x, so the test goes (`s = s - 1 : If s = 0`).
5. **`x = 1` and `x = 255` on a byte are `decf`/`incf x, w`** and one branch (2 words, was `movf`/`xorlw`/branch); in a
   wide equality each byte that is compared with 0x01 or 0xFF gets the same (both back ends). On the PIC18 two
   peepholes keep this from costing where W already holds the byte: `movwf x` / `incf x, w` becomes `addlw 0x01` (same
   W and flags; the store may then go), and `movf x, w` / `xorlw 1` / `bz` from other code becomes `decf x, w` when W and
   the carry are dead on both sides of the branch (not in a `Select Case` chain that goes on with `xorlw`).

A driver race these changes brought out: `i2c` (hardware driver) `Wait` read RXBF, then NACKIF, and reported a not
acknowledge (status 3) when the byte had not yet arrived at the first read. A one-byte read's byte (RXBF, 8th clock) and
the module's own not acknowledge of it (NACKIF, 9th) can both land between the two reads, which the shorter loop made
happen in `scripts/test_i2chw.py` at 8 MHz and 4 MHz with a 400 kHz bus (`rd1`, `rdOne` returned 3). `Wait` now reads
RXBF again when it sees NACKIF while waiting for a byte, so received data wins over NACKIF as its comment intends. The
old code was open to the same race at other timings.

New test: `tests/exec/cmp_zero_one.bas` (every zero test and its mirror forms on Byte, Word and LongWord over 0, 1, 2,
255, 256, 0x01FF, 0xFF01, 0xFFFF; byte and word equality with 1, 255, 0xFFFF, 0x01FF, 0xFF01; a ByRef countdown stepped
and tested in place). Checked on 18F27Q10, 18F16Q41, 16F18346, 16F17146, 16F15244 and 16F13145. New unit tests:
`peephole::tests::byref_pointer_reload_is_dropped`, `step_then_test_and_incdec_compares`.

## Compiler changes found through the reviews (0.1.167)

1. **Variable delays (both back ends, `delay`).** `DelayMS(v)` / `DelayUS(v)` set a 16-bit counter to `v − 1` with a
   zero guard, copied it from `__A` to `__D`, and counted down with `movlw`/`subwf`/`movlw`/`subwfb`/branch: 17
   words around the timed body for a Byte. The counter now stays in `__A`, starts at the complement of the value
   and is stepped at the top of the loop, so a value of 0 runs no pass and needs no separate test. A Byte steps with
   `incfsz`/`bra` (3 cycles a pass, 5 words with the set-up); a Word with an `incfsz` chain (`incfsz lo` / `bra back` /
   `incfsz hi` / `back: bra top`) whose two paths back both take 5 cycles (7 words). A variable `DelayUS` now needs
   12 MHz (Byte) or 20 MHz (Word) instead of 24 MHz (PIC18) and 28 MHz (16F).
2. **Constant delays (`emit_cycles`, both back ends).** A counter of 256 is set with `clrf` (1 word, 1 cycle) instead
   of `movlw 0` / `movwf`. (A counter loop would also be a word shorter than the `bra`s for 10 to 12 cycles, but it takes a `__D` byte, which a handler then has to save; left as is.)
   Checked against a model of the emitted code for every count up to 3 000 000.

New tests: `tests/exec/delay_var_word.bas` and `tests/exec_p16/delay_var_word.bas` (Word counts 256, 511, 300 and 0,
Byte counts 200 and 0), `tests/exec/delay_seconds.bas` and `tests/exec_p16/delay_seconds.bas` (`DelaySeconds` of 0
and 2, `DelayNop`); cycle counts checked in basil-sim (18F27Q10) and MDB (16F17146).

## 1. `adc`

Measured on 18F27Q10 (`lib_adc`, `lib_adin`) and on each 16F family's `lib_adc` and `small.bas`.

Changed in the module:

- `Convert` read `ADRESL` into a temporary `lo` and then built `ADRESH * 256 + lo`: three `movff`s and a RAM byte. It
  now writes `Result = ADRESL` and then `Result.Byte1 = ADRESH`, which keeps ADRESL being read first (−2 words, −1 byte RAM
  with the overwritten-store pass).
- `AdcRead` (Q10 branch) kept the dropped first conversion after a channel change (erratum 1.4.4) in a local `dummy`:
  four `movff`s and two RAM bytes. It now calls `Convert()` as a statement, which discards the result (−4 words).

Left as opportunities:

- **Constants through inlined arguments.** `AdcRead(13)` inlined is `movlw 13 ; movwf ch ; movlw 63 ; andwf ch, f`: the
  constant argument is not folded into `ch And 63`, and the channel compare reloads `ch`. Same for `AdcRefFvr(4)`
  (`gain >= 4`, `gain = 0` tested at run time). A general constant propagation into inlined parameters would remove these.
- **16F: result copies.** On the enhanced mid-range core `Result = ADRESL` goes `ADRESL → __A0 → Result`, then the result
  is copied `Result → __A0/__A1 → caller` (about 12 instructions for a 2-byte value). The PIC18 back end's result
  coalescing and copy forwarding have no 16F counterpart yet; this is the largest remaining 16F cost in every module.

## 2. `aht30`

`Aht30Fetch` was 359 words, most of it the conversion of the raw readings.

Changed in the module:

- The 20-bit humidity and temperature readings were put together with 32-bit shifts and `Or`s
  (`LongWord(frame(1)) << 12 Or LongWord(frame(2)) << 4 Or ...`): two shift loops through `__A`, staging copies through a
  4-byte temporary, about 80 instructions. They are now put together a byte at a time (`raw.Byte2 = frame(1) >> 4`,
  `raw.Byte1 = (frame(1) << 4) Or (frame(2) >> 4)`, ...), which is `swapf`, a mask and an `iorwf` per byte. The results are
  bit for bit the same. `lib_aht30` 796 → 712 words.
- The simulator test has no sensor on the bus, so the conversion is checked by reading the code, not by a run (the field
  positions are those of the data sheet, Table 9 / 5.2).

Left as opportunities:

- `Crc8` (inlined) runs the 8-step loop with `k` counting up and a compare each step; a down-counter with `decfsz` would
  save 2 words and 2 cycles per bit. The `If (c And 128) <> 0 Then c = (c << 1) Xor 49 Else c = c << 1` costs 10 words;
  hand code is `addwf WREG` (bit 7 to carry), `btfsc STATUS, C`, `xorlw 0x31`: 5. Not worth asm here: the CRC runs once
  per measurement, after an 80 ms wait.
- The two `raw * 625` / `raw * 1250` multiplies use all four bytes of `raw`; its top byte is known to be 0, so 2 of the 7
  `mullw` partial products are always 0. A compiler that tracks known-zero bytes would drop them.

## 3. `bits`

Probe program (every routine, run-time arguments): 860 → 787 words.

Changed in the module:

- `Rol(Word)` computed `v >> 15` as a 7-pass word shift loop. Now `Result = v << 1` and the top bit is put back with a
  bit test (`If v.15 = 1 Then Result.0 = 1`): 2 `rlcf` and a `btfss`/`bsf`.
- `Ror(Word)` the same way round (`v << 15` was a 7-pass loop).
- `SwapBytes` built `(v << 8) Or (v >> 8)` through `__A` and a temporary; now two byte moves.
- `GetBit` tested all four bytes of `(v >> n) And 1`; only the low byte can be non-zero, so it tests `Byte(v >> n)`.
- Comments: an old search-and-replace had turned "bit" into "sq" in five comments ("least significant sq",
  "16-sq xorshift"); restored.

Left as opportunities (compiler):

- **Rotate idioms.** `Rol(Byte)` is `(v << 1) Or (v >> 7)`: about 7 instructions where `rlncf` is one; `Ror(Byte)` likewise
  (`rrncf`), and `SwapNibbles` (`(v << 4) Or (v >> 4)`, 9 instructions) is one `swapf`. Recognising
  `(x << k) Or (x >> (8 − k))` on a byte as a rotate would fix all three, and user code that writes the same idiom.
- **Multi-byte shifts by 5..7 places.** A word or long shifted by r = 5..7 (plus whole bytes) runs a loop of r passes.
  Shifting the other way by 8 − r and moving the bytes by one is shorter and faster (`Random`'s `rndState << 7` is a
  7-pass loop; it is `>> 1` and a byte move).
- **`(x And k) <> 0` with k < 256** still clears and tests the upper bytes of a wide `x`; only the low byte matters.
- `Ncd` shifts the whole 32-bit value once per bit (up to 32 passes); skipping zero high bytes first would cut the
  worst case to about 8 passes.
- `LoadBit` inlines a call of `SetBit` and of `ClearBit` and copies the arguments and the result through both frames
  (about 30 words for the LongWord form); not measured against an alternative yet.

## 4. `buttons`

Probe program (`Button` twice and `Counter` twice, every argument read from a port): 18F27Q10 342 → 296 words
(`Button` 110 → 66), 16F18346 437 → 388 (`Button` 128 → 81).

Changed in the module:

- `Button` read and wrote the caller's `state` through its pointer at every step (eight pointer loads, and the
  `ElseIf` re-read it after the decrement). It now copies `state` into a local `s` once the button is seen down, works
  on `s`, and writes it back once at the end; a button that is up, or a press that turns out to be a bounce, writes 0
  as before. `If delay = 0 Then state = 255 Else state = delay` became `s = delay : If s = 0 Then s = 255` (and the same
  for `rate`), which keeps the value in `s`. The behaviour is the same in every case; `lib_buttons` checks the held,
  released and no-repeat paths.
- `Counter` is unchanged; its `While ms > 0` gained from compiler change 1.

Left as opportunities:

- **`pinio` calls.** `Button` and `Counter` spend more in `pinio` than in themselves: `PinOk` is 20 words of three
  range compares where `pin < 24` would do on a part with ports B and C; `BindData` and `PinInput` each build
  `1 << (pin And 7)` with the `__shl1` loop; on the 16F `DataRead` is 64 words. For the `pinio` review.
- **16F `ByRef`.** The enhanced mid-range core reaches `state` through FSR with no reuse of the loaded pointer; the PIC18
  change 2 has no 16F counterpart yet.
- **Indirect step then test.** `decf INDF0, f` / `movf INDF0, w` / `bnz` (a `ByRef` byte stepped and tested): the
  `movf` is redundant, but `pass_repeat_test` only reasons about compiler-placed RAM, and W is live at the `return`.
- The 10 ms debounce wait is a cycle-counted delay; a timer would let the main loop run on. That is a design choice of
  the module, not a size issue.

## 5. `delay`

The module is two routines; most of what `Include "delay"` stands for is the `DelayMS`/`DelayUS` intrinsics, so the
review covered their code as well (compiler changes 0.1.167).

Changed in the module:

- `DelaySeconds` was `For i = 1 To s`: a loop variable, a hidden copy of the limit, and a compare and an increment
  each pass. It now counts `s` down (`While s <> 0 ... s = s - 1`): 34 → 21 words on the 18F27Q10, 36 → 22 on the
  16F18346, two bytes of RAM fewer.
- `DelayNop` was documented (manual, `LIBRARY.md`, the module) as one instruction cycle. It is a call: `rcall`/`call`
  2, `nop` 1, `return` 2, so 5 cycles on both cores (DS40002043F Table 38-2 p.626-628; DS40001839E Table 34-3 p.399).
  The documentation now says so and points to `Asm nop End Asm` for a single cycle.

Over the programs measured (112 with the delay tests): 18 smaller, none larger, 82 725 → 82 417 words (−308):
`library_all.bas` 7140 → 7081, `lib_lcd` 721 → 701, `lib_glcd` 2888 → 2872, `lib_i2c` (Q41) 435 → 421.

Left as opportunities:

- **`DelayNop` as one cycle.** A routine whose body is raw `Asm` is never inlined (`inline_single_calls` skips
  `Item::Raw`), so the call stays even when it is longer than the body. Inlining a routine whose body is no longer than
  its call would make `DelayNop` the single cycle its name suggests and save its 2 words.
- **For loop limit.** `For i = 1 To s` keeps a hidden copy of `s` although the body cannot write it (a `ByVal`
  parameter, no calls). Using the limit in place when nothing in the body can change it would save the copy in every
  such loop.
- **Byte value in W.** A Byte delay of a plain variable is `movf v, w` / `xorlw 0xFF`; `comf v, w` is one word
  shorter, with the same W and flags. A peephole would serve `Not v` in general as well.
- `DelaySeconds`' loop is tested at the top (`movf s, f` / `bnz`) after a jump in; a `decfsz` at the bottom with one
  guard would save a word. The compiler's `While` shape decides this.

## 6. `dma`

Done after `eeprom` (module 7). Tests: the nine `tests/exec_q41/lib_dma*.bas` programs (registers left behind in
MDB, bytes moved against the DMA model of `scripts/dma_sim.py`), all passing; new `addr_store.bas` for the compiler change.

Measured first: the module is already close to what the source can give. Every routine validates its arguments, picks
the channel, writes about twenty registers and starts, and the set-up of `DmaCopy`, `DmaCopyFlash`, `DmaCopyEeprom`
and `DmaOnTrigger` is similar. A shared private `Arm` routine did shrink a probe that calls all four (908 → 884 bytes,
852 with cheaper range checks) but made the programs people write larger: a test that calls one or two of them grew by
25 to 40 words (`lib_dma_abort` 150 → 190), because the single-call routine is inlined with its parameters copied
twice. **Dropped.** The module keeps one body per routine.

Changed in the module:

- `channel >= 1` / `channel <= DmaChannels` are one `And` test in every routine that has both (1 to 4 words each).
  The same for the byte count was tried and is worse: the compiler turns `count >= 1 And count <= 4095` into
  `count - 1 <= 4094` (a 16-bit subtract) where the two nested tests were a zero test and a high-byte test.

Compiler change found by reading `DmaCopy`'s call sites (both back ends): **`w = @x` and ByRef arguments**. The address
of a variable or register is a constant, but it was built in `__A` and copied out (`movlw low(x)` / `movwf __A0` /
`movlw high(x)` / `movwf __A1` / `movff __A0, p` / `movff __A1, p+1`: 6 words). The PIC18 now writes the two bytes
straight into the destination (4 words); the PIC16 does the same through its constant path (the 16F18346 ByRef call
was 37 words, now 28). Every ByRef call and every `@x` assignment gains.

Over the 110 library programs against 0.1.167: 37 smaller, none larger, 82 283 → 81 323 words (this step −415 after
0.1.169). `lib_dma` 284 → 226, `lib_dma_trig` 360 → 295, `lib_dma_trigmove` 321 → 285, `lib_dma_move` 195 → 168,
`lib_dma_eeprom` 201 → 177, `lib_dma_flash` 190 → 174; outside the DMA module `lib_buttons` 255 → 223,
`lib_strings` 165 → 145, `lib_aht30` 704 → 680, `lib_glcd` 2872 → 2848, `library_all.bas` 7081 → 7045,
`library_q41.bas` 5346 → 5316.

Left as opportunities:

- **Parameters copied twice when a routine is inlined.** An inlined single-call routine still copies each argument into
  its parameter and then on into the next routine's parameters (`DmaCopy` → `Arm` above). Forwarding the caller's
  value (a constant, or a variable not written in between) into the callee's uses would let a layered module cost
  nothing for its layers; it is the same gap as X6 in `EFFICIENCY.md`.
- The `PRLOCK` unlock is inlined in every routine that arms a channel (11 words each); a shared routine pays only from
  the second use. The data sheet's sequence (DS40002214G Example 7-1) is unchanged.

## 7. `eeprom`

Reviewed ahead of `dma`, which the random-program comparison against XC8 pointed to (`EepromWrite` / `EepromRead` on the
16F, `docs/EFFICIENCY.md` X4). Tests: `lib_eeprom` on every family that has data EEPROM (18F27Q10 and 18F16Q41 in
basil-sim, 16F17146 and 16F18346 in MDB), `lib_dma_eeprom`, and the new `tests/exec_p16/eeprom_word_edge.bas` (16F17146,
16F18346, 16F18056 in MDB; the same program with the Q41 addresses on the 18F16Q41).

Bug fixed:

- **A word access at 65535 wrapped to byte 0.** `EepromWriteWord(65535, v)` wrote byte 65535 (refused) and then
  `addr + 1`, which is 0 as a Word, so it overwrote byte 0 and returned 0; `EepromReadWord(65535)` mixed in byte 0 as
  the high byte. Both now test `addr < 65535` before the second byte. At the last real byte the behaviour is as before
  (the first byte is stored, the second does not exist, the write returns 0).

Changed in the module:

- `EepromWrite` no longer reads the byte a second time when it already held the value: it starts with `Result = 1`
  and clears it only when the read-back after a real write differs. The skipped-write case is one read, was two.
- `SetAddr` (called from one place, with a Word argument copied through `__A` on the 16F) is part of `EepromRead`.

Compiler change (`codegen16`, `cmp_jump`): an unsigned 16-bit variable compared with a multiple of 256, or one less
(`x < 256`, `x >= 512`, `x > 255`, `x <= 511`, either way round), tests only the high byte: `movf hi, f` and a branch for
256, `movlw` / `subwf hi, w` and a branch for the others. The PIC18 had this since 0.1.164; the 16F subtracted all 16
bits through `__A` (14 words saved in `EepromRead` and `EepromWrite` together, since the module's range check is
`addr < 256` on a 256-byte part). New tests `tests/exec/cmp_hibyte.bas` (18F27Q10) and `tests/exec_p16/cmp_hibyte.bas`
(16F17146 and 16F18346): every form against 9 constants and 17 values, each answer checked against the same compare on
a LongWord copy; a one-byte change to the emitted `movlw` makes it fail with 144 wrong answers.

Probe (all five routines, values read from ports): 18F27Q10 328 → 328 bytes, 18F16Q41 332 → 332, 16F18346 291 → 285
words, 16F17146 288 → 282, with the word fix included (it costs 4 words on the PIC18 and about 19 on the 16F, which the
rest of the changes pay for). Over the 110 library programs: 18 smaller, none larger, 82 283 → 82 062 words (−221):
`lib_eeprom` 229 → 197 on every 16F part, `library_all.bas` 7081 → 7065, `exec_p183_parts/small.bas` 812 → 788.

Tried and dropped: a private `ReadAt` (the read without the address set-up) for the read-back after a write; the extra
call costs more than the 7 words of address set-up it saves (+2 words PIC18, +3 on the 16F).

Left as opportunities, worked in 0.1.169:

- **Word arguments through `__A` (16F), done.** `store` (`codegen16/stmt.rs`) evaluated a plain variable into `__A` and
  copied `__A` to the destination, so every `Word` argument to a routine (and any `w2 = w1`, `l = w`, `l = b`) cost
  four extra instructions per two bytes. A plain variable, or an unsigned narrower one zero-extended, now goes byte
  by byte through WREG (`clrf` for the upper bytes). A source that shares storage with the destination at another offset
  still goes through `__A`. Probe: 16F18346 285 → 241 words, 16F17146 282 → 238; `lib_eeprom` 197 → 189; the PIC18 had
  this already. Over the 110 library programs against 0.1.167: 21 smaller, none larger, 82 283 → 81 738 words (−545):
  `lib_flashwrite` −44, `lib_pwm` −26..−44 on every 16F part, `exec_p180_parts/small.bas` 1628 → 1595. New test
  `store_copy.bas` (`tests/exec` and `tests/exec_p16`); leaving out the `clrf` makes it fail.
- **`ie` as a bit, dropped.** A `Bit` variable is stored as a whole byte, so it saves nothing (285 words both ways);
  an alias `Dim ieb As ie.0` costs 2 words more, and restoring with `IntEn = ie` 3 more. Only a flag-bit allocation in the
  compiler would change this.

## 8. `timer`

Reviewed on request, ahead of `flashwrite`. The module is Timer0, Timer1 and Timer2 over seven register layouts
(18F27Q10, 18F-Q41, PIC16F171xx, 16F183xx, 16F152xx, 16F1805x, 16F131xx). A probe calls every routine on all seven
parts (`TimerNOnExpire` hooks included, arguments read from ports). Tests: `lib_timer`, `lib_timer12`,
`lib_timer_event`, `lib_timer_hw` on 18F27Q10, 18F16Q41 and 16F17146, `lib_timer` and `lib_timer_event` on 16F18346,
16F15244, 16F13145 and 16F18056; new `timer_read.bas`, `bool_bit.bas`, `nibble_swap.bas`.

Correctness: no defects found. Checked: Timer0 reads TMR0L first (it latches TMR0H), Timer1 on the 16F183xx has no RD16
and rereads TMR1L when TMR1H moved, the flags are cleared only after the one-shot `Expired` sees them, the gate
registers are written with the timer off and TMR1GIF is cleared after them, Timer2's `T2CON` is written last. The
register facts and bit positions in the module are unchanged and were not re-derived from the data sheets in this review.

Changed in the module:

- `Timer0Read` and `Timer1Read` build the word with `Result = TMR1L` / `Result.Byte1 = TMR1H` instead of
  `TMR1H * 256 + lo` through a local (the low byte is still read first). 11 words each on the 16F, 2 on the PIC18.
- `TimerNService` tests and clears its flag itself instead of calling `TimerNExpired`: a program that uses only the
  event hook no longer links `Expired` and saves the call and the result copy (`lib_timer_event` 31 → 26 words).
- `Timer1PulseDone`, `Timer1GateState` and `Timer2Running` are `Result = bit = value`; with the compiler change below
  that is 3 words, was 5 to 6.
- `Timer1StartGated` / `Timer1StartPulse` write the gate register once (`T1GCON = 128` or `144`, `Or 64` for active
  high, `Or 32` for full cycle) instead of two stores in an If/Else and three read-modify-writes.
- `Timer0Start` / `Timer0Start16` build `T0CON1` as `(prescale And 15) Or 64`.

Tried and dropped:

- `TimerNExpired` as `Result = (flag = 1)` then one unconditional clear: shorter, but an overflow that sets the flag
  between the test and the clear is lost; the conditional clear keeps it for the next call.
- `Timer1Start(prescale)` as a call of `Timer1StartSource(T1ClkFosc4, prescale)`: 9 to 10 words less when both are used,
  2 words more in the usual program that uses one of them (`lib_timer_f152` 300 → 302).
- `((prescale << 4) And 48)` for `(prescale And 3) * 16`: no change before the compiler fix below, no gain after it.

Compiler changes found by reading the probe code:

1. **Constant on the left of `+`, `And`, `Or`, `Xor` (16F).** `64 + (x And 15)` copied the value to a temporary and
   added it (`movwf TMP` / `movlw` / `addwf`); the constant now goes to the right and takes `addlw` / `andlw` /
   `iorlw` / `xorlw`. The PIC18 already did this.
2. **A Boolean from a bit test or a flag (both back ends).** `r = (bit = 1)`, `r = (x = 3)` on the 16F, and the bit
   tests on both, were a branch, `movlw 0`, `bra`, `movlw 1` (5 to 6 words); they are `movlw 0` / skip / `movlw 1`
   (3 words, no branch). Test `bool_bit.bas` compares 10 forms (with `Not`, `And`, `Or`) against the same test as an If.
3. **`w = F(...)` of a Word or LongWord result (16F).** The result was copied to `__A` and then to the destination;
   it is copied from the result variable straight to the destination (the PIC18 did this).
4. **`(x And m) * 16` and `(x And m) << 4` with `m` below 16 (both back ends).** The high nibble is clear, so the
   result is `swapf` alone: the PIC18 had `mullw 0x10` / `movf PRODL, w` (3 words with the mask, now 2), the 16F `swapf`
   and a redundant `andlw 0xF0`. `nibble_swap.bas` checks every byte against a Word computation, and that a mask of 31
   or 240 keeps its `andlw`.

Probe, words: 16F17146 464 → 393 (−15%), 16F18346 408 → 332 (−19%), 18F27Q10 332 → 300 (−10%), 18F16Q41 329 → 300.
In the timer tests: `lib_timer_f152` and `f180` 324 → 300, `f183` 204 → 185, `lib_timer_event` 31 → 26, `lib_timer` 75 → 72.
Over the 110 library programs against 0.1.167: 66 smaller, none larger, 82 283 → 80 421 words (−1 862).

Left as opportunities:

- **Bank switching on the 16F.** Each parameter lives in bank 0 and each timer register in bank 3 to 7, so a routine
  that copies parameters to registers alternates `movlb 0` / `movlb n` (about a third of `Timer1StartPulse`). Placing
  parameters and locals of small routines in common RAM (70h to 7Fh) would remove most of them.
- **Constant multiply on the 16F.** `x * 3` is the eight-pass shift-and-add loop; two shifts and an add would be 4 words.
- **Parameters copied twice when a routine is inlined** (as in module 6).
- `Timer2Start` and `Timer2StartLimit` repeat the same register writes; sharing them costs words in programs that use only one.

## 9. `flashwrite`

The module is the program-flash self-write of the 18F27Q10 (NVMADRU, sector erase and read), the 18F-Q41 (NVMCMD) and the
PIC16F171xx / 183xx / 1805x / 131xx / 152xx (row of 32 words with write latches). A probe calls every routine on 18F27Q10,
18F16Q41, 16F17146, 16F18326 and 16F15244 with the address and value read from ports. Tests: `lib_flashwrite` on all six
families (`exec`, `exec_q41`, `exec_p16`, `exec_p13`, `exec_p152`, `exec_p183`); new `narrow_shift.bas`.

Correctness: no defect found by reading. Checked: interrupts are restored as found on every exit, the two NOPs after each
self-write instruction on the Q10, NVMERR / WRERR cleared before and read after each operation, a read-back verifies each
write, and the 16F row modify (row to a RAM image, erase, 32 latch loads, write). The register facts, unlock bytes and
errata notes in the module were not re-derived from the data sheets in this review.

Changed in the module:

- `FlashEraseSector` loads NVMADR from the sector number (`NVMADRU/H = sector`, `NVMADRL = 0` on the PIC18, since a sector
  starts at byte address 256 × s; `NVMADRH/L` from `sector >> 3` and `sector << 5` on the 16F) instead of shifting it to a
  word address and shifting that back apart in `SetAddr`.

Compiler changes found by reading the probe code:

1. **Low byte of a 16-bit shift by a constant (both back ends, `lower::narrow_shift`).** `Byte(x << k)` is `Byte(x) << k`;
   `Byte(x >> k)` is the high byte shifted by `k - 8` for `k` of 8 or more, and for `k` of 4 to 7 the low byte shifted right
   Or the high byte shifted left by `8 - k`. The bytes are read in place. `SetAddr` on the PIC18 was three shift loops (34
   words), now 16. Only a program variable (a device register pair such as TMR1 is read low byte first, whatever the
   shift), and below 4 places the 16-bit shift is shorter, so it stays. Signed `>>` keeps its arithmetic shift of the high byte.
2. **A Word against a constant of a wider type (both back ends, `lower::binary`).** `addr >= _FlashBytes` (a LongWord
   constant) compared four bytes (16 words on the 16F); an unsigned value against a constant that fits its width is now
   compared at its own width.
3. **Constant propagation through byte-part loads (`opt.rs`, `byte_part`).** Item 1 turns `Byte(count >> 8)` into a load of
   byte 1 of `count`; a parameter or variable with a known value now gives that byte's value too, or calls such as
   `DmaCopy(.., 5)` would no longer fold (the first version made `lib_dma_srcmove` 118 → 134).
4. **16F `eq_jump` with a constant on the left and a computed right side** (`70000 = x` for a Word `x`) hit an
   `unreachable!` and stopped the compiler; the operands are swapped first. Found by `narrow_shift.bas`.

Probe, words: 18F27Q10 352 → 320, 18F16Q41 353 → 322, 16F17146 553 → 516, 16F18326 554 → 517, 16F15244 558 → 521.
`narrow_shift.bas` checks `Byte(x >> k)` and `Byte(x << k)` for every `k` (Word and Integer) and the Word-against-constant
compares in both operand orders against the same value computed through a Word or LongWord variable. Over the 102 library
programs against 0.1.171: 14 smaller, none larger, 80 421 → 80 062 words (−359).

Left as opportunities:

- **Copies on the 16F.** `SetAddr` still copies its argument twice and `FlashWriteWord` moves `value` to a temporary for
  the read-back compare (the missing 16F copy forwarding, as in earlier modules).
- **`FlashUpdateWord` on the 16F** loads each latch through `SetAddr` (a call and two stores per word); writing NVMADRL
  alone in the loop would be shorter, at the cost of a second copy of the address set-up.
- A right shift by 1 to 3 places of a Word still runs as a 16-bit shift on both back ends.

## 10. `floatlib` (started 2026-11-11, 0.1.175)

Probe: every Float operation (`FFromLong`, `Float(byte)`, `+ - * /`, `LongInt()`/`Byte()`/`Word()` of a Float, three
compares, `-`, `Abs`) on values read from ports, so nothing folds. Baseline 965 words (18F27Q10) and 988 (16F18346).

- **The library routines are already tight.** `FAdd`, `FMul` and the rest are hand-written assembly on the scratch
  registers; reading the PIC18 output found nothing worth a change.
- **Gap found, in the compiler:** after each Float call the result sits in `__A0..3`, is stored to the variable, and the
  next statement (`c = c * b`) loads the same variable straight back into `__A0..3`: 4 `movff` words per chained
  operation. `pass_copy_back` already removed this inside one statement but forgot every pair naming a scratch byte at a
  statement end.
- **Change (PIC18):** `pass_copy_back` keeps a pair across a statement end when its scratch byte was last written by a
  call whose result is in the scratch registers. No peephole pass can delete a call's write, so the "no scratch value is
  carried past a statement" rule of the module notes still holds for everything else. A write to the scratch byte or the
  variable, a label, raw assembly, an unknown instruction or any other call drops the pair.
- **Change (16F):** new `pass_copy_back16`, the same rule for the byte copy `movf s, w` / `movwf d`: the `movwf d` is deleted
  when `d` already holds `s`; the `movf` is left to the `WREG` passes. It runs in `optimise16` before them.
- **Sizes:** probe 965 → 933 words (−32, 18F27Q10), 988 → 956 (−32, 16F18346).
  The 102-program size comparison of earlier reviews was not rerun for this change.
- **Tests:** new `tests/exec/float_chain.bas` (a chain of `+ * / -` through one variable, bit patterns checked; basil-sim
  and MDB on the 18F27Q10, MDB on the 16F17146 through `P16_PORTABLE`, at -O1 and -O0). Full `BASIL_MDB=1 cargo test --release` passes.

- **16F copy forwarding (general, found with `bench/random` seed 8):** `pass_forward16` reads `s` for `movf d, w` after
  `movf s, w` / `movwf d` while neither byte has changed, and `pass_dead_temp_stores` deletes `movwf` to a compiler
  temporary (`F__TMP`) that is not read again (temporaries are never address-taken). Random seeds 1-12 on the
  16F18346: 6441 -> 6334 words (-107, -1.7%); the Float probe is unchanged.

Read for gaps on the PIC18 side with nothing worth changing: `Pack`, `FromMag`, `FToLong`, the `FFrom*` entries, `Cmp`,
`FSign`, `FScale`. One saving left unapplied: the two's-complement negate in `FFromLong`/`FToLong` could use `negf`
(2 words each), but DS40002043F p.661 does not say how `NEGF` sets C, so it needs an MDB check before use.

Left as opportunities:

- The 16F routines (second half of `lib/floatlib.bas`) were not read.

## 11. `fmath` (done 2026-11-11, 0.1.177)

Every function is a fixed-length series or iteration on the Float operations of `floatlib`, so the only savings are fewer terms or steps, and each one is a question of accuracy.
Each candidate was first modelled in float32 on the host, then measured on the PIC18F27Q10 simulator.

- **`FSqr`: three Newton steps, not four.** The start guess (exponent halved) is within 4 %, each step squares the relative error. Three and four steps gave identical bits for
  453 439 host values and for 3000 values on the simulated chip (`tests/exec/fmath_sqrt3.bas`). Lossless; `lib_fmath` on the 16F13245: 148 598 → 144 152 cycles.
- **`FLog`: the s^9 term of the atanh series is dropped.** |s| <= 0.172 on the reduced range, so the term is under 3e-8 of the result. Worst relative error over 60 000 host
  points 2.0e-7 → 2.5e-7 (3.4 → 4.2 units of the last digit), inside the module's documented "few units in the sixth digit". 20 calls: 87 338 → 79 262 cycles (−9 %), 1119 → 1093 words.
  `tests/exec/fmath_log_acc.bas` holds the error to 5e-7 over 23 points (a version with one more term dropped fails it: 3 points).
- **`FExp`, `FSin`, `FCos`, `FTan`: not changed.** The next term of the `FExp` series (r^7/5040, |r| <= 0.35) is 1.3e-7 of the result and the `FSin` series' lowest dropped term is 3.6e-6, so removing
  one would cost more than two units of the last digit. `FTan` calls `FSin` twice by design; `FPow` and `FLog10` are one call plus a multiply.
- `lib_fmath` (18F27Q10, and 16F13245 as `tests/exec_p132/lib_fmath.bas`) still passes at its 4e-6 bound.

## 12. `gpio` (done 2026-11-11, 0.1.178)

Three routines (`GpioAllDigital`, `GpioPullUps`, `GpioOpenDrain`), each a few `#if _has(REG)` register writes. Probe: every routine called with values read from ports
(18F27Q10 32 words, 16F18346 29, 16F13245 27, 18F16Q41 32); a single call is inlined, so the routines cost exactly their register writes.

- **The module has nothing to save:** the generated code is one `clrf` per `ANSELx` and one load and store per mask. No change.
- **Gap found, in the compiler (PIC18): start-up clears the first statement overwrites.** Start-up zeroes every global with absolute-address `clrf 0xNNN`, so even
  `Dim a As Byte : a = PORTA` began with `clrf 0x000` and then `movff PORTA, P_A`. `pass_overwritten_store` could not relate `0x000` to the symbol `P_A`, and treated an absolute
  operand as a possible read. It now resolves such a `clrf` to the user variable that lives there (`abs_var`) and steps over the other start-up clears (they are writes to their own
  byte). Only when `Env::zero_abs` holds: **the program has no interrupt handler and no linked C code**, because the zero start value is a guarantee of the language that a
  handler could observe before the first store. Volatile variables are not in `plain`, so they keep their clears; so do a byte read before it is written and the untouched bytes
  of a partly written Word (`tests/backend.rs`, `startup_clears_are_kept_where_a_read_can_see_zero`; unit test `startup_clear_is_deleted_only_when_nothing_can_see_it`).
- **Sizes:** probe 32 → 29 words. `tests/exec` and `tests/programs`, 180 programs built with the previous and the new compiler: 251 881 → 251 850 words, 19 smaller, none larger.
  The gain is a word or so per global that is assigned before it is read, in programs without a handler.
- **Not done:** the same dead `clrf` exists on the enhanced mid-range core (`clrf 0x070` before `movwf P_A`); that core has no overwritten-store pass and its bank
  selects make the byte identity harder, so it was left. An inlined routine still copies each `ByVal` argument into its parameter slot (`movff P_A, MASKA`, then
  `movf MASKA, w`); substituting the argument for the parameter when a call is inlined would save the copy (6 words in the probe) but is a larger change.

## 13. `i2c` (done 2026-11-11, 0.1.179)

Three implementations behind one API: the MSSP1 host (18F27Q10 and every PIC16F), a software host on two pins (PIC18-Q41) and, with `#option I2c = Hardware`, the Q41's I2C1
peripheral (block routines only). Two probes per part: A calls every routine with values read from ports; B is typical use, `I2cInit(100000, ...)`, `I2cWriteReg`,
`I2cReadReg` with constants. Words before and after:

| Part | A before → after | B before → after |
|---|---|---|
| 18F27Q10 | 864 → 777 | 389 → 309 (−21 %) |
| PIC16F17146, 13245 | 1166 → 1012 | 554 → 422 (−24 %) |
| PIC16F18346 | 1162 → 1008 | 554 → 422 |
| 18F16Q41 (software host) | 876 → 863 | 469 → 460 |

- **`SetPps` was a quarter of probe B** (96 words on the Q10, 134 on the PIC16F17146): a comparison chain with one branch per pin. The `RxyPPS` registers are contiguous from `RA0PPS` in pin
  order on every part (checked in all 48 device files that have them: 0E90h, 1D8Ch, 1F10h, 0201h, 0EE2h), so one write through an FSR does it. PIC18: FSR2 saved and restored, as module
  `Pwm` already did (24 words). Enhanced mid-range: `Asm` block at FSR0, 12 words; the block clobbers W, STATUS and BSR (what the compiler assumes of every `Asm` block) and FSR0 is
  compiler-owned, never live across a statement (ABI.md). `banksel` before each parameter read, as the two bytes may be in different banks.
  Tests: `tests/exec_p16/i2c_pps_edges` (RA0, RA5, RC0, RC5), `tests/exec_p132/i2c_pps_edges20` (RB4, RB5, RC6, RC7), `tests/exec/i2c_pps_edges_q10` (RB0, RB7, RC0, RC7): the pin gets the SCL / SDA
  code, its neighbours stay 0, `I2cOff` gives it back. With an off-by-one in the address each of them fails (checked), and they run on six PIC16 families.
- **`I2cWriteReg` and `I2cReadReg` repeated the Start / address / register sequence of the block routines' `Open`**; they call it now (−9 words each on the Q10, −10 on the PIC16F17146; the Q41 software
  host shares the code, −9). `I2cReadReg` does not call `I2cReadRegs`: that would allocate the 8-byte `I2cBuf` in programs that only read single registers.
- **Left as opportunities:** `PinSetup` (43 words on the PIC16F17146: `TRISx` and `ANSELx` are contiguous too, so the same FSR scheme would take it to about 25) and `PinOk` (35 words, a mask test would be
  shorter); about 3 % each of the typical program. **The same comparison chain is in `spi` (`SetPps`, both cores) and `pwm` (enhanced mid-range)**: the same change applies, to be measured in their reviews.
  The software host's `Half` delay and the 16-bit bounded waits were left as they are: they set the bus timing and the timeout behaviour.

## 14. `lcd` (done 2026-11-11, 0.1.180)

HD44780 4-bit driver on six pins through `Pinio`. Probes (18F27Q10): A calls every routine with values read from ports, B is typical use (`LcdInit`, `LcdWrite("Hello")`, `LcdGoto`,
`LcdWriteWord`). Words before and after:

| Part | A before → after | B before → after | `lib_lcd` |
|---|---|---|---|
| 18F27Q10 | 691 → 609 | 554 → 472 (−15 %) | 693 → 599 |
| PIC16F17146 | 885 → 789 | 689 → 608 | |

`tests/programs/library_all` 6900 → 6776, `library_q41_small` 5002 → 4887.

- **The pin-claim bookkeeping was the cost, not the display code.** `Claim` kept a 32-bit set of used pins (`LongWord(1) << pin`: a 4-byte mask, `__shl4`, 57 words), and `LcdInit` called it six
  times. The six pins are now one `pins(6)` array: `LcdInit` checks each with `Pinio.PinOk` (the part's own port test, which replaces the two `#if _has(LATx)` copies in `Claim`) and compares it
  with the pins before it; the set-up, and the four data pins of `Nibble`, are loops over the array instead of six and four unrolled `PinSet` calls (`Nibble` 47 → 39 words).
  Five bytes of RAM fewer (`used`, `shown` and six pin variables → six bytes).
- **`shown` was dead state**: `LcdDisplay` built the instruction in a module variable nothing else read; it is a local now, and `LcdInit` sends the literal 0CH.
- **Behaviour change, deliberate: a refused `LcdInit` disables the module.** Before, a refused call (bad pin, shared pin, `lines` 3) left `ready` true and the old pins in place, but had already
  overwritten the claimed-pin set; now `ready` is cleared first, so the other routines do nothing until a call succeeds rather than driving pins of a set-up the caller just tried to replace.
  `tests/exec/lib_lcd_refuse` covers it, a pin above 23 in each of the six positions, a shared pin in seven pairs (including the last pin against each other one), and the disabled state afterwards;
  it fails on the old module (the display pins are still driven after the refused call). Runs on 18F27Q10, 18F16Q41 and the PIC16F17146, 18346, 13245.
- **A bug found in the first version of the change, kept in mind:** the duplicate loop `For j = 0 To i - 1` runs 255 times when `i` is 0 (a Byte); it is a `While j < i` loop. The 18F27Q10 run of
  `lib_lcd` caught it, the 18F16Q41 run did not (the stray reads happened to match).
- **Timing is unchanged where the data sheet constrains it**: the enable pulse, the 50 us / 2 ms / 5 ms / 150 us waits and the 50 ms power-up wait are the same; `Nibble`'s loop adds a few cycles
  between data changes, which only lengthens the data set-up time.
- **Not changed:** `LcdWriteWord` (already subtraction by powers of ten, no divide linked), `LcdWrite`'s per-character `ready` test (the same one `LcdWriteChar` does), the `Send` waits. The
  module is still not interrupt-safe (read-modify-write of `LATx`), as documented in the header and the manual.

## 15. `oled` (done 2026-11-11, 0.1.181)

SSD1309 128 x 64 over I2C or 4-wire SPI, text, bitmaps and a 1 KB frame buffer for pixel drawing. Probes (18F27Q10): A calls every routine, B is typical text use (`OledInitSpi`,
`OledClear`, `OledWrite`, `OledWriteWord`), C is the frame buffer (`OledLine`, `OledRect`, `OledBufText`, `OledUpdate`). Words before and after: A 1854 → 1862, B 871 → 869, C 1094 → 1099.

- **Size: nothing worth taking.** The cost is structural: both transports are always linked (`Begin` / `Put` / `Finish` 134 words, plus `I2cSend` and its helpers, about 97 words, in a program that
  only uses SPI), and the 475-byte font is 238 words. Removing the unused transport needs a compile-time choice (an `#option`), which is an API change; left as an opportunity. The pixel code is
  already a multiply by 128 and one shift loop (47 words). `Begin` now sends the I2C control byte with one `I2cSend` call instead of two (−2 words in B).
- **Bug fixed: `OledBufText` wrapped past column 255.** `x` is a Byte, so a string longer than 42 characters drew its 43rd character at column 2, and `OledBufChar` at `x` above 250 put its
  columns on 0..4. `OledBufText` stops at column 128 and `OledBufChar` ignores a character whose `x` is above 127 or `y` above 63. `tests/exec/lib_oled_text` covers the long string, the
  off-screen `x` (128 and 250) and `y` (250); it fails on the old module (`LT_WRAP: want 0 got 1`). A and C grow by 8 and 5 words for the guards.
- **Not changed:** `OledRect`, `OledFillRect` and `OledBufBitmap` still wrap when `x + w` or `y + h` pass 255 (documented for the rectangles); the SSD1309 command values were not re-read
  against the data sheet in this review.

## 16. `pinio` (done 2026-11-12, 0.1.202)

Run-time pin access by number: `PinSet`, `PinGet`, `PinOutput`, `PinInput`, bound pins for `shift` / `pulse`, and whole-port access for `glcd`. Probes: A calls every routine with values read from ports. Words before and
after: 18F27Q10 435 → 423, 16F18346 516 → 437. Library programs (copies of `tests/exec/lib_*.bas`, built for the part named): PIC18 `lib_lcd` 585 → 573, `lib_shift` 415 → 403, `lib_pulse` 730 → 718,
`lib_rtccspi` 442 → 430, `lib_glcd` 2726 → 2714 (nine programs smaller, none larger); PIC16F17146 `lib_pulse` 1094 → 975, `lib_shift` 546 → 478, `lib_lcd` 753 → 711, `lib_rtccspi` 684 → 643, `lib_buttons` 287 → 260,
`lib_glcd` 4104 → 4048 (total of eight 10 918 → 10 477, −4 %); PIC16F18346 11 030 → 10 552.

- **16F `PinSet` and `PinGet` in assembler (62 → 30 and 62 → 29 words).** The PIC18 routines already went through FSR0 (0.1.125); the 16F ones were the straight comparison chain with a shift loop and a banked
  read-modify-write per port. LATA, LATB, LATC (and PORTx) are consecutive on every supported part, so the port is `LATA + (pin >> 3)` through FSR0, and the mask `1 << (pin And 7)` is built from the three
  low bits of the pin by conditional shifts (bit 2 as a nibble swap), with no loop and the pin left alone. The addresses were read from all 47 device files.
- **`PinOk` is one comparison (20 → 8 words).** It was three chained comparisons; the part has ports A, A + B, A + C or A + B + C, so it is `pin < 24`, `pin < 16`, a bit test, or `pin < 8`.
- **Bug fixed: `PinOutput` / `PinInput` on a part without port B.** The chain ended in `ElseIf pin < 24`, so pins 8..15 changed port C (PIC18F04/05/06Q41, PIC16F13123/13124/13125/13224/13225, 16F15223/15224, 16F17126,
  16F18323..18326). The module documents that such pins are refused (`PinSet` / `PinGet` already did). They are now ignored; the guard exists only on those parts.
- **Tried and dropped: `PinOutput` / `PinInput` in assembler.** 33 / 38 → 31 / 31 words on the PIC18 and 45 / 50 → 45 / 45 on the 16F, but `lib_buttons` grew 222 → 249: a call with a constant pin is folded
  into a private copy of a Basic routine (6 words for `PinInput`), which an `Asm` routine cannot be. For the same reason a constant-pin call of the 16F `PinSet` / `PinGet` is now the 30-word routine instead of
  a small folded copy; the library modules keep their pins in variables, so every module gains.
- **Not done:** the whole-port routines (`PortWrite`, `PortRead`, ... about 18 words each, 8 routines, used only by `glcd`) could go through FSR0 the same way; `BindData` / `PinAddr` on the PIC18 are 24 words
  for two pin numbers that are constants in most programs.
- **Test:** `tests/exec/lib_pinio_ref.bas` runs `Pinio` against the plain-Basic reference for pins 0..35 (and 100..255), both levels, two start patterns, with `PinGet` reading back distinct patterns on each
  port (MDB mirrors LATx into PORTx for output pins). It is in the 16F portable list and passes on 18F27Q10, 18F16Q41, 18F14Q41, 18F06Q41, 18F04Q41 and 16F17146, 17126, 18346, 18323, 15244, 15223, 13145,
  13123, 13113, 13245, 18056. A mask bit changed in the 16F `PinGet` fails it (`PR_BAD=11`).

## 17. `pwm` (done 2026-11-13, 0.1.203)

Four designs: Timer2 CCP/PWM (18F27Q10 and the 16F183xx / 152xx / 18056 / 13145 families) and the 16-bit PWM modules (18F-Q41, 16F17126 / 17146 / 132xx). Probes call every routine with run-time values. Words before and after: 18F27Q10 911 → 758, 18F16Q41 1041 → 1004, 16F17146 1410 → 1333, 16F18346 1323 → 1106. Of the 24 existing programs that use `pwm`, 22 got smaller and 1 larger (`exec_p132_parts/small.bas`, +11 from array indexing in `ModuleActive`); total 40 076 → 38 024 words. `m3_motor` 771 → 742, `library_all` 6559 → 6463.

- **`pinio` instead of local pin routines.** `PinInput` / `PinDigital` are gone; the module calls `Pinio.PinInput` / `Pinio.PinOutput`.
- **`pins` slots replace the `active` bitmask.** `pins(ch-1)` holds pin + 1 for a running channel and 0 when idle, `nact` counts running channels; the `1 << n` shifts go. `PwmStart` checks for a pin collision over the four slots.
- **`PwmInit` arithmetic.** One 32-bit divide, then shifts. Checked against the original algorithm on the host over 2.4 M cases (clocks 1..64 MHz, hz 1..1 000 000): 0 differences. The frequency is still computed inside `PwmInit` from locals, because writing it from a global stopped a constant `PwmInit(hz)` from folding.
- **One 16F `SetPps`.** `RxyPPS` registers are contiguous by pin number, so one FSR0 write replaces the 16-way chains (each parameter gets its own `banksel`).
- **Tried and dropped:** lazy `PwmFrequency` (saved words in the probe, grew constant-`hz` programs by 40..60), a Word-only `PwmPercent` on 16F and Q41 (+13..+51).
- **Not done:** the Q41 / 17146 register chains (`Setup`, `SetDuty`, `LoadDuty`, `SetCon`, about 200 words); the register stride differs per part.
- **Tests:** new `lib_pwm_pins` on 18F27Q10, 16F18346 and 16F17146 (pin sweep, restart on another pin, collision, same-pin restart, init frequency and steps). Passes on the old and new library; the 16F18346 one fails on a mutated `SetPps`. `lib_pwm` passes on 16F17146, 18346, 15244, 18056, 13145, 18F16Q41 and 18F27Q10.

## 18. `serial` (done 2026-11-13, 0.1.204)

Probes call every routine with values read from ports (`SerialInit(115200)`, `SerialWrite`, `SerialNewLine`, `SerialWriteWord`, `SerialWriteHex`, `SerialAvailable`, `SerialRead`, `SerialFlush`). Words before and after: 18F27Q10 166 → 144, 16F18346 / 16F17146 / 16F18056 215 → 187, 16F15244 214 → 186, 18F16Q41 167 → 145. Programs that include `serial` (copies of the exec tests, built for their own part): `lib_serial` 133 → 113 (18F27Q10), 165 → 142 (16F17146, 16F18326, 16F18056), 164 → 141 (16F15244), `bench/modules` m1_logger 575 → 547, m2_i2cnode 644 → 622, m4_spiflash 488 → 470; the Q41 programs −7 and the `small.bas` programs unchanged (they call no digit routine).

- **`SerialWriteWord`.** The power of ten was a variable stepped down by a five-way `If` ladder (a 16-bit compare per rung, about 35 words inlined). It is now `Const Pow10(4) As Word = (10000, 1000, 100, 10)` read once per digit into a Word `d` (reading the table in the loop condition and again in the body cost two table fetches a pass and saved only 4 words), and the last digit is `48 + v` after the tens are taken out, so the `d = 1` pass, its `started Or d = 1` test and the fifth table entry go. Leading zeros are still dropped; 0 prints "0".
- **`SerialWriteHex`.** A two-pass loop (`v >> 4`, then `v << 4`) instead of the nibble code written out twice (−2 / −3 words).
- **Tried:** the table read twice per pass (−4 words only, see above).
- **Not done:** `Serial2WriteWord`, `LcdWriteWord` and `OledWriteWord` have the same ladder (`Serial2` and the others are reviewed in their own turns); `SerialInit` with a run-time baud rate links the 32-bit divide (a constant rate folds to two register writes); the 16F `SerialAvailable` stores `Result` and tests it again (`movlw 0` / `btfsc` / `movlw 1` / `movwf` / `movf` / `bz`), a code-generation matter for `Result = bit = value` followed by a test.
- **Tests:** `serial_word_digits` (18F27Q10, 16F17146) models the new digit and hex code with stored bytes (0, 7, 10, 100, 1000, 9999, 12345, 40000, 65535; `$A5`, `$0F`) and reads the last byte the library itself leaves in `TX1REG` after 65535, 40000, 9, `$AF`, `$05`. Passes on 18F27Q10, 16F17146, 16F15244, 16F18326 and 16F18056; changing the hex `+ 7` in the library to `+ 8` fails `T_L4`. The simulators do not capture UART output, so only the last byte of the library's own calls is observed; there is no Q41 copy because the simulated UART there never drains its transmit buffer.

## 19. `serial2` (done 2026-11-13, 0.1.205)

Probe calls every routine with values read from ports (`Serial2Init(115200)`, `Serial2Write`, `Serial2NewLine`, `Serial2WriteWord`, `Serial2WriteHex`, `Serial2Available`, `Serial2Read`, `Serial2Flush`). Words before and after: 18F27Q10 185 → 163, 16F17146 and 16F18056 241 → 213, 18F16Q41 186 → 164 (−22 / −28 / −22). The PIC16F183xx and PIC16F152xx parts the header comment names have no EUSART2 in the device files, so they are not probed.

- **`Serial2WriteWord` / `Serial2WriteHex`.** The same changes as section 18: a `Const Pow10(4)` table read once per digit into a Word, the last digit sent as `48 + Byte(v)`, the hex nibbles in a two-pass loop. Leading zeros are dropped; 0 prints "0".
- **Not done:** `LcdWriteWord` and `OledWriteWord` keep the old ladder for their own turns; `Serial2Init` with a run-time baud rate links the 32-bit divide, as `SerialInit` does.
- **Tests:** new `serial2_word_digits` (`tests/exec_p16`, 16F17146) reads the last byte the library leaves in `TX2REG` after 65535, 40000, 9, `$AF`, `$05` and 0. Passes on 16F17146, 16F18056 and 16F13245; changing the hex `+ 7` in the library to `+ 8` fails `T_L4`. Skipped on the parts without EUSART2 (16F183xx, 16F152xx) and on the 16F13145 list, as `lib_serial2` is. The 18F27Q10 and Q41 simulators never set TX2IF / drain the UART2 buffer, so no copy there; their digit code is the one `serial_word_digits` models. `lib_serial2` passes on 18F27Q10, 16F17146 and 16F18056.

## 20. `rtcc` (done 2026-11-13, 0.1.206)

Probe calls every public routine with values read from ports. Words before and after: 18F27Q10 1487 → 1431, 16F17146 1956 → 1895, 18F16Q41 1628 → 1579 (−56 / −61 / −49).

- **One read-modify-write routine.** `Start`, `Stop`, `Battery`, `ClearPowerFail`, `AlarmEnable`, `AlarmClear`, `AlarmPolarity`, `SquareWave`, `PinLevel` and the `RtccTrim` CRSTRIM step each read a register,
  changed bits and wrote it back with their own code. `Rmw(reg, keep, setb)` does it (value = `(old And keep) Or setb`); `WkWrite` is gone. The bus traffic is the same, one read then one write.
- **`EeGet` / `EePut`** are the wait-for-ready, transfer and copy shared by `RtccEeRead` / `RtccIdRead` and `RtccEeWrite` / `RtccEeProtect`. `RtccIdWrite` keeps its own sequence: the unlock bytes must
  follow the ready check directly, with no further EEPROM probe between them and the data.
- **Not done:** `ReadBlock` (84 words, software I2C) and `RtccSet` are the bulk of what is left; the loop shapes are those of the errata sequence and were not touched.
- **Tests:** `lib_rtcc_model` also calls `RtccEeProtect` (argument check, and a valid level), which no test reached before. The model tests pass on 18F27Q10 (optimised and `-O0`), 18F16Q41 (hardware I2C) and
  16F17146; `lib_rtcc` passes on 18F27Q10 and 16F17146.

## 21. `rtccspi` (done 2026-11-13, 0.1.207)

Probe calls every public routine with values read from ports (program words, `--report`). Before and after: 18F27Q10 1839 → 1812, 16F17146 2700 → 2664, 18F16Q41 1947 → 1922 (−27 / −36 / −25).

- **One read-modify-write routine.** The same change as section 20: `Rmw(reg, keep, setb)` replaces the read, change, write code of `RtccspiStart`, `Stop`, `Battery`, `ClearPowerFail` (`WkWrite` is gone), `AlarmEnable`, `AlarmClear`, `AlarmPin`, `SquareWave`, `SquareWaveOff`, `WdtFlagClear` and the CONTROL step of `RtccspiTrim`. Bus traffic is unchanged (one read, one write).
- **`GetByte` / `EeGet`.** One byte read into a `ByRef` value for `RtccspiReadReg`, `RamRead`, and (after the wait for a write cycle) `EeRead` and `IdRead`.
- **Not done:** `RtccspiSet` and `RtccspiAlarm` (the errata sequence and register layout are as the data sheet gives them), `EeReady` / `StatusRead` (53 words, the timing loop), `Cmd1` / `Cmd2` / `ReadBlock` / `WriteBlock` (the chip-select framing, each a different byte pattern).
- **Tests:** `lib_rtccspi_model` (18F27Q10, optimised and `-O0`) and `lib_rtccspi` (18F27Q10, 16F17146) pass; every changed routine is called by the model test.

## 22. `shift` (done 2026-11-13, 0.1.208)

Probe calls all four routines with values read from ports (program words, `--report`). Before and after: 18F27Q10 570 → 524, 16F17146 672 → 625, 18F16Q41 570 → 524.

- **`Setup`.** The pin check, the binds, the clock parked low and made an output were written four times (`PinsOk` plus the same five calls in each routine); one `Setup(d, c, bits, max)` function now does them. The data pin direction stays in the callers, so a program that only shifts out does not pull in `PinInput`.
- **`Pulse`.** The delay, clock high, delay, clock low of the two output routines is one routine.
- **Tried and dropped:** collecting `ShiftIn` bits at the top and justifying once at the end (the loop is simpler but the variable shift costs more: probe +26 words).
- **Cost:** a program that calls only `ShiftOut` once (`bench/modules/m3_motor`) is 5 words larger (742 → 747): the single-call case no longer folds the pin check as it did. Programs that use two or more of the routines gain.
- **Tests:** `lib_shift` now also refuses 9 bits on `ShiftOut` / `ShiftIn` and 17 or 0 bits on the 16-bit routines; it passes on 18F27Q10 (optimised and `-O0`), 18F16Q41 and 16F17146. `bench/large/d_ctrl` passes on 18F27Q10 and 16F17146.

## 23. `spi` (done 2026-11-13, 0.1.209)

Measured with constant pins (what programs pass) and with run-time pins (probe). Constant-pin programs: `lib_spi` 357 → 313 (18F27Q10), 120 → 103 (18F16Q41), 731 → 722 (16F18056), 614 → 613 (16F17146); `bench/modules/m4_spiflash` 470 → 436. Probe with run-time pins: 16F17146 706 → 659, 18F27Q10 417 → 425, 18F16Q41 459 → 475.

- **One `SpiInit` body for the MSSP and SPI1.** The two copies and the three copies of `SetPps` / `PinSetup` / pin checks are one source with `#if` only where registers differ; `SckCode` / `SdoCode` cover every family.
- **`SetPps` is a comparison chain again on every part (Q10, Q41 and 16F), without the port A cases where the part does not take them.** The PIC18 FSR2 routine (17 words) is smaller for run-time pins but a constant call cannot fold into a private copy of an assembler routine: with constant pins the chain is 17..38 words smaller per program. A pin that is a constant is by far the usual case. Cost: a run-time-pin call keeps the whole chain (about 100 words), and a program heavier than `SPEC_MAX_WEIGHT` (about 3000+ words) gets no private copies at all (`library_all` 6445 → 6513, `library_q41` 5012 → 5093).
- **Clock arithmetic.** `ceil(F / (4 hz)) - 1` is `(F - 1) / (4 hz)`: one add and one subtract fewer.
- **Q10 pin checks** are inline comparisons (a `PinOk` call with constants leaves its result store behind), `SpiTransfer` uses a bit alias for BF.
- **Tried and dropped:** shared `Route` function for the pin work (constant calls lose their folded checks, +91 words in `lib_spi`); FSR0 `SetPps` on the 16F and an FSR2 `PpsOff` for `SpiOff` (heavy programs gain, small ones lose); `Pinio.PinOutput` / `PinInput` instead of `PinSetup` (inlined single caller, larger alone); counting the receive timeout down.
- **Tests:** new `lib_spi_pins` (18F27Q10 and 18F16Q41): every pin as SCK then SDO with run-time pin numbers, PPS codes and `SpiOff` checked; fails on a swapped chain entry. `lib_spi` passes on 18F27Q10 (also -O0), 18F16Q41, 16F17146, 15244, 18056, 18326; `pins8/14/20` on 16F13214/13224/13244; every part-list build test passes.

## 24. `strings` (done 2026-11-13, 0.1.210)

The module is one routine, `Len`, 17 words (18F27Q10, run-time strings). Loop shapes (`For` with `Break`, `Do` / `Loop` with `Break`) were no smaller (20 and 17 words). The cost was in the compiler: `s(k)` with a Byte `k` through a `ByRef` / `ByRefConst` pointer built the address in `__A` (`movff`, `clrf`, `movf`, `addwf`, `movf`, `addwfc`, `movff`, `movff`: 8 words).

- **Compiler (`point_fsr`).** A Byte index, not scaled, into the array a pointer parameter names is now `movf idx, w` / `addwf ptr, w` / `movwf FSRnL` / `movlw 0` / `addwfc ptr+1, w` / `movwf FSRnH`: 6 words, no `__A`. Applies to every program that indexes a `ByRef` array or String by a Byte.
- **Result.** `Len` 17 → 12 words. Programs (18F27Q10): `lib_strings` 139 → 134, `str_basic` 542 → 532, `str_func` 991 → 986, `str_slice` 599 → 594, `str_slice_ref` 629 → 559, `lib_oled` 1748 → 1742. No other program in `tests/exec/lib_*`, `str_*`, `bench/large`, `library_*` changed.
- **Tests:** new `tests/exec/byref_index` (Byte indices into `ByRef` arrays, a loop index, an expression index, 255); PIC18 gate (`tests/exec/*.bas`, `bench/large`, `tests/exec_rtcc/lib_*.bas`) 207 pass. The 16F back end is not touched.

## 25. `system` (done 2026-11-13, 0.1.211)

Probe calls every routine with run-time values: 18F27Q10 and 18F16Q41 299 → 278 words, 16F17146 375 → 356, 16F18346 418 → 389, 16F18056 and 16F15244 353 → 334.

- **`SysClockFrom` reads the HFINTOSC megahertz from a `Const` table** (`MhzTab`, one per family) instead of an `If` chain: 88 → 66 words (18F27Q10). Out-of-range codes still give 0; the 16F183xx table keeps the reserved code 2 as 0, codes 7 and up as 32 MHz, and the PLL clocks from index 8.
- **`SysWakeFrom` is a four-entry table** (`WakeTab`): 21 → 15 words (18F27Q10), 26 → 14 (16F).
- **Left:** `SysResetCause` is a flag-priority chain with no shorter form; `SysWdtSleep` is already minimal.
- **Tests:** `lib_system` passes on 18F27Q10 (also -O0), 16F15244, 16F18056, 16F18346.

## 26. `x10` (done 2026-11-13, 0.1.212)

Probe calls `Xout`, `Xin`, `CodeOf` and `NumberOf` with run-time pins and codes: 18F27Q10 and 18F16Q41 768 → 741 words, 16F17146 and 16F18346 952 → 929.

- **`CodeOf` and `NumberOf` are 16-byte `Const` tables** (`CodeTab`, `NumTab`) instead of a LongWord nibble shift and a 16-pass search that called `CodeOf` each time: `CodeOf` 42 → 12 words, `NumberOf` 15 → 12 (18F27Q10, table included). Both mask their argument to 4 bits, so a value over 15 is read as its low nibble (`NumberOf` used to return 0 for a pattern outside 0..15).
- **Tried and dropped:** one `Level` routine for the two loops of `Zero` (−3 words on the PIC18, −1 on the 16F, +3 bytes of RAM).
- **Left:** `Frame`, `SendBit`, `Half` and `Zero` are already a chain of small calls; the rest is the 500 µs and 10 µs delays.
- **Tests:** `tests/exec_pins/lib_pins_model` (all 16 codes both ways, frames sent and played back through `Xin`) passes on 18F27Q10 and 16F17146.

## 27. `irremote` (done 2026-11-13, 0.1.213)

Probe calls `SonyIn` and `RC5In` with a run-time pin: 18F27Q10 and 18F16Q41 436 → 357 words, 16F17146 533 → 444.

- **One `Begin` for the start-up both decoders repeated** (pin check, input, the stuck-low test, the wait for the falling edge): the second copy of the two `Width` calls with their compares and the `PinOk`/`PinInput` calls is gone.
- **Sony threshold once.** `w * 8 > header * 3` is `w > (header * 3) >> 3` for integers; it is now computed once before the loop instead of a multiply and a three-place shift per bit.
- **Sony bits shifted in from the top** (`v = v >> 1`, `Or 2048`) instead of `v Or (1 << i)`, which called `__shl2` per bit.
- **Results as two byte stores** (`Result.Byte0`, `Result.Byte1`) from the bytes of `v`: no 7-place and 6-place word shift loops, no 16-bit mask and shift in `__A`.
- **Left:** `Width` (a 16-bit count, a delay and a `PinGet` per poll) and the 5 ms of `WaitUs` per RC5 bit are the timing itself.
- **Tests:** `tests/exec_pins/lib_pins_model` now decodes four RC5 lines (command below and above 64, toggle set, all ones, all zeros) as well as the Sony frame; the new test passes on the old library too, so the decode is unchanged. Passes on 18F27Q10, 18F16Q41, 16F17146 and 16F18346.

## 28. `epaper` (done 2026-11-13, 0.1.214)

Probe calls every public routine with run-time arguments: 18F27Q10 and 18F16Q41 1390 → 1167 words, 16F17146 1950 → 1753. `lib_epaper` (model) 2515 → 2307.

- **One `SetWindow`** (validation and the five window commands) for `EpdWindow`, `EpdFillRect` and `EpdWriteChar`: `EpdFillRect` carried its own copy of `EpdWindow`'s checks. The window ends reuse the sums `x + w` and `y + h` the check computes, and `ye = 296 - (y + h)`.
- **`PlaneBytes` (two `ByRef` bytes through pointers) is `PlaneByte(colour, p)`**, one value per plane; the fill loop writes a hoisted byte and counts down.
- **`EpdWriteChar` reads each font byte once** (a column at a time, shifted into the five-bit rows) instead of the 35 reads with a variable shift of the old row-at-a-time build; the plane polarity is two masks computed per plane (`(row << 2 And am) Xor xm`) instead of a branch chain per byte; the array clear is the one every local array gets on entry; the column and row limits are two bytes set by `EpdInit` (`tCols`, `tRows`) instead of shifts of the width and height.
- **`Setup` sends its commands from a `Const` table** (`InitTab`), and the 10 ms delay is one `Pause` routine (five inline copies of the delay loop before). `WaitIdle` counts down.
- **`EpdInit`**: the pin checks that `PinOk` repeats are gone, and `Drive` sets a pin high and makes it an output for D/C#, CS# and RES#; `CsSet` is the CS# write of `CmdBegin` / `CmdEnd`.
- **Left:** the font (475 bytes, 238 words) and the SPI calls themselves; a window outside the display is still tested with 16-bit sums, which wrap for an `x` or `y` near 65535 as before.
- **Tests:** `tests/exec_epaper/lib_epaper` (the whole command stream, plane contents, text, wrap, windows, red ink, sleep and wake, 2.13" and no-pin cases) passes unchanged on 18F27Q10, 18F16Q41, 16F17146 and 16F18346.

## 29. `glcd` (done 2026-11-13, 0.1.215)

Probe calls every public routine with run-time arguments, all three controllers initialised in one program: 18F27Q10 and 18F16Q41 4653 → 4354 words, 16F17146 6715 → 6432.

- **One read cycle per controller**: `KsIn(isData)` for `KsStatus` and `KsRead`, `TIn(cd)` for `TStatus` and `TReadData` (the two pairs differed only in the RS / C/D level).
- **One digit routine**: `Digits(v, first)` over the `Pow10` LongWord table serves `GlcdWriteWord` (from index 5) and `GlcdWriteLong` (from 0); the table entry is read once per digit and the digit is built as its character. The Word-only loop with its `If` chain for the next power is gone. A program that writes only Words now links the 32-bit routine, a little slower per digit than before.
- **`TPoint(x, y)`** points the address pointer and returns the bit with one division by the font width (`TByteAddr` and `TBit` each divided).
- **`WrapText`** is the line and screen wrap of `GlcdWriteChar` and `GlcdWriteCode`; `cols` is now set by every init (21 for the KS0108 and folded ST7920, 42 unfolded), so the text width no longer costs a division by 6 per character.
- **`Drive(pin, level)`** (set, then make an output) for `MakeOutputs` and `ResetPulse`; **`SCmd(v, us)`** for the ST7920 start-up instructions and their waits; **`HexDigit`** for the two hex digits.
- **Tried and dropped:** the two bytes of a graphic RAM word as an array indexed by `(x >> 3) And 1` instead of `wHi` / `wLo`: 15 words larger.
- **Left:** `SGlyph` and `Splice` (the ST7920's six-pixel cells straddling 16-bit words), the 475-byte font, and the clear loops, which are the display's own timing.
- **Tests:** the three model suites (`tests/exec_glcd_ks`, `_t69`, `_st79`) pass optimised and at `-O0`, and `lib_glcd` on 18F27Q10, 18F16Q41, 16F17146 and 16F18346. `lib_glcd_ks` also writes `10050`, `0` and `AB` and checks the glyph column of each cell (passes on the old library too).

## 30. `intosc` (done 2026-11-13, 0.1.216)

The start-up code is register writes with the `Clock` constants folded in (nothing to save), so the review is of the run-time routines. Probe calls `SetClock` and `SetClockDiv` with run-time values: 18F27Q10 152 → 137 words, 16F17146 184 → 173, 16F18056 149 → 141, 16F15244 128 → 120.

- **`FrqCode` searches a `Const` table** of the speeds (`MhzTab`, the OSCFRQ code is the index) instead of an `If` chain: one table per family (9 entries on the Q10, 6 on the PIC16F171xx, 152xx, 18056).
- **`Apply` on the Q10 / 16F171xx** returns one boolean expression (`Settle() And first And ...`) instead of an `If` with a `False` branch; `Settle()` is still evaluated first.
- **Left:** the `WaitSettle` poll loops (bounded, 16-bit counters) and the compile-time `#if` ladder of `ClockFrq` / `ClockDiv`.
- **Tests:** `lib_intosc`, `lib_intosc_div` (18F27Q10), `tests/exec_p152` (16F15244) and `tests/exec_p180` (16F18056) pass. New `tests/exec_p16/lib_intosc.bas` (16F17146: start-up code, 8 / 12 / 32 MHz, divider) checks the OSCFRQ / OSCCON1 values; the simulator does not raise ORDY / HFOR for that part, so the `True` result of a switch is not checked there (the previous library returns `False` there too).

## 31. `pulse` (done 2026-11-13, 0.1.217)

Probe calls every public routine with run-time values (pin, level, widths from ports): 18F27Q10 1339 → 1212 words, 16F17146 1527 → 1390. Each change was also measured with one routine alone in a program, since a helper shared by two routines costs a call in each: a split was kept only when the program that uses one routine does not grow (`Sound2` and `Freqout` with two frequencies are 3 words larger alone on the PIC18, 4 smaller on the PIC16F17146, and 61 words smaller together).

- **`Pot` multiplies in 16 bits**: `(t * scale) >> 8` is `(t >> 8) * scale + ((t And 255) * scale >> 8)`, exact for a 16-bit `t`, so the 32-bit product and shift go. `Pot` alone 325 → 254 (18F27Q10), 357 → 338 (16F17146).
- **`PulseIn` is one loop run for three phases** (wait out the level, wait for it, measure it), the pin state to wait on being `level Xor (phase = 1)`, instead of three copies of the poll loop: 176 → 153 alone (18F27Q10), 213 → 176.
- **`TwoTone` and `HalfTicks`**: `Sound2` and the two-frequency `Freqout` shared one tick loop (`mix` sends both waves, exclusive-or'ed, to the data pin; without it the second goes to the clock pin) and one half-period routine.
- **Tried and dropped:** a shared `Wave` loop for `Sound` and `Freqout` (+13 and +12 words alone, no gain together), `OpenOut` / `OpenIn` helpers for the pin set-up (+3 to +6 alone), `Span` for the three poll loops of `PulseIn` and `RCin` (+5 and +6 alone).
- **Left:** `WaitUs` (three loops of 100, 10 and 1 us), `PwmPin`, the noise generator of `Sound`.
- **Tests:** `tests/exec/lib_pulse.bas` (18F27Q10) and the pin model suite `tests/exec_pins/lib_pins_model.bas` (pulse widths 299 / 124 / 100 / 200, pin write counts of every routine) pass; the 16F17146 library programs build smaller.

### Compiler fix found by the review: `pass_repeat_test` across a statement end

`Result = Ok(p) : If Result Then ...` with `Ok` inlined to a constant became `movlw 1 ; movwf R ; bz L`: `pass_repeat_test` had dropped the `movf R, f` after `movf Ok, w ; movwf R` (the first load's flags describe `R`), then `pass_wreg` dropped `movf Ok, w` because `WREG` already held the byte and the flags looked dead at the statement end between the store and the branch, so the branch read the flags of an earlier `clrf`. `pass_repeat_test` now also deletes the statement ends between the flag-setting instruction and the instruction it makes redundant, so every other pass sees the branch that reads the flags (`tests/exec/repeat_test_fence.bas`: the guarded call was skipped before). No size change over 130 programs apart from the pulse programs.

## Next

Module 10 (`floatlib`): the 16F routines were read (`FMul`, `FAdd`, `Pack` are the PIC18 routines rewritten without a hardware multiplier, nothing worth changing). Every other module in the list is done.
