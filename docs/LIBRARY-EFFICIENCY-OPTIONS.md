# Library efficiency options

Status: proposal. Nothing here is implemented yet.

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

1. `floatlib.bas` (about 2000 lines): multiply, divide, normalise and shift loops.
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
