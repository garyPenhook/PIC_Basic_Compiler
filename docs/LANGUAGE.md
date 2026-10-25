# Language specification (draft 0.1)

Status: M0 draft, 2026-10-23. Written in our own words from the *behaviour* described in the
reference manuals (see `PLAN.md` §2 for the clean-room rules). Where the reference manuals are
silent or we deliberately differ, the rule here is the authority.

Conventions: `[x]` optional, `{x}` zero or more, `a | b` alternatives. Keywords are
case-insensitive (D10). Device-dependent facts (RAM size, pin names, register names) always come
from the device description, never from this document.

Notation for provenance: **(SF)** = behaviour of the structured core language,
**(P8)** = convenience spelling or library command, **(NEW)** = our own rule.

---

## 1. Program structure

There are two kinds of source file.

```
program [Name]                     ' optional name
    [Device = <part>]              ' before any Include or declaration
    [Clock  = <MHz>]               ' before any Include or declaration
    { Include "module" }
    { declaration }
    { statement }
[End]
```

```
module Name
    [Device / Clock]               ' discouraged; ties the module to one part (SF)
    { Include "module" }
    { declaration }                ' Public / Private
    { statement }                  ' initialisation: runs before the main program (SF)
[End]
```

* There is **no `Main`**. Top-level statements of the program run in order after all module
  initialisation statements have run (D9). A program that falls off its end loops forever in a
  halt state (the compiler emits a self-branch), never runs off into unprogrammed flash. (NEW)
* **Declaration order is enforced**: includes, constants, types/structures, variables, aliases,
  then subroutines/functions/interrupts/events. Once the first executable statement appears, no
  further includes or declarations are allowed at that level. Identifiers must be declared before
  use; there is no forward referencing. (SF)
* `Device` and `Clock` must precede includes/declarations so the preprocessor can see them. If
  `Device` is omitted the compile fails with a clear message (the reference language silently
  defaults to a particular part; we do not). (NEW)
* The program and each module are compiled **together** (D17). A module included by several
  files is loaded once. (SF)

## 2. Lexical rules

* **Identifiers**: `[_] letter { letter | digit | _ }`. Case-insensitive (D10).
* **Comments**: `'` or `//` to end of line; block comments `(* … *)` or `{ … }`. The two block
  styles cannot be mixed to close each other but may be nested inside one another. (SF)
* **Line continuation**: a line ending in ` _` (space, underscore) continues (D14). `:` may
  separate several statements on one line. (P8)
* **Numeric literals**: decimal `100`, binary `%1010` or `0b1010`, hexadecimal `$FF` or `0xFF`, floating point
  `3.14` / `1.0e3`. (SF/P8: both reference languages use `%` and `$`; the C-style prefixes are an addition.)
* **Characters and strings**: `"A"` is a Char or a one-character String depending on context;
  `#65` is the Char with code 65; `#13 + #10` concatenates control characters. (SF)
* **Constants** `True`, `False`, `Null` (string terminator / empty string). (SF)

## 3. Types

| Type | Bits | Range / meaning |
|------|------|-----------------|
| `Boolean` | 1 | `True` / `False`; cannot hold a number |
| `Bit` | 1 | `0` / `1` |
| `Byte` | 8 | 0 … 255 |
| `ShortInt` | 8 | −128 … 127 |
| `Word` | 16 | 0 … 65535 |
| `Integer` | 16 | −32768 … 32767 |
| `LongWord` | 32 | 0 … 4294967295 |
| `LongInt` | 32 | −2147483648 … 2147483647 |
| `Float` | 32 | IEEE-754 binary32 (D7, D51): sign, 8-bit exponent, 23-bit fraction; about ±3.4e38, 6 to 7 digits |
| `Char` | 8 | one character |
| `String[(n)]` | n bytes | up to 255 characters + terminating `Null`; default size is a compiler constant (24 in the reference language) |
| `Structure` | — | see §3.3 |

(SF; the table follows the core types.) **Alternative spellings** such as
`Dim x As Byte` are accepted for declarations (§14).

The compiler uses 24-bit as an **internal** width only (D19); there is no `Word24` type.

### 3.1 Booleans and bits
A `Boolean` is the result of comparisons and of `And/Or/Xor/Not` on Booleans; it cannot be
assigned a number. A `Bit` is a numeric 0/1. Converting between them is explicit
(`Boolean(b)`, `Bit(flag)`) and free in generated code. (SF/NEW)

### 3.2 Strings and arrays
* Strings are null-terminated; `+` concatenates; `=` and `<>` compare. Element `s(i)` is
  zero-based. (SF)
* Arrays are one-dimensional: `Dim a(5) As Byte` declares **five** elements (indices 0..4);
  `Bound(a)` is the highest valid index (4), so `For i = 0 To Bound(a)` visits every element.
  (SF; the reference manual's own example shows a 5-element array iterated 0 to 4.) The size
  must be a constant expression. A constant index outside the array is a compile error; a
  variable index is not checked at run time unless `#option BoundsCheck = true` (NEW, costs code).
* `Const` arrays live in program memory: `Const T(3) As Byte = (1, 2, 3)` (the size, like `Dim`, is the element count, and must match the list). They can be read by
  index and assigned wholesale to a same-sized RAM array. (SF)
* A RAM array may be given values when it is declared: `Dim a(3) As Byte = (1, 2, 3)` (or
  `Dim a(3) = (1, 2, 3) As Byte`). The list must have exactly as many values as the array has
  elements, each known at compile time. A global array is filled once at start-up, a local one on
  every entry. Element types are the integers, `Char`, `Boolean` and `Bit`. (NEW)
* Multi-dimensional arrays are not supported in 0.1. (SF)
* A `Bit` or `Boolean` array that is only ever indexed (`a(i)`) is packed eight elements to a byte.
  A constant index is a single bit instruction; a run-time index costs a shift and a mask. An array
  that is used as a whole (passed `ByRef`, copied, cleared, given initial values) or is a structure
  field uses one byte per element instead, so it can be addressed like any other array. As the
  elements of a packed array share bytes, assigning one through a run-time index is a
  read-modify-write: do not write other elements of the same array from an interrupt. (NEW, D47)
* A bit of an element picked at run time (`a(i).3`, `p(i).Flag`) or of a `ByRef` parameter
  (`x.5`) is read and written with a read-modify-write of its byte. The index must not contain a
  call, and, as with `Inc` on an element, it is evaluated twice, so an index changed by an interrupt
  during the statement may hit a different element. (NEW)

### 3.3 Structures and unions
```
[Public|Private] Structure TName
    Field As Type
    …
End Structure
```
Fields are accessed with `.`; structures may nest and be array elements. A structure whose
fields are aliases of one field is a **union** (shared storage):
```
Structure TStatus
    Val As Byte
    Enabled   As Val.0          ' alias: shares Val's storage
    Connected As Val.1
End Structure
```
(SF.) `Clear(x)` zeroes a variable, array or structure.

### 3.4 Aliases and modifiers
`Dim Name As Existing[.modifier]` creates an **alias**: no new storage. Modifiers select a part:
`.n` / `.Bits(n)` / `.Booleans(n)` (a bit), `.Byte0 … .Byte3` / `.Bytes(n)`, `.Word0/.Word1` /
`.Words(n)`. **Promotion modifiers** make a larger view of smaller storage:
`Dim L As Arr(0).AsLongWord`. Aliases may chain. Aliasing a device register works the same way:
`Dim LED As PORTB.0` (the register name is resolved through the device description). (SF)
Zero-cost partial access is the intended way to work with multi-byte values efficiently
(PLAN §7A.2).

## 4. Declarations and scope

```
[Public|Private] Const Name [As Type] = constexpr     ' type inferred if omitted
[Public|Private] Dim   Name {, Name} As Type
[Public|Private] Dim   Name(Size) As Type
```
* Declarations are **Private** by default; `Public` exports from a module. (SF)
* A constant with no type takes its type from the expression: `5/1024` is integer arithmetic and
  yields 0; write `5.0/1024` for floating point. (SF)
* Locals declared inside a routine are visible only there. Name lookup: local, then the current
  module/program, then the public declarations of the modules it includes. (SF)
* Qualified names resolve ambiguity: `Serial.Write(…)`. A routine can be aliased:
  `Dim Out As Serial.Write`. (SF)
* **Initial values**: all variables are zero-initialised at start-up unless the declaration
  carries an initialiser (`Dim n As Byte = 10`) (NEW). The compiler removes the clearing code
  for variables it can prove are written before being read (efficiency, PLAN §7A). A routine's
  locals and `Result` are zero at **every entry** to the routine, not only the first (their storage
  is shared with other routines, §7); an initialiser is applied at every entry too.
* **`Static`** (`Static Dim n As Byte = 10`, inside a routine only): the local keeps its value
  between calls. It has its own RAM (never overlaid), is cleared and initialised once at start-up
  instead of at each entry, and is still visible only inside its routine. At module level every
  variable already lasts for the whole run, so `Static` there is `E-DIM`.
* **`Volatile`** (`Volatile Dim flag As Byte`, any scope): something outside the code the compiler
  sees (an interrupt handler, `Asm`, the hardware through an alias of a register) may change the
  variable at any time. Every read and every write in the source is performed, in source order:
  none is kept in a register, merged with a neighbour, forwarded as a constant or removed as dead
  or write-only. Without it a variable that is never read has its stores removed. Not allowed on
  an alias (`E-DIM`). `Static` and `Volatile` may be combined in either order after `Public`/`Private`.

## 5. Expressions

### 5.1 Operators and precedence
Highest first. (SF; matches the reference language's table.)

| Level | Operators |
|------:|-----------|
| 1 | `@` (address), unary `-`, unary `+`, `Not` |
| 2 | `*`, `/`, `Mod` |
| 3 | `+`, `-` |
| 4 | `<<`, `>>` |
| 5 | `=`, `<>`, `<`, `>`, `<=`, `>=` |
| 6 | `And` |
| 7 | `Or`, `Xor` |

`And/Or/Xor/Not` are **logical** on Boolean operands and **bitwise** on integer operands;
mixing the two is an error (D11). Only `=` and `<>` apply to strings. Avoid `=` on floats.

### 5.2 Short-circuit evaluation (SF)
In conditions (`If`, `While`, `Repeat…Until`, `If … GoTo`), `And`/`Or` over Booleans evaluate the
right side only if needed. The order of evaluation of operands is otherwise left to right, and the
compiler may reorder pure side-effect-free operands.

### 5.3 Typing and evaluation width (decision D16)

This is the core efficiency rule of the language.

1. **Operand types.** The type of an operand is its declared type; the type of a constant is the
   narrowest type that holds its value.
2. **Common type.** For a binary arithmetic or bitwise operation the operands are converted to the
   *common type*: the wider width; if one operand is signed and the other unsigned with the
   same width, the program is rejected (explicit conversion needed) unless the unsigned operand is
   a constant that fits the signed type; an unsigned operand narrower than a signed one is
   widened value-preservingly; a signed operand narrower than an unsigned one is rejected.
   Any `Float` operand makes the operation floating point.
3. **Evaluation width.** An integer expression assigned to a target is evaluated at
   `W = max(width of every operand in the expression, width of the target)` — and no wider.
   Examples:
   * `W = B1 * B2` (`Word` target, `Byte` operands): 16-bit result of an 8×8 multiply.
   * `B3 = B1 + B2`: 8-bit add; the result wraps modulo 256.
   * `If B1 + B2 > 300 Then`: a comparison evaluates its operands at the wider of the two sides
     (here 16 bits because `300` needs it), so the sum is evaluated at 16 bits.
4. **Overflow diagnostics.** Where range analysis shows an operation *can* overflow its
   evaluation width, the compiler warns (W-OVF) and names the operation; add a wider operand,
   target or an explicit `Word(…)`/`LongWord(…)` conversion to silence it. The programmer, not the
   compiler, decides when wrapping is wanted. This keeps the cheap 8-bit code without making
   overflow silent.
5. **Division and modulo** use the evaluation width above, truncate toward zero, and `Mod` takes the dividend's sign (D31); dividing by zero at run time gives an all-ones quotient and the dividend as remainder; division by a constant power of two
   becomes a shift; division by zero in a constant expression is an error.
6. **Shifts.** The shift count must be a constant or a `Byte`; shifting by the operand width or
   more yields 0 (or the sign for arithmetic right shift of signed values). `>>` is arithmetic for
   signed types and logical for unsigned.
7. **Comparisons** yield `Boolean`; operands are converted to their common type.
8. **Assignment narrowing** (D12): a constant that does not fit the target is an error; a
   non-constant narrowing is a warning (W-NARROW), or an error under `#option Strict = true`.

### 5.4 Calls in expressions
Functions may appear in expressions; subroutines may not. Parentheses are required when calling
with arguments and optional for a subroutine with none (`Print` or `Print()`). (SF)

## 6. Statements

```
target = expression                      ' assignment
If c Then … [ElseIf c Then …] [Else …] EndIf
If c GoTo label                          ' single-line conditional jump
Select e
    Case v {, v | lo To hi | < v | > v}  ' relational and range conditions
        …
    [Else …]
EndSelect
While c … Wend
Repeat … Until c
For v = a To b [Step s] … Next           ' v is an integer variable, not a Float
Break                                    ' leave the innermost loop
Continue                                 ' next iteration of the innermost loop
Exit                                     ' leave the current Sub/Function
GoTo label  /  label:
Inc(v)  Inc(v, n)  Dec(v)  Dec(v, n)  Clear(v)  Toggle(bit)  High(bit)  Low(bit)  Input(bit)  Output(bit)
```
(SF.) Notes:
* The limit of `For` is evaluated once, the step must be a constant, and after a loop that ran the variable keeps the last value it took, not one past it (D33). The loop variable of `For` must not be modified inside the loop (SF); the compiler may keep it
  in a register or count down when the body does not use it (PLAN §7A.2).
* A `For` loop whose bounds are constants and whose body is small may be unrolled; `For` over a
  `Byte` with an upper bound of 255 is safe (the compiler does not wrap-loop forever). (NEW)
* `Case` conditions are compile-time-checked for overlap and unreachable `Else`. (NEW)
* **Alternative loop forms** `Do … Loop`, `Do While/Until … Loop` are accepted as aliases (§14).

## 7. Subroutines and functions

```
[Public|Private] [Inline|NoInline] Sub Name([params])
    { declaration } { statement }
End Sub

[Public|Private] [Inline|NoInline] Function Name([params]) As Type
    { declaration } { statement }       ' assign to the function name or to Result
End Function

param := [ByVal | ByRef | ByRefConst] Name [()] As Type [= constexpr]
```
* **Parameters** are by value unless `ByRef`; arrays and large aggregates must be `ByRef`
  (array parameters are written `pArr() As Type`); `ByRefConst` passes a program-memory
  (constant) array by address. A `ByRef` argument must be a variable, not an expression.
* **Default values** are allowed on trailing `ByVal` parameters only.
* **Return type** may be any scalar type or a structure; not an array. The implicit variable
  `Result` holds the return value; assigning to the function name is equivalent. (SF)
* **No recursion** (D13). Because the call graph is acyclic and fully known, the compiler gives
  every routine static frame storage and **overlays** the frames of routines that are never live
  at the same time (frame recycling, SF); RAM use is the maximum depth of the call chain, not
  the sum. Declaring working variables locally therefore saves RAM.
* **Inlining**: a routine called exactly once is inlined by default; `Inline` forces it,
  `NoInline` forbids it; the optimiser may also inline small routines by its cost model.
* **Overloading** (same name, different parameter types) and **compound subroutines** are
  planned but deferred to milestone M9. (SF)
* **Reentrant** routines (opt-in attribute `Reentrant`) use a software stack and may recurse; they
  are slower and larger and are off by default (PLAN §7.2).

## 8. Interrupts, events and context saving

```
Interrupt Name([priority])
    …
End Interrupt

Enable(Name)      Disable(Name)      ' commit the handler to a vector / set or clear the enable
```
* An interrupt handler is declared with no parameters. With a single handler, no priority is
  given and the compiler picks the vector. With two priorities, `ipLow = 1` and `ipHigh = 2`.
  (SF) The vector addresses and the interrupt enable/priority registers come from the device
  description and the M1 fact base (`docs/FACTS-18F27Q10.md` §4).
* The mapping to a vector is committed by `Enable`; enabling two handlers of the same priority is
  an error. (SF)
* **Context saving**. The hardware fast register stack (`STATUS`, `WREG`, `BSR`) is used for one
  handler; when two priorities exist the high-priority handler uses it and the low-priority
  handler saves/restores in software, because a high-priority interrupt overwrites the shadow
  values (verified M1, `[DS40002043F p.112]`). `#option ISR_SHADOW = false` forces software
  saving. (SF)
* **Safety check (NEW)**: calling a routine from a handler is an error unless the handler wraps
  the call in `Save(…) … Restore`, or the routine is proven to use only storage that the
  handler owns. The compiler reports the exact shared locations. A handler may use only its own
  frame; main-line frames are never overlaid onto a handler's frame. (This turns the reference
  language's "great care must be taken" into a compile-time check.)
* **Events** (SF): `Event Name() … End Event` declares a handler with its **own, non-overlaid
  frame**, callable only through a variable of an event type (`Type TEvent = Event()`), which is
  how a module lets user code plug into its interrupt safely.
* `Save(item {, item}) … Restore`: preserves the named variables, routines' frames, or the
  compiler's working registers (`0`) around the block. A routine item covers the frames of
  everything it calls. Inside a handler the compiler adds the frame and registers of every routine
  the block calls, so a call can never corrupt main-line storage. `Exit`, `Break` and `Continue`
  inside the block restore first; `Goto` and labels inside it are not supported.
* **What `Enable`/`Disable` do (M6).** They set or clear the global interrupt bits only
  (`GIE/GIEH`, `PEIE/GIEL`). Enabling a particular source is the program's job: set its `PIEx`
  bit, clear its flag in the handler (flags are not cleared by hardware), and, with two
  priorities, set its `IPRx` bit (they reset to *high*). Clearing the global bit inside a handler
  is undone by the return. Wide variables shared with a handler are not accessed atomically.
  Cycle-counted delays (`DelayUs`/`DelayMs`) run longer when interrupted.
* **Events (M6).** An event variable is one byte: 0 until assigned, then the number of the handler
  assigned to it (numbered in order of first use; only handlers named in an assignment are compiled).
  `Cb()` calls a shared dispatcher that compares the byte and calls that handler; an unassigned
  variable does nothing. Handler frames are ordinary frames, overlaid by the same call-graph rule as
  routines. For that reason (and because the dispatcher's parameter is shared) an interrupt handler
  must wrap an event call in `Save` like any other call (`E-ISR-CALL`). Event variables cannot be
  compared and there are no arrays of them.

**Float in handlers.** Float arithmetic, comparisons and conversions use shared library routines with static frames, so they are
`E-ISR-CALL` directly inside a handler; do the work in a routine and call it inside `Save(…) … Restore`. Copying a Float, `-f` and `Abs(f)`
are plain bit operations and are allowed. A 4-byte Float is not read atomically (D45).

## 9. Modules, includes and visibility

* `Include "name"` loads `name.bas` from the including file's folder, then the project `lib/`
  folder, then the configured library path. Loaded once per compilation. (SF)
* Only `Public` declarations of an included module are visible. Module statements are
  initialisation code and run before the main program, in include order. (SF)
* Qualified names (`Module.Name`) resolve ambiguity between modules. (SF)

## 10. Device and clock

* `Device = 18F27Q10` (the `PIC` prefix is accepted: `PIC18F27Q10`). Reading
  `_Device` yields the name as a string constant. (SF/NEW)
* `Clock = 64` is the **instruction-clock source frequency in MHz** the program is built for
  (may be fractional). `_Clock` reads it. The delay and serial libraries compute timing from it.
  `Declare Xtal = 64` is accepted as an alias. (SF/P8)
* **`Clock` does not set the hardware.** It declares the speed the program expects, as `Declare Xtal` does. The oscillator is set by `Config` (`RSTOSC`) and by register
  writes in the program: `Include "intosc"` does them for you, or write `OSCFRQ` / `OSCCON1` yourself
  (`docs/CLOCK.md`). A `Clock` that differs from the `RSTOSC` speed with nothing setting the oscillator
  gives `W-CLOCK`.
* The compiler checks the `Clock` against the device's limits and the configuration settings; for
  the 18F27Q10 the limits come from the datasheet (64 MHz maximum, `[DS40002043F p.1]`) and the
  oscillator-mode errata (e.g. XT above 2 MHz, `[DS80000832G]`) — see PLAN §5.5.
* **Configuration bits** are given in a `Config` block (names and values from the device
  description, validated against the pack):
  ```
  Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
  ```
  Any word not mentioned gets the pack's documented default and the compiler prints a note
  listing the defaulted words. (NEW)

## 11. Preprocessor

`#define`, `#undefine`, `#constant`, `#variable`, `#ifdef/#ifndef/#else/#endif`,
`#if/#elseif/#else/#endif`, `#error`, `#warning`, `#option`. `#if` / `#elseif` take numbers, the
predefined `_clock` and `_device` (read from the program's `Clock` and `Device` lines, so a module can
test them), `= <> < > <= >=`, `in (a, b, ...)`, `not`, `and`, `or` and parentheses; a device name such as
`18F27Q10` is written bare and compared with `=`, `<>` or `in`. Example:
`#if not(_clock in (1, 2, 4))` ... `#error "..."` ... `#endif`. (SF) **Predefined constants** come from the device description:
`_device`, `_clock`, `_core`, `_maxram`, `_maxrom`, `_ports`, `_adc`, `_adres`, `_eeprom`,
`_usart`, `_usb`, `_mssp`, `_ccp`, `_eccp`, `_comparator`, `_flash_write`, and more as devices
need them. (SF; names follow the reference language; values come from our device files.)

Options (`#option`): `Optimize = Size|Speed|Balanced`, `Strict = true|false`, `ISR_SHADOW`,
`Warn.<id> = true|false`. (NEW/SF)

## 12. Built-in routines

Compiler intrinsics (no module needed): `AddressOf`, `BitOf`, `Bound`, `Clear`, `Inc`, `Dec`,
`High`, `Low`, `Input`, `Output`, `Toggle`, `DelayMS`, `DelayUS`, `Terminate`, plus width
conversions (`Byte(x)`, `Word(x)`, `LongWord(x)`, `ShortInt(x)`, `Integer(x)`, `LongInt(x)`) and
`Abs`, `Min`, `Max` for integers. (SF + NEW)

`DelayMS/DelayUS` generate exact, cycle-counted code from `Clock`; the compiler computes the
count at compile time and reports the achieved error. Everything else — I/O, serial, ADC, timers,
I2C, SPI, LCD, EEPROM — is **library code** written in the language (PLAN §6).

## 13. Embedded assembler

```
Asm
    movlw 0x55            ; pic-as syntax
    xorwf PORTB, f, c
End Asm
```
The block is pic-as syntax, passed through unchanged. The compiler treats it as clobbering
`WREG`, `STATUS` and `BSR` unless the block declares otherwise (`Asm Preserves(W, STATUS, BSR)`),
and will not move its own code across it. Variables are referenced by their emitted symbol
names (documented in `ABI.md`). (SF/NEW)

## 14. Alternative spellings accepted (provisional)

Anything not listed here is not accepted.

| Alternative spelling | Meaning here |
|---|---|
| `Declare Xtal = n` | `Clock = n` |
| `Device = 18F27Q10` / `PIC18F27Q10` | same |
| `Symbol LED = PORTB.0` / `Symbol cMax = 100` (the `=` is optional) | alias or constant, chosen by what the value is |
| `SByte`, `SWord`, `Long`, `Dword` | `ShortInt`, `Integer`, `LongInt`, `LongWord` (type names and conversions; diagnostics print the native name) |
| `Dim x As Byte` | same (it is also the native form) |
| `Proc Name(p As T)` … `EndProc` | `Sub Name(p As T)` … `End Sub` |
| `Proc Name(p As T), RetType` … `EndProc` | `Function Name(p As T) As RetType` … `End Function` (return value in `Result`) |
| `ExitProc` | `Exit` |
| `Do … Loop` | `While True … Wend` |
| `Do While c … Loop`, `Do Until c … Loop` | `While c … Wend`, `While Not c … Wend` |
| `Do … Loop Until c`, `Do … Loop While c` | `Repeat … Until c`, `Repeat … Until Not c` |
| `$FF`, `%1010`, `0xFF`, `0b1010` | native |
| `:` between statements | native |
| `HRSOut`, `HRSIn`, `Toggle`, `Inc`, `Dec`, `DelayMS`, `DelayUS` | library or intrinsic with the same name where the behaviour matches |

Global `Declare` switches (for example for LCD pins or baud rate) are **not**
reproduced as a global mechanism; the corresponding library modules take their settings as
`Const` or `#constant` values (PLAN §4.2).

## 14A. Rules settled while building the front end (M3)

These fill gaps the draft left open; each is recorded in `DECISIONS.md` (D20–D27).

* **Labels.** `name:` is a label only when it is the first thing on a line and nothing follows the
  colon. Elsewhere `:` separates statements. Labels are local to the routine (or to the unit's
  top-level code) and must be unique there.
* **Single-line `If … Then statement` is rejected** with a message; use a block or `If c GoTo label`.
* **`Dim n As Byte = 10`** and **`Dim n = 10, m = 20 As Byte`** are both accepted. An initial value
  must be a constant. On a local variable it takes effect at each entry to the routine.
* **Parameters.** Arrays, `String` and structure parameters are passed `ByRef` (or `ByRefConst`) and
  default to `ByRef` when no mode is written; writing `ByVal` for them is an error. `ByRefConst`
  accepts a constant array or a string literal. A default value is allowed only on a trailing `ByVal`
  parameter and must be a constant.
* **`ByRef` strings** must match the callee's `String(n)` size exactly (a longer write would overrun a smaller buffer); `ByRefConst` accepts any size.
* **`#define` names are scoped to the file** that defines them (only `-D` names are shared), so results do not depend on include order. Directives inside `(* *)` or `{ }` comments are ignored.
* **Unary minus** on an unsigned variable widens to the next signed type (`Byte` to `Integer`,
  `Word` to `LongInt`); a `LongWord` cannot be negated without a conversion.
* **`Bound(a)`** is a constant for a declared array and a non-constant `Word` for an array parameter.
* **`Case Else`** is accepted as a spelling of `Else` in `Select`. Case values must be constants;
  overlapping cases are an error and an `Else` that can never run is a warning (`W-CASE-ELSE`).
* **Interrupt handlers** may call a user routine only inside `Save(…) … Restore` (error
  `E-ISR-CALL` otherwise). This is the conservative form of the rule in §8; the proof that a
  routine touches only the handler's own storage is not attempted (D22).
* **Calls.** Calling a function as a statement discards its result. `FunctionName = value` and
  `Result = value` are the same assignment.
* **Addresses.** `@x` / `AddressOf(x)` has type `Word` for RAM objects and `LongWord` for constant
  arrays and routines.
* **`BitOf`** is reserved but not specified in 0.1; using it is an error.
* **Preprocessor subset.** `#define`, `#undefine`, `#ifdef`, `#ifndef`, `#else`, `#endif`, `#error`,
  `#warning`, `#option`, `#if` and `#elseif` work. `#constant` and `#variable` are reported as
  unsupported (`E-PP-UNSUPPORTED`) until a later milestone. Only `_clock` and `_device` are predefined in `#if`;
  the other predefined names in §11 are not yet available to the preprocessor.
* **Clock limits.** `Clock` is checked to be a positive number. The upper limit for the device is
  not in the device description yet (it is a data sheet value, not in the pack), so it is not checked.
* **Overflow warnings (`W-OVF`)** need range analysis and arrive with the optimiser (M5). The
  evaluation width of every integer expression is already recorded (D16) for the code generator.

## 15. Open points

* Float format (D7).
* Exact interrupt context-save behaviour and vector registers for the 18F27Q10 (M1).
* Other type names, `ByValue`/`BycRef` and command
  statements without parentheses (`High LED`) are not accepted; only the spellings in §14 are.
* Overloading and compound subroutines (M9).
