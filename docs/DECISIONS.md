# Decision record

Decisions from `PLAN.md` §14. "Accepted" means the plan was approved on 2026-10-23 with the
recommendation shown; any item can be reopened.

| ID | Decision | Status | Choice | Notes |
|----|----------|--------|--------|-------|
| D1 | Implementation language | Accepted | **Rust** | Single crate `basicc` to start; split into a workspace only when a part needs to be reused (e.g. `devgen`). |
| D2 | Surface syntax | Accepted | **Swordfish-style core**, Positron spellings accepted as aliases where unambiguous | See `LANGUAGE.md` §14 for the alias table. |
| D3 | Back-end route | Accepted | **Route A (direct pic-as emitter) first**; Route B (recovered LLVM backend) evaluated at M7 | Both emit the same pic-as dialect behind one driver. |
| D4 | Calling convention / frames | Accepted (provisional) | **Static frames with overlay**, opt-in reentrant via FSR2 | Finalised in M4 after the M1 fact base; see `ABI.md`. |
| D5 | Device-file format | Accepted | **TOML** | Revisit in M2 only if TOML proves awkward for register maps. |
| D6 | Hardware flashing/test path | **Tentative (auto-approved 2026-10-23)** | MPLAB X command-line tools already installed (`/opt/microchip/mplabx`, an existing project at `~/MPLABXProjects/test.X`); confirm the actual programmer hardware at M6 | Practical: no new tool to build. The home-built Nucleo programmer only covers PIC16F17146/17124, so it is not used for the 18F27Q10. |
| D7 | Float format | **Accepted (auto-approved 2026-10-23)** | **IEEE-754 binary32**, implemented as library routines, built only when floats are used | Practical: results can be verified exhaustively on the host. The reference language's stated range (about ±1e38) differs slightly from IEEE; programs that depend on its exact format are not portable. Revisit only if size/speed measurements at M9 demand a leaner format. |
| D8 | Next micro after the 18F27Q10 | **OPEN (not needed until after M9)** | — | Gary's call, after M9. Devices are added slowly, one at a time (PLAN §9). |

## Additional decisions made in M0

| ID | Decision | Choice | Reason |
|----|----------|--------|--------|
| D9 | Entry point | **No `Main`.** Top-level statements of a `Program` run in order, after module initialisation | Both reference languages work this way; simplest mental model. |
| D10 | Case sensitivity | **Case-insensitive** keywords and identifiers; the compiler preserves the first-declared spelling in diagnostics and emitted symbols | Matches both reference languages' feel. Emitted pic-as symbols are normalised (pic-as is case-sensitive). |
| D11 | Operators on booleans vs integers | `And/Or/Xor/Not` are logical on Boolean operands, bitwise on integer operands; **mixing the two is an error** | Removes a classic source of bugs without changing common code. |
| D12 | Narrowing assignment | Constant that does not fit → **error**; non-constant narrowing → **warning** (error under `#option Strict = true`) | Safe by default, convenient when wanted. |
| D13 | Recursion | **Rejected at compile time** by default; allowed only for `Reentrant` routines | Static frames need a known call graph. |
| D14 | Line continuation | A line ending in ` _` (space + underscore) continues on the next line | Identifiers may start with `_`, so the space is required. |
| D16 | Expression evaluation width | **Context-width rule**: an arithmetic expression is evaluated at the width of the widest of its operands and its assignment target; never wider unless converted explicitly | Efficiency priority (PLAN §7A.2): `Word = Byte * Byte` is one hardware multiply, `Byte = Byte + Byte` stays 8-bit. Precisely specified in `LANGUAGE.md` §5.3. |
| D17 | Optimisation scope | **Whole-program compilation**; an `-O0` reference build is always available and is the oracle for differential testing | Enables dead-code removal, single-call inlining, frame overlay, stack proof (PLAN §7A.1). |
| D18 | Efficiency is gated by measurement | Benchmark harness (size via map file, cycles via MDB) built in **M4**; XC8 `-Os`/`-O2` baselines; targets calibrated from real numbers at M4, enforced from M5 | PLAN §7A.4. |
| D19 | Internal integer widths | **8, 16, 24 and 32 bits** are all first-class in the IR; the *language* types stay 8/16/32 (24-bit appears only as a compiler-chosen width after range analysis) | 24-bit is cheaper than 32-bit on an 8-bit core (to be re-measured in M4). |
| D15 | Vendor material | Manuals kept in `reference/` (git-ignored); nothing copied from vendor libraries or data files | PLAN §2. |

## Decisions made in M3 (front end)

| ID | Decision | Choice | Reason |
|----|----------|--------|--------|
| D20 | Positron aliases | Accept exactly `Declare Xtal`, `Symbol`, `Proc … , Type … EndProc`, `ExitProc`, `Do … Loop [Until/While]` and `Do While/Until`, rewritten to core forms by the parser | Confirmed from the Positron8 manual (LANGUAGE.md §14). Nothing else of its syntax is accepted. |
| D21 | Aggregates by reference | Arrays, `String` and structures are parameters by reference; `ByRef` is the default for them and `ByVal` is an error | "Large aggregates must be ByRef" (LANGUAGE.md §7) made enforceable. |
| D22 | Interrupt safety, conservative form | A handler may call a user routine only inside `Save … Restore` (`E-ISR-CALL`) | The "proven to use only the handler's storage" exemption needs frame overlay (M5). |
| D23 | Labels | `name:` alone on a line | `:` is also the statement separator; this removes the ambiguity without reserving more words. |
| D24 | Single-line `If … Then stmt` | Rejected with a message | Not in the grammar; keeps block structure unambiguous with `:` separators. |
| D25 | Preprocessor in M3 | Conditional compilation on `#define` names plus `#error/#warning/#option`; `#if` family reported unsupported | An expression evaluator is not needed by anything in M3–M5. |
| D26 | Overflow warnings | `W-OVF` deferred to M5 with range analysis; evaluation widths are recorded now | Warning on every `Byte + Byte` without range information would be noise. |
| D27 | Clock limit check | Not done in M3 | The maximum clock is a data sheet value that the device description does not carry yet; add a hand-entered, cross-checked field in `devgen` first (as for vectors). |

## Decisions made in M4 (back end)

| ID | Decision | Choice | Reason |
|----|----------|--------|--------|
| D28 | Calling convention | Arguments stored straight into the callee's static frame; result read from the callee's `Result` variable; nothing preserved across calls | With static frames the caller knows every address; simplest correct form, measured against alternatives in M5. Finalises D4 for non-reentrant code. |
| D29 | Data placement | The compiler assigns all data addresses (`equ`), hottest first into the Access Bank; pic-as places only code | Exact bank-select decisions at compile time; usage counts drive placement (PLAN §7A.3 #3). |
| D30 | Code placement | One absolute psect from address 0; no reset `goto` while there are no interrupts | Smallest; vectors are added with interrupts in M6. |
| D31 | Division | Truncates toward zero; `Mod` takes the dividend's sign; divide by zero gives an all-ones quotient and the dividend as remainder | Matches C and what the restoring helper produces for free; no trap code. Unsigned division/mod by a power of two is a shift/mask. |
| D32 | Port writes | A store to `PORTx` is emitted as a store to `LATx` | Avoids read-modify-write on the pins; reads are unchanged. |
| D33 | `For` loop | Limit evaluated once; constant step only (variable step is `E-BACKEND`); after a loop that ran the variable holds the last value it took (the limit for step ±1), and the counter never steps past the limit, so a `Byte` loop to 255 terminates | Needed for a correct count-down/`DECFSZ` form in M5. Post-loop value was unspecified; this is now the rule. |
| D34 | Signed multi-byte compare | Both top bytes are biased by 0x80 and compared unsigned; the overflow flag of a multi-byte subtract is not used | The simulator's `SUBWFB` overflow flag disagreed with the textbook value, and the data sheet only says OV is affected (DS40002043F p.674). The carry chain is unambiguous. |
| D35 | Unsupported constructs | Reported as `E-BACKEND` at the use, never miscompiled: structures, floats, `Bit` by reference, `ByRefConst` arrays, `@`, `Abs/Min/Max`, interrupts/events, multi-bit register fields, 3-byte registers | Scheduled for M5 (data) and M6 (interrupts). |
