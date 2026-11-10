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
| 6 | `dma` | next | |
| … | `eeprom` … `x10` | not started | |

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

## Next

Module 6, `dma`, then on through the list in alphabetical order.
