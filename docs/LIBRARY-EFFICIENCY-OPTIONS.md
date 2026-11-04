# Library efficiency options

Status: proposal, with a first measurement pass (below). Step 2 of the next step is done for `Pinio.PinSet`/`PinGet` (0.1.125, see the end).

## Current state

- `lib/*.bas` (about 11k lines) is written in Basil, so it goes through the normal optimiser and peephole passes.
- `Asm` blocks are used only where the compiler cannot match hand code: `delay`, `flashwrite`, and the PPS/FSR2 helpers in
  `i2c`, `spi` and `pwm`, plus parts of `floatlib`. This follows PLAN §7A.5.
- Runtime helpers such as `__div4` are emitted by the code generator (`src/codegen.rs`), not by library files.

## Option A: C libraries (not recommended)

- XC8 output is generally larger and slower than this compiler's output, which conflicts with the every-byte-counts goal.
- It depends on "call C functions and link C libraries" (PLAN item 5), which is not built yet.
- It would undercut "pay only for what is used" and the per-device conditional compilation of the libraries.

## Option B: targeted hand assembly (recommended, measure first)

Candidates, in order of expected payoff:

1. ~~`floatlib.bas`~~: already hand asm on PIC18 (`#if _has(PRODL)`); the Basic code is only the fallback for parts without a hardware multiply. No gain.
2. Bit-bang and byte-serial loops in `i2c`, `spi`, `shift`, `lcd`, `oled`, `x10`.
3. `pulse.bas` and `irremote.bas`, where cycle-exact timing matters for correctness as well as size.
4. Multi-byte shift and divide helpers in the code generator, which benefit every program.

Constraints:

- Asm is PIC18-specific and does not carry over to `codegen16` or other devices, so keep a Basil fallback under `#if`.
- Where the compiler can be improved instead, prefer fixing the compiler; PLAN §7A.5 says to replace asm once the compiler catches up.

## Option C: improve the compiler first

Fix the codegen/peephole gaps that make hand asm necessary, so the library stays portable and every user program gains.

## Proposed method

1. Build each module for a reference part and record words used and cycles (harness: `bench/kernels`, results in `BENCHMARKS.md`).
2. Hand-write the top candidates and compare against the compiled version.
3. Adopt asm only where the saving is clear, with a benchmark entry and a Basil fallback.

## Measurement pass (every `tests/exec/lib_*.bas` built with `basil --report`)

- The largest routines are one-time init code (`AHT30FETCH` 388 words, `PwmInit` 225, `LcdInit` 220, `SpiInit` 201,
  `I2cInit` 195, `FAdd` 176, `FMul` 158, `FDiv` 141). Asm there saves little and costs portability.
- The compiled loop code is already close to hand asm. `ShiftOut` (69 words) has the same shifts, `decfsz` delay loops and
  counted loop that hand code would have.
- The real cost is `Pinio.PinSet` (44 words), called three times per bit by `shift`, and used the same way by `lcd`, `oled`
  and `pulse`. Every call recomputes the port and mask from the runtime pin number (`1 << (pin And 7)` plus a LATA/LATB/LATC
  compare chain).

## Recommended next step

1. Resolve the pin to its LAT address and mask once per call, outside the bit loop (FSR-based `bsf`/`bcf`), first in Basic.
2. If the compiler cannot produce that, write an `Asm` fast path for `PinSet`/`PinGet` and `ShiftOut`, with the Basic version as fallback.
3. Compare words used (`--report`) and cycles (picsim) before and after; keep the change only if the saving is real.

Cycle counts have not been taken yet; the simulator now lives in the separate picsim repo.

## Result: `PinSet` / `PinGet` as PIC18 asm (0.1.125)

`Pinio.PinSet` and `PinGet` are now `Asm` on PIC18 (Basic fallback kept for the other cores). The port is `LATA + (pin >> 3)` (or
`PORTA +`), reached through FSR0, because the three LAT (and PORT) registers are consecutive on the 18F27Q10 and the PIC18-Q41 parts
(device files; the 18F0xQ41 parts have no LATB but LATC stays at LATA + 2, so those parts add a Basic check for pins 8..15).
Measured on 18F27Q10 with `ShiftOut` + `ShiftIn`: `PinSet` 44 -> 24 words, `PinGet` 39 -> 23, the program 236 -> 234 words
(`PinGet` was inlined before). Cycles for one 8-bit `ShiftOut` + `ShiftIn` went **up** a little, 2831 -> 2893 (picsim), because the mask is
built by a shift loop. The shift loops still resolve the pin on every call: hoisting the address and mask out of the bit loop (step 1)
is done in the next section. `tests/exec/lib_pinio.bas` covers the new code; MDB does not mirror LATx into PORTx, so
`PinGet` returning true was checked by hand with `--engine sim`.

## Result: bound pins in `shift` (0.1.126)

`shift` now resolves its two pins once per call (`Pinio.BindData` / `BindClk`: LATx address and mask kept in `Pinio` globals) and the
bit loop uses `DataPut`, `ClkPut` and `DataRead`, each a few asm instructions through FSR0 (other cores: they call `PinSet`/`PinGet` on the
bound pin). Passing the address and mask as arguments instead cost 70 words at the call sites, so the bound state lives in globals.
18F27Q10, one 8-bit `ShiftOut` + `ShiftIn` (picsim): 2831 -> 1933 cycles (-32%); program 236 -> 257 words (+21: the bind routines and
`PinAddr`; `PinSet`/`PinGet` are no longer linked by this program, but `lcd`, `oled` and `pulse` still use them). The bound state makes
`shift` non-reentrant, as `Pinio` already is. `lcd`, `oled` and `pulse` are converted in the next section.

## Result: `pulse`, `lcd`, `oled` (0.1.127)

`pulse` binds its pin once per routine (`BindData`; `Sound2` also `BindClk`) and its poll and toggle loops use `DataRead` / `DataPut` /
`ClkPut`. `lcd` and `oled` had their own Basic copies of `PinSet` and `PinOutput`; they now use `Pinio`'s (PIC18 asm). `lcd` drives six pins
and the bound state has only two slots, shared with `shift`, so it is not hoisted there (binding per call would also be clobbered by a
`ShiftOut` in between). 18F27Q10, the `lib_*` exec tests: `lib_lcd` 741 -> 727 words, `lib_oled` 1902 -> 1887, `lib_pulse` 766 -> 774
(+8: the bind routines, which `shift` shares) with 665413 -> 655367 cycles in that test, which only runs set-up and one `RCin`, not the loops.
