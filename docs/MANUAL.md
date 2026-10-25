# basicc Compiler User Manual

Revision for **basicc 0.1.6**, target device **PIC18F27Q10**.

This manual describes exactly what the compiler accepts and generates today. It is laid out like the
Positron8 manual: an overview of the language, then one entry per command (Syntax, Overview,
Parameters, Example, Notes), then one entry per library routine. Anything not listed here is not
supported; Appendix A lists the Positron8 features that are missing or different, and Appendix B is
a checklist to work through when testing.

Status of the code: every feature below passes the Microchip MDB simulator suite and the host test
suite. **Nothing has been run on a real chip yet** (decision D6). Where a feature depends on pin
behaviour the simulator cannot model (serial bytes on the wire, PWM waveforms, external timer
edges, I2C/SPI traffic, LCD/OLED panels), that is stated, and those are the items to test on
hardware first.

Related documents: `docs/LANGUAGE.md` (formal language rules), `docs/GRAMMAR.md`,
`docs/LIBRARY.md`, `docs/DIAGNOSTICS.md`, `docs/CLOCK.md`, `docs/ABI.md`, `QUICKSTART.md`.

---

# Contents

1. Compiler overview
   - Supported device
   - Running the compiler
   - Program layout
   - Identifiers, labels, comments, line continuation
   - Numeric representations and literals
   - Variables and types
   - Aliases and register bits
   - Constants and `Symbol`
   - Arrays, strings, structures
   - Float
   - Operators and expression typing
   - Procedures (Sub, Function, Proc)
   - Interrupts, events and context saving
   - Modules and `Include`
   - Device, Clock, Config
   - Preprocessor
2. Language commands (alphabetical)
3. Library modules
4. Diagnostics
5. Appendix A: Positron8 comparison
6. Appendix B: Test checklist

---

# 1. Compiler overview

## Supported device

| Device | Core | Flash | RAM | Notes |
|---|---|---|---|---|
| PIC18F27Q10 | PIC18 (8-bit), legacy instruction set (`XINST = 0`) | 128 KB (65,536 words) | 3,359 usable GPR bytes (as reported by the build summary) | Device file `devices/18F27Q10.toml`, generated from pack `PIC18F-Q_DFP 1.31.492` |

`Device = 18F27Q10` (or `PIC18F27Q10`) is the only value accepted. A second device is added only
after it has its own description file and passes its own tests. Every register and register bit of
the device is available by its pack name (`PORTB`, `LATA`, `T0CON0`, `PIE0.5`, `SSP1CON1.SSPEN`
...), case-insensitively.

## Running the compiler

```
basicc [--check] [-S] [--report] [-O0] [-o OUT.hex] [-D NAME] [-L LIBDIR]
       [--devices DIR] [--pic-as PATH] [--version] <program.bas>
```

| Option | Meaning |
|---|---|
| *(none)* | Compile, assemble and link. Writes `prog.hex`, `prog.S` (assembly), `prog.map`. |
| `--check` | Front end only (syntax, types, declarations). No output files. Fast. |
| `-S` | Stop after writing the assembly (`prog.S`). |
| `--report` | Also print words per routine and every RAM object. |
| `-O0` | No optimisation (the test suite builds everything both ways and compares). `-O1`, `-O2`, `-Os` are accepted and mean "optimise" (the default). |
| `-o FILE` | Output hex path. |
| `-D NAME` | Define a preprocessor name (visible in every file). |
| `-L DIR` | Add a library folder (repeatable). |
| `--devices DIR` | Folder holding the device descriptions. |
| `--pic-as PATH` | The `pic-as` assembler (otherwise `$BASICC_PICAS`, then `/opt/microchip/xc8/*/pic-as/bin/pic-as`). |
| `--version` | Print the version. |

`lib/` and `devices/` are found by looking in the source file's folder and then each parent folder
(only the nearest of each is used), so keep programs inside the repository (for example
`my_src/`) or pass `-L` and `--devices`.

After a successful build the compiler prints the program size and a bar of flash and RAM used
against the device (colour only on a terminal, and not when `NO_COLOR` is set):

```
Program: 28 words (56 bytes)
basicc: blink.bas -> blink.hex (28 words, 56 bytes)
```

Errors print as `file:line:col: error[CODE]: message`, with the source line and a caret. Several
errors are reported per run. Exit status is non-zero if any error was reported.

## Program layout

A source file is a **program** or a **module**.

```basic
Program Name                        ' name is optional
    Device = 18F27Q10               ' required, before any Include or declaration
    Clock  = 16                     ' MHz; required for anything using delays or timing
    Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
    Include "module"                ' zero or more
    ' constants, types, variables, aliases
    ' subroutines, functions, interrupts, events
    ' statements - the main program
```

* There is no `Main`. The top-level statements run in order. Statements of included modules (their
  initialisation) run first, in include order.
* A program that runs off its end loops forever (a self-branch); it never runs into empty flash.
* **Order is enforced**: Device/Clock/Config, then `Include`, then constants/types/variables/aliases,
  then routines, then statements. After the first executable statement, `Include`, `Dim` and
  routine declarations are an error (`E-ORDER`).
* Identifiers must be declared before use. There is no forward reference.
* The program and all modules are compiled together. A module included by several files is loaded once.

A `Proc ... EndProc` flat/procedural layout in the Positron style is accepted (see *Procedures*).

## Identifiers, labels, comments, line continuation

* **Identifiers**: letter or `_`, then letters, digits and `_`. Not case sensitive (`Label`, `LABEL`
  and `label` are the same). A variable cannot have the name of a device register (`trisa` clashes
  with `TRISA`; `W-REGNAME`).
* **Reserved words** cannot be names (`E-RESERVED`). Notable ones that catch people out: `Inc`,
  `Dec`, `High`, `Low`, `Input`, `Output`, `Toggle`, `Clock`, `Device`, `Type`, `Result`, `Step`,
  `Next`, `Event`, `Loop`, `Do`, `Symbol`, `Proc`, `Declare`. The full list is in `src/lexer.rs`
  (`KEYWORDS`).
* **Labels**: `name:` as the first thing on a line with nothing after the colon. Labels are local to the
  routine (or to the top-level code) and must be unique there. Jump with `GoTo name`.
* **Comments**: `'` or `//` to end of line; `(* ... *)` or `{ ... }` for blocks (these nest inside
  each other, but not themselves with mixed closers).
* **Several statements on one line**: separate with `:`.
* **Line continuation**: end a line with a space and `_`.

## Numeric representations and literals

| Form | Example | Notes |
|---|---|---|
| Decimal | `100` | |
| Hexadecimal | `$FF` | `0x`-style is **not** accepted |
| Binary | `%1010` | `0b` is **not** accepted |
| Floating point | `3.14`, `1.0e3`, `1.5E-2` | |
| Character | `"A"` | a Char, or a one-character String, by context |
| Character code | `#65`, `#13 + #10` | Char with the given code; can be concatenated |
| String | `"Hello"` | up to 255 characters |
| Booleans | `True`, `False` | |
| `Null` | `Null` | string terminator / empty string |

## Variables and types

```basic
Dim Name As Type
Dim Name1, Name2 As Type
Dim Name As Type = constant          ' initial value
Dim Name = constant, Name2 = 5 As Type
```

| Type | Bits | Range / meaning | Positron-style spelling |
|---|---|---|---|
| `Boolean` | 1 | `True` / `False`. Cannot hold a number | |
| `Bit` | 1 | 0 / 1 | `Bit` |
| `Byte` | 8 | 0 to 255 | `Byte` |
| `ShortInt` | 8 | -128 to 127 | `SByte` |
| `Word` | 16 | 0 to 65,535 | `Word` |
| `Integer` | 16 | -32,768 to 32,767 | `SWord` |
| `LongWord` | 32 | 0 to 4,294,967,295 | `Dword` |
| `LongInt` | 32 | -2,147,483,648 to 2,147,483,647 | `Long` |
| `Float` | 32 | IEEE-754 binary32, about +/-3.4e38, 6 to 7 digits | `Float` |
| `Char` | 8 | one character | |
| `String(n)` | n+1 bytes | up to n characters plus a terminating `Null` | |
| `Structure` | | see *Structures and unions* | |

**Note on `Long`:** here `Long` is the signed 32-bit type (`LongInt`), not Positron8's 24-bit
unsigned `Long`. There is no 24-bit type; 24 bits is only used inside the compiler. `SDword` and
`Double` are not accepted. The Positron `Pin` type is not accepted.

* All variables are zeroed at start-up unless they have an initialiser. A routine's local variables
  are zeroed **at every entry**, and an initialiser is applied at every entry too.
* Declarations are `Private` by default; `Public` exports from a module.
* Name lookup order: local, then the current file, then the `Public` names of included modules.
  Qualify with `Module.Name` to resolve a clash.
* Global variables must fit the device RAM (`E-RAM`). The hardware return stack is checked at
  compile time (31 levels; `E-STACK`).

### Type conversion

`Byte(x)`, `Word(x)`, `Integer(x)`, `LongWord(x)`, `LongInt(x)`, `ShortInt(x)`, `Float(x)`,
`Boolean(x)`, `Bit(x)`, `Char(x)`, and the Positron spellings `SByte(x)`, `SWord(x)`, `Dword(x)`,
`Long(x)`. A constant that does not fit the target type is an error (`E-CONST-RANGE`). Conversion
to `String` is not supported. Float to integer truncates toward zero.

## Aliases and register bits

An alias creates a second name for existing storage; it uses no RAM.

```basic
Dim LED As PORTB.0               ' a register bit
Dim Flags As Byte
Dim Ready As Flags.0             ' a bit of a variable
Dim LowNibble As Flags.Bits(4)   ' see the modifier table
Symbol Button = PORTA.3          ' Positron spelling, same effect
```

| Modifier | Gives |
|---|---|
| `.n` or `.Bits(n)` | bit n |
| `.Booleans(n)` | bit n as a Boolean |
| `.Byte0` ... `.Byte3`, `.Bytes(n)` | byte n of a multi-byte value |
| `.Word0`, `.Word1`, `.Words(n)` | word n |
| `.AsLongWord` and similar | a larger view of smaller storage (promotion), for example `Dim L As Arr(0).AsLongWord` |

Aliases may chain. A bit alias is a `Bit`; it cannot be used directly as a condition (`E-COND`):
write `If LED = 1 Then`. Any device register or register bit can be read and written by name
without declaring it: `PORTB`, `TRISB`, `ANSELB = 0`, `PIE0.5 = 1`, `SSP1CON1.SSPEN = 1`.

## Constants and Symbol

```basic
Const Name = expression               ' type inferred
Const Name As Type = expression
Symbol cLimit = 100                   ' Positron form; the = is optional
Symbol LED = PORTB.0                  ' becomes an alias, chosen by what the value is
```

A constant without a type takes its type from the expression: `5 / 1024` is integer arithmetic and
is 0; write `5.0 / 1024` for floating point. Constants can be used in array sizes, `Case` values
and anywhere a constant expression is required. `_Clock` and `_Device` are predefined constants
(the `Clock` value and the device name).

## Arrays, strings, structures

### Arrays

```basic
Dim a(5) As Byte                       ' FIVE elements: a(0) .. a(4)
Dim t(3) As Byte = (1, 2, 3)           ' initialiser: exactly 3 values
Const Tbl(4) As Byte = (10, 20, 30, 40)  ' lives in program memory
```

* The number in brackets is the **element count**. `Bound(a)` is the highest index (4 here), so
  `For i = 0 To Bound(a)` visits every element.
* Element types: the integer types, `Char`, `Boolean`, `Bit`, `Float`. One dimension only.
* A constant index outside the array is a compile error (`E-BOUNDS`). A run-time index is not
  checked.
* `Const` arrays are read-only (reading by index works; assigning a `Const` array to a same-sized RAM
  array copies it).
* `Bit` and `Boolean` arrays that are only indexed are packed eight to a byte. Writing one through a
  run-time index is a read-modify-write: do not write other elements of the same array from an
  interrupt (the compiler turns interrupts off around the write).
* Arrays are passed to routines as `ByRef` (written `p() As Byte`) or `ByRefConst`.
* `Clear(a)` zeroes an array; `a = b` copies same-sized arrays.
* Not supported: multi-dimensional arrays, arrays of strings, `Const` arrays of Float, functions
  that return an array.

### Strings

```basic
Dim s As String(20)                    ' 21 bytes
Dim t As String(10) = "hi"
s = "abc"                              ' from a literal, another string, a Char
s = s + "def"                          ' in-place append
s = "x" + t + "y"                      ' + chain (the target may only be the first operand)
If s = "abc" Then ...                  ' = and <> only
c = s(1)                               ' element, zero-based, a Char
Clear(s)
```

Assignments are cut off at the declared size and always terminated with `Null`. There is no run-time
bounds check on `s(i)`. String literals live in program memory and are read with `TBLRD`.
A `String` parameter is `ByRef` (size must match the callee's `String(n)` exactly) or `ByRefConst`
(any size, also accepts a literal).

Not supported: `Len`, `Left`, `Mid`, `Right`, `Str`, `Val`, `Print`, comparison of a concatenation,
string-returning functions, arrays of strings. Output of text is done by the library routines
(`SerialWrite`, `LcdWrite`, `OledWrite`).

### Structures and unions

```basic
Structure TStatus
    Val       As Byte
    Enabled   As Val.0           ' alias field: shares storage with Val (a union)
    Connected As Val.1
End Structure

Structure TPoint
    X As Word
    Y As Word
End Structure

Dim p As TPoint
Dim pts(4) As TPoint             ' arrays of structures; structures may nest
p.X = 100
pts(2).Y = 7
Clear(p)
```

Fields are reached with `.`. `Clear(x)` zeroes a structure. Structure initialisers are not supported.

## Float

`Float` is IEEE-754 binary32 (sign, 8-bit exponent, 23-bit fraction). It is implemented in
`lib/floatlib.bas`, which the compiler adds automatically to any program that mentions `Float`; only
the routines used are linked.

* Supported: variables, constants, arrays, parameters, results; `+ - * /`; unary minus; `Abs`; the six
  comparisons; mixed integer and Float expressions (the integer is converted); `Float(x)` and the
  integer conversions `Byte(f)`, `Integer(f)`, ... (truncating).
* Rounding is to nearest even. Infinities and NaN propagate. Denormals are flushed to zero.
* Not supported: `Sqr`, `Sin`, `Cos`, `Tan`, `Log`, `Exp`, `Pow`, `fRound` and the other Positron math
  functions; `Print`/`Str` of a Float; a Float as a `For` variable, in `Select`, or with `Inc`/`Dec`;
  `=` and `<>` between floats are available but avoid them as for any float.
* Cost: about 700 words for `+`, 800 for `*`, 470 for `/`, plus about 250 shared (roughly 2,500 words
  for a program using all three).
* In an interrupt handler, float arithmetic is an error (`E-ISR-CALL`): do it in a routine and call
  that inside `Save(...) ... Restore`. Copying a Float, negation and `Abs` are allowed. A 4-byte Float
  is not read atomically.

## Operators and expression typing

Highest precedence first:

| Level | Operators |
|---:|---|
| 1 | `@` (address), unary `-`, unary `+`, `Not` |
| 2 | `*`, `/`, `Mod` |
| 3 | `+`, `-` |
| 4 | `<<`, `>>` |
| 5 | `=`, `<>`, `<`, `>`, `<=`, `>=` |
| 6 | `And` |
| 7 | `Or`, `Xor` |

* `And`, `Or`, `Xor`, `Not` are **logical** on Booleans and **bitwise** on integers. Mixing a
  Boolean and a number is an error (`E-MIX`). Conditions short-circuit left to right.
* There is no `\`, `^`, `&`, `|`, `~`, `<<=` or `Dig`/`?`, `@` bit reverse, `Dcd`/`Ncd`.
* **Evaluation width.** An integer expression is evaluated at the width of its widest operand or its
  target, whichever is larger, and no wider. `B3 = B1 + B2` is an 8-bit add that wraps; `W = B1 * B2`
  is a full 16-bit product (hardware 8 x 8 multiply). A comparison is evaluated at the wider of its
  two sides.
* **Mixing signedness.** Signed and unsigned operands of the same width cannot be combined without a
  conversion (`E-SIGN`); a narrower unsigned operand is widened safely; a narrower signed operand
  against a wider unsigned one is rejected. Unary minus on an unsigned variable widens to the next
  signed type.
* **Narrowing.** A constant that does not fit is an error; a non-constant narrowing is the warning
  `W-NARROW` (error under `#option Strict = true`).
* **Division and `Mod`** truncate toward zero; `Mod` takes the dividend's sign. Divide by zero at run
  time gives an all-ones quotient and the dividend as remainder; in a constant expression it is an
  error. A division by a power-of-two constant becomes a shift. A constant multiplier becomes shifts
  or `MULLW` steps.
* **Shifts.** The count must be a constant or a `Byte`. Shifting by the width or more gives 0 (or the
  sign for a signed right shift). `>>` is arithmetic for signed types.
* Functions may be used in expressions; subroutines may not. Parentheses are needed when calling
  with arguments.

## Procedures (Sub, Function, Proc)

```basic
[Public|Private] [Inline|NoInline] Sub Name([params])
    ' declarations and statements
End Sub

[Public|Private] [Inline|NoInline] Function Name([params]) As Type
    ' assign to Result (or to the function name)
End Function

param := [ByVal | ByRef | ByRefConst] Name [()] As Type [= constant]
```

Positron-style equivalents are accepted:

```basic
Proc Name(p As Byte)                 ' = Sub
    ...
    ExitProc                         ' = Exit
EndProc

Proc Double(pValue As Byte), Word    ' = Function ... As Word, value in Result
    Result = pValue * 2
EndProc
```

* Parameters are **by value** by default for scalars; arrays, `String` and structures are `ByRef`
  (or `ByRefConst`). A `ByRef` argument must be a variable, not an expression. A `ByRef` parameter
  can be a Byte/Word/etc. scalar, an array, a String or a structure.
* A default value is allowed only on a trailing `ByVal` parameter, and must be a constant.
* A function returns a scalar or a structure (not an array, not a String). Calling a function as a
  statement discards its result.
* **No recursion** (`E-RECURSION`). Because the call graph is acyclic, the compiler gives every
  routine static storage and **overlays** the storage of routines never live at the same time, so
  RAM use is the deepest call chain, not the sum. Declaring working variables locally saves RAM.
  `Reentrant` is parsed but rejected by the back end.
* A routine called once is inlined by default; `Inline` forces and `NoInline` forbids it.
* Overloading and compound subroutines are not supported.
* Routines are called as `Name(args)`, or `Module.Name(args)`.

## Interrupts, events and context saving

```basic
Interrupt Name([priority])
    ' handler body
End Interrupt

Enable(Name)        ' commit the handler and set the global enable
Disable(Name)       ' clear the global enable bit(s)
```

* A handler has no parameters. With one handler no priority is written. With two priorities, the
  low one is `ipLow = 1` and the high one `ipHigh = 2`. The 18F27Q10 has fixed vectors.
* `Enable` and `Disable` set or clear only the **global** bits (`GIE/GIEH`, `PEIE/GIEL`). Enabling a
  particular source is the program's job: set its `PIEx` bit, **clear its flag inside the handler**
  (hardware never clears it), and with two priorities set its `IPRx` bit (they reset to high).
* **Context saving** is automatic. The fast register stack is used for one handler; with two
  priorities the high handler uses it and the low handler saves in software.
* **Calls from a handler** must be wrapped: `Save(...) ... Restore`; otherwise `E-ISR-CALL`.

```basic
Save(0, SomeRoutine)           ' 0 = the compiler's working registers; a routine covers its callees
    SomeRoutine()
Restore
```

`Exit`, `Break`, `Continue` inside a `Save` block restore first; `GoTo` and labels inside it are not
supported.
* Wide variables shared with a handler are not read or written atomically. `DelayMS`/`DelayUS` run
  longer if interrupted.
* **Events**: `Event Name() ... End Event` declares a handler callable through a variable of an event
  type (`Type TEvent = Event()`), one byte per variable; an unassigned variable does nothing when
  called. An event call inside an interrupt must also be wrapped in `Save`.
* Library modules never declare an `Interrupt`; they set up peripherals and read flags, and your program
  writes its own handler.

## Modules and Include

```basic
Module Name
    Public Sub Hello()
    End Sub
    ' statements here are start-up code, run before the main program
```

`Include "name"` loads `name.bas` from the including file's folder, then the project `lib/` folder,
then any `-L` folder, once per compile. Only `Public` names are visible. Call as `Name.Routine()`
or by the bare routine name when unambiguous. The spelling of a module's own name is what you write
after the `.`: `Include "serial"` then `Serial.SerialInit(115200)`.

## Device, Clock, Config

* **`Device = 18F27Q10`**: required (`E-NODEVICE`).
* **`Clock = n`** (or `Declare Xtal = n`): the instruction-clock source frequency in MHz that the
  program is built for, fractions allowed (`Clock = 0.5`). Delays, baud rates and timer periods are
  computed from it.
* **`Clock` does not set the hardware.** The oscillator is set by `Config RSTOSC` and by register writes. Either
  start the part at the speed you declare (`RSTOSC = HFINTOSC_64MHZ` with `Clock = 64`), or add
  `CSWEN = ON` and `Include "intosc"`, which writes `OSCFRQ`/`OSCCON1` for you. A mismatch with nothing
  setting the oscillator gives `W-CLOCK`. Details: `docs/CLOCK.md`.
* **`Config NAME = VALUE, ...`**: configuration words by pack names, validated against the device
  (`E-CONFIG`). Settings not mentioned take the pack default and the compiler prints a note listing
  them. Typical line:

```basic
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
```

## Preprocessor

| Directive | Notes |
|---|---|
| `#define NAME [value]`, `#undefine NAME` | scoped to the file that defines them (only `-D` names are shared) |
| `#ifdef`, `#ifndef`, `#else`, `#endif` | |
| `#if`, `#elseif`, `#else`, `#endif` | expressions with numbers, `_clock`, `_device`, `= <> < > <= >=`, `in (a, b, ...)`, `not`, `and`, `or`, parentheses. A device name is written bare: `#if _device = 18F27Q10` |
| `#error "text"`, `#warning "text"` | |
| `#option Optimize = Size\|Speed\|Balanced`, `Strict = true\|false`, `ISR_SHADOW`, `Warn.<id> = true\|false` | |

Not supported: `#constant`, `#variable` (`E-PP-UNSUPPORTED`). Of the predefined names, only `_clock`
and `_device` exist in `#if`. Directives inside `(* *)` or `{ }` comments are ignored.

---

# 2. Language commands

Entries are alphabetical. In the syntax lines `[x]` is optional, `{x}` is repeated.

## Abs

**Syntax**
```basic
Result = Abs(value)
```
**Overview** Absolute value of a constant, variable or expression. Works on every signed integer type
and on `Float` (clears the sign bit).

**Parameters** `value` is any numeric expression. The result has the type of `value`.

**Example**
```basic
Dim a As Integer
Dim b As Integer
a = -1234
b = Abs(a)              ' 1234
```
**Notes** Like Positron8, wrap functions inside larger expressions in parentheses for clarity:
`x = (Abs(a)) + 1`. `Abs(-32768)` of an `Integer` overflows as in any two's-complement system.

## AddressOf  (and `@`)

**Syntax**
```basic
p = AddressOf(item)
p = @item
```
**Overview** Address of a variable, array or routine. The type is `Word` for RAM objects and
`LongWord` for `Const` arrays and routines.

**Notes** The argument must be a variable, array or routine (`E-ADDR`).

## Asm ... End Asm

**Syntax**
```basic
Asm [Preserves(W, STATUS, BSR)]
    movlw 0x55            ; pic-as syntax
    xorwf PORTB, f, c
End Asm
```
**Overview** Raw `pic-as` source, passed through unchanged. The compiler assumes the block changes
`WREG`, `STATUS` and `BSR` unless the optional `Preserves(...)` says otherwise, and will not move its
own code across it. A variable that is used only inside `Asm` still gets storage. Variables are
referred to by their emitted symbol names (see `docs/ABI.md`; the names are in the `.S` and `.map`
files).

**Notes** Comments inside the block are assembler comments (`;`). The block ends at a line holding
`End Asm`. Stack use of `call` in raw `Asm` is counted by the `E-STACK` check.

## Bound

**Syntax**
```basic
n = Bound(array)
```
**Overview** Highest valid index of an array. For a declared array it is a constant (`Dim a(5)` gives
4). For an array **parameter** it is a run-time `Word`.

## Break

**Syntax** `Break`

**Overview** Leaves the innermost `For`, `While`, `Repeat` or `Do` loop. Outside a loop it is an error
(`E-LOOP`).

## Clear

**Syntax**
```basic
Clear(variable)
```
**Overview** Sets a variable, array, string or structure to zero.

## Continue

**Syntax** `Continue`

**Overview** Jumps to the next iteration of the innermost loop (`E-LOOP` outside a loop).

## Dec

**Syntax**
```basic
Dec(variable)
```
**Overview** Subtract one from a variable (integer types, array elements, structure fields).
Not available for `Float`.

## DelayMS / DelayUS

**Syntax**
```basic
DelayMS(milliseconds)
DelayUS(microseconds)
```
**Overview** Cycle-counted delays computed from `Clock`. The compiler works out the loop counts at
compile time. With a constant argument the achieved error is reported.

**Parameters** A constant, or a variable of any integer type. A negative constant is an error. A
**variable** delay needs an integral number of instruction cycles per unit at the given `Clock`;
otherwise the build fails rather than rounding silently.

**Example**
```basic
Dim led As PORTB.0
ANSELB = 0
Output(led)
While True
    Toggle(led)
    DelayMS(500)
Wend
```
**Notes** Interrupts lengthen a delay. The simulator suite checks exact cycle counts (for example
1,600, 16,000 and 8,000,000 cycles for the test delays). Keywords are case-insensitive, so `DelayMs`
and `DelayMS` are the same word. `DelaySeconds` is in the `delay` module.

## Disable / Enable

**Syntax**
```basic
Enable(HandlerName)
Disable(HandlerName)
```
**Overview** `Enable` assigns the handler to its vector and sets the global interrupt bits; `Disable`
clears them. See *Interrupts*. Enabling two handlers of the same priority is an error (`E-ENABLE`).

## Do ... Loop  (Positron form)

**Syntax**
```basic
Do
    ...
Loop

Do While condition ... Loop
Do Until condition ... Loop
Do ... Loop While condition
Do ... Loop Until condition
```
**Overview** Accepted as spellings of `While`/`Repeat`:
`Do...Loop` = `While True`; `Do While c` = `While c`; `Do Until c` = `While Not c`;
`Loop While c` = `Repeat ... Until Not c`; `Loop Until c` = `Repeat ... Until c`.

## Exit / ExitProc

**Syntax** `Exit`   (Positron: `ExitProc`)

**Overview** Leaves the current Sub or Function. For a Function the current `Result` is returned.

## For ... Next ... Step

**Syntax**
```basic
For variable = start To end [Step constant]
    ...
Next
```
**Overview** `variable` must be an integer variable (not `Float`, not a Bit). `end` is evaluated once.
`Step` must be a constant (negative counts down). After a loop that ran, the variable holds the last
value it took. The variable must not be changed inside the loop (`E-LOOPVAR`). A `Byte` loop to 255 is
safe (it does not wrap forever).

**Example**
```basic
Dim i As Byte
Dim a(8) As Byte
For i = 0 To Bound(a)
    a(i) = i * 2
Next
For i = 10 To 0 Step -2
    DelayMS(1)
Next
```

## GoTo

**Syntax**
```basic
GoTo label
If condition GoTo label
```
**Overview** Jump to a label in the same routine. `GoSub`/`Return`, `Call` and computed `On GoTo` are not
supported.

## High / Low / Toggle / Input / Output

**Syntax**
```basic
High(bit)         ' drive 1
Low(bit)          ' drive 0
Toggle(bit)       ' invert
Input(bit)        ' make an input (TRIS = 1)
Output(bit)       ' make an output (TRIS = 0)
```
**Overview** `bit` is a `Bit`/`Boolean` variable or alias, or a register bit such as `PORTB.4` or an
alias `LED`. `High`/`Low`/`Toggle` act on the **latch** (`LATx`), and `Input`/`Output` on `TRISx`,
so a pin set high is not disturbed by read-modify-write of other pins (verified in the generated
assembly: `High(led)` on `PORTB.0` gives `bsf LATB,0`). To set a whole port direction or value, write the
register: `TRISB = 0`, `LATB = $FF`.

**Example**
```basic
Dim LED As PORTB.0
ANSELB = 0               ' pins reset to analog; make port B digital
Output(LED)
High(LED)
Toggle(LED)
If LED = 1 Then          ' a bit alias is compared, not used bare
    Low(LED)
EndIf
```
**Notes** Parentheses are required: `High LED` and `High 1` (pin numbers) are **not** accepted. Pin
numbers for the library routines are 0..23 (`RA0` = 0, `RB0` = 8, `RC0` = 16).

## If ... Then ... ElseIf ... Else ... EndIf

**Syntax**
```basic
If condition Then
    ...
ElseIf condition Then
    ...
Else
    ...
EndIf

If condition GoTo label
```
**Overview** The condition must be Boolean (`E-COND`); `And`/`Or` short-circuit. Bit aliases are
compared: `If led = 1 Then`.

**Notes** The single-line form `If x Then y = 2` is rejected with a message; use a block or
`If c GoTo label`.

## Inc

**Syntax**
```basic
Inc(variable)
```
**Overview** Add one to an integer variable, array element or structure field. Not for `Float`. On an
array element with a run-time index the index is evaluated twice.

## Min / Max

**Syntax**
```basic
r = Min(a, b)
r = Max(a, b)
```
**Overview** Smaller / larger of two integers. Integers only (`E-TYPE` for Float). The result has the
common type of the two arguments.

## Repeat ... Until

**Syntax**
```basic
Repeat
    ...
Until condition
```
**Overview** Body runs at least once; ends when the condition is true.

## Save ... Restore

**Syntax**
```basic
Save(item {, item})
    ...
Restore
```
**Overview** Preserves the named variables, routines' storage (including what those routines call) and,
with `0`, the compiler's working registers around the block. Required around any call made from an
interrupt handler. See *Interrupts*.

## Select ... Case ... EndSelect

**Syntax**
```basic
Select expression
    Case 1
        ...
    Case 2, 3
        ...
    Case 10 To 20
        ...
    Case < 0
        ...
    Case Else          ' or: Else
        ...
EndSelect
```
**Overview** `Select` takes an integer expression. Case values are constants; they can be a list, a
range (`lo To hi`) or a relation (`< v`, `> v`, ...). Overlapping cases are an error
(`E-CASE-OVERLAP`); an `Else` that can never run is the warning `W-CASE-ELSE`.

**Notes** The Positron form `Select Case x` is **not** accepted: write `Select x`. Strings and
Floats cannot be selected on.

## Terminate

**Syntax** `Terminate()`

**Overview** Stops the program: it falls into the halt loop (a self-branch).

## While ... Wend

**Syntax**
```basic
While condition
    ...
Wend
```
**Overview** Test first. `While True ... Wend` is the usual main loop.

---

# 3. Library modules

Modules are in `lib/` and loaded with `Include "name"`. Call as `Module.Routine(...)` or by the
bare routine name when unambiguous. Only the routines a program calls are linked. All modules
cite the PIC18F27Q10 data sheet (DS40002043F) and errata (DS80000832G) for their register values.

**Common rules**

* **Pins** are given by number: `RA0..RA7` = 0..7, `RB0..RB7` = 8..15, `RC0..RC7` = 16..23.
* **Return codes**: functions that can fail return a `Byte`: 1 = success, 0 = refused (bad pin, bad
  argument, conflict), unless the entry says otherwise. Bus modules also keep a status code.
* The reset state of port pins is **analog** (`ANSELx = 1`). Call `GpioAllDigital()` (or write
  `ANSELx`) before using pins digitally.
* **No module is reentrant.** Do not call a module routine from an interrupt handler and from the main
  program, or from two handlers, without `Save`.
* Library timing is computed from the compile-time `Clock`. If you change the oscillator at run time
  (`SetClock`) the library timing is then wrong (by design).
* **Not yet checked on hardware** for any module.

## gpio

| Routine | Effect |
|---|---|
| `GpioAllDigital()` | `ANSELA/B/C = 0` |
| `GpioPullUps(maskA, maskB, maskC)` | `WPUx`: a 1 bit enables that pin's weak pull-up |
| `GpioOpenDrain(maskA, maskB, maskC)` | `ODCONx`: a 1 bit makes the pin drive low only |

```basic
Include "gpio"
Gpio.GpioAllDigital()
Gpio.GpioPullUps(0, 0, %00000001)        ' pull-up on RC0
```

## delay

| Routine | Effect |
|---|---|
| `DelaySeconds(s)` | `s` x `DelayMS(1000)`; `s` is a `Byte` |
| `DelayNop()` | exactly one instruction cycle |

`DelayMS` and `DelayUS` are built into the language (section 2).

## intosc  (internal oscillator set-up)

`Include "intosc"` makes the hardware run at `Clock`. Its start-up code (run before the main program)
writes `OSCFRQ` and `OSCCON1` and waits, each wait bounded, for `OSCCON3.ORDY` and `OSCSTAT.HFOR`.
Include it **first**. `Config` needs `CSWEN = ON` unless `Clock` already equals the `RSTOSC` speed.

Accepted `Clock` values (anything else is a compile error): 64, 48, 32, 16, 12, 8, 4, 2, 1 MHz, and
0.5, 0.25, 0.125, 0.0625, 0.03125 MHz (1 MHz divided by 2 to 32).

| Routine | Effect |
|---|---|
| `SetClock(mhz)` | HFINTOSC at `mhz` (1, 2, 4, 8, 12, 16, 32, 48 or 64), divider 1:1. Returns True when the switch completed and read back; False (nothing written) for another value |
| `SetClockDiv(mhz, shift)` | the same divided by 2^`shift` (`shift` 0..9) |

```basic
Program Blink
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"
```

## system  (reset cause, clock check)

| Routine | Effect |
|---|---|
| `SysResetCause()` | 1 power-on, 2 brown-out, 3 MCLR pin, 4 watchdog time-out, 5 watchdog window violation, 6 `RESET` instruction, 7 stack overflow, 8 stack underflow, 0 none |
| `SysResetFlags()` | raw `PCON0` |
| `SysClearResetFlags()` | set `PCON0` flags inactive (call after reading the cause) |
| `SysClockHz()` | system clock in Hz from `OSCCON2`/`OSCFRQ` (HFINTOSC only; 0 for other sources) |
| `SysClockFrom(cosc, cdiv, hffrq)` | the same conversion from given field values |
| `SysClockOk()` | True when `SysClockHz()` equals `Clock` |

## timer  (Timer0, Timer1, Timer2)

All timers count FOSC/4 unless a Timer1 source says otherwise. `prescale` ranges are per timer.

| Routine | Effect |
|---|---|
| `Timer0Start(prescale, period)` | 8-bit; one overflow per `(period+1) * 2^prescale` cycles; `prescale` 0..15 |
| `Timer0Start16(prescale)` | 16-bit free-running |
| `Timer0Read()` | 16-bit count |
| `Timer0Expired()` | True once per overflow, clearing the flag |
| `Timer0Ack()` | clear the flag (call from your handler) |
| `Timer0EnableInterrupt()` / `Timer0DisableInterrupt()` | `PIE0.TMR0IE`; also `Enable(handler)` |
| `Timer0Stop()` | |
| `Timer1Start(prescale)` | 16-bit; `prescale` 0..3 = 1:1..1:8 |
| `Timer1StartSource(clk, prescale)` | any clock `T1Clk*`: `T1ClkPin` (T1CKI, default RC0), `T1ClkFosc4`, `T1ClkFosc`, `T1ClkHfIntOsc`, `T1ClkLfIntOsc`, `T1ClkMfIntOsc`, `T1ClkSosc`, `T1ClkTmr0` |
| `Timer1StartCounter(prescale)` | `Timer1StartSource(T1ClkPin, prescale)` |
| `Timer1StartGated(clk, prescale, source, activeHigh)` | counts only while the gate source is active. Sources `T1GatePin` (RB5), `T1GateTmr0`, `T1GateTmr2`, `T1GateCcp1`, `T1GateCcp2`, `T1GateCmp1`, `T1GateCmp2` |
| `Timer1StartPulse(clk, prescale, source, activeHigh, fullCycle)` | single-pulse gate: times the first gate pulse, then holds; poll `Timer1PulseDone()`, then `Timer1Read()` |
| `Timer1GateState()` | live gate (`T1GCON.GVAL`) |
| `Timer1Read()`, `Timer1Expired()`, `Timer1Ack()`, `Timer1Stop()` | as Timer0 (`PIR4.TMR1IF`) |
| `Timer1EnableInterrupt()` / `Timer1DisableInterrupt()` | `PIE4.TMR1IE` |
| `Timer2Start(prescale, postscale, period)` | free-running 8-bit; flag every `(period+1) * 2^prescale * (postscale+1)` cycles; `prescale` 0..7 = 1:1..1:128, `postscale` 0..15 |
| `Timer2StartLimit(prescale, postscale, period, mode, source)` | hardware-limit mode `T2Mode*` (software, gate, reset, one-shot, mono-stable, level; 20 constants) and reset source `T2Rst*` (`T2RstPin` = T2IN, default RC3; `T2RstTmr4`, `Tmr6`, `Ccp1`, `Ccp2`, `Pwm3`, `Pwm4`, `Cmp1`, `Cmp2`) |
| `Timer2Running()` | `T2CON.ON`; use this (not the flag) to detect the end of a one-shot |
| `Timer2Read()`, `Timer2Expired()`, `Timer2Ack()`, `Timer2Stop()` | as Timer0 (`PIR4.TMR2IF`) |
| `Timer2EnableInterrupt()` / `Timer2DisableInterrupt()` | `PIE4.TMR2IE` |

External pins (T1CKI, T1G, T2IN) must be digital inputs; the module does not set them up. The first
pulse after a Timer1 start may be missed. **Hardware untested** for external clock, gate and pulse use.

```basic
Include "timer"
Timer.Timer1Start(3)                  ' 16 MHz / 4 / 8 = 500 kHz
While Timer.Timer1Expired() = False
Wend
```

## serial  (EUSART1, 8N1, TX = RC6, RX = RC7)

| Routine | Effect |
|---|---|
| `SerialInit(baud)` | PPS, pin directions, `BRG16 = BRGH = 1`, enables TX and RX. Baud divisor computed from `Clock` (one 32-bit divide at run time) |
| `SerialWriteByte(b)` | one byte, blocking |
| `SerialWrite(text)` | a string or literal, up to 80 characters |
| `SerialNewLine()` | CR + LF |
| `SerialWriteWord(v)` | `Word` as unsigned decimal |
| `SerialWriteHex(v)` | `Byte` as two hex digits |
| `SerialAvailable()` | True when a byte is waiting |
| `SerialRead()` | wait for and return a byte; clears an overrun |
| `SerialFlush()` | wait for the shift register to empty |

`Clock` must be FOSC in MHz. The internal oscillator drifts with temperature and voltage, so use a
crystal for anything beyond casual use. There is no formatted `Print`: build output from the routines
above (for a signed number or a Float, convert in your own code).

```basic
Include "serial"
Serial.SerialInit(115200)
Serial.SerialWrite("hello")
Serial.SerialNewLine()
Serial.SerialWriteWord(1234)
```

## serial2  (EUSART2, TX = RB6, RX = RB7)

Same routines with the prefix `Serial2`: `Serial2Init`, `Serial2WriteByte`, `Serial2Write`,
`Serial2NewLine`, `Serial2WriteWord`, `Serial2WriteHex`, `Serial2Available`, `Serial2Read`,
`Serial2Flush`. RB6/RB7 are the ICSP pins: disconnect the programmer while using them. Both serial
modules can be used together. **Set-up verified only** (the simulator does not set TX2IF); a real
transmit is unproven.

## adc  (ADCC, 10-bit, right-justified)

| Routine | Effect |
|---|---|
| `AdcInit()` | ADC on, VDD/VSS reference, FOSC clock giving TAD of at least 1 us, hardware acquisition of 5 us |
| `AdcPin(ch)` | make channel 0..23 an analog input (RA0..RC7) |
| `AdcRead(ch)` | one conversion, 0..1023. Internal channels: `AdcChVss` 60, `AdcChTemp` 61, `AdcChDac` 62, `AdcChFvr` 63 |
| `AdcReadAvg(ch, n)` | mean of `n` (1..64) conversions |
| `AdcMillivolts(raw, vrefMv)` | `raw * vref / 1023` |
| `AdcRefVdd()` | VDD reference |
| `AdcRefFvr(gain)` | FVR reference, gain 1, 2 or 4 (4 or more is taken as 4, 0 as 1); waits for `FVRRDY` |

Errata handling: (1.4.4) the first conversion after a channel change is run and dropped; code that
writes `ADPCH` itself bypasses this. (1.4.1) `AdcRefFvr` needs TAD of at least 8 us, which `ADCS` allows
only up to `Clock` = 16 MHz; above that use the VDD reference. Source impedance above 10 kohm needs a
larger `ADACQ`. The temperature indicator needs `FVRCON.TSEN`, which the module does not set.

```basic
Include "adc"
Dim v As Word
Adc.AdcInit()
Adc.AdcPin(0)                 ' RA0
v = Adc.AdcRead(0)
```

## eeprom  (data EEPROM, 1024 bytes)

| Routine | Effect |
|---|---|
| `EepromRead(addr)` | byte at 0..1023 (255 for a larger address) |
| `EepromWrite(addr, value)` | skips the write if the byte already holds `value`; otherwise unlock sequence and wait. Returns 1 when the byte reads back as `value`, 0 for a bad address or failed write |
| `EepromReadWord(addr)` / `EepromWriteWord(addr, value)` | 16-bit, low byte first at `addr` and `addr + 1` |
| `EepromSize` | constant 1024 |

Global interrupts are held off for the unlock sequence and the previous state is restored. Success
is judged by read-back (errata 1.6.1). Reading stored values is **not verifiable in the simulator**
(it does not model DFM reads); test on hardware.

## pwm  (CCP1, CCP2, PWM3, PWM4 on Timer2)

| Routine | Effect |
|---|---|
| `PwmInit(hz)` | choose Timer2 prescale and `T2PR` for `hz` (1..1,000,000). Returns 1, or 0 if unreachable or a channel is running. Starts nothing |
| `PwmFrequency()` / `PwmSteps()` | achieved frequency; duty steps per period `4 * (T2PR + 1)` |
| `PwmStart(ch, pin, duty)` | channel 1 = CCP1, 2 = CCP2, 3 = PWM3, 4 = PWM4, on pin 0..23. CCP1/CCP2 on ports B and C, PWM3/PWM4 on ports A and C. `duty` in steps. Returns 0 for a bad channel or pin, pin in use, or no `PwmInit` |
| `PwmDuty(ch, duty)` / `PwmPercent(ch, pct)` | new duty of a running channel (steps, or 0..100 %) |
| `PwmInvert(ch, inverted)` | polarity of PWM3/PWM4 (0 for channels 1 and 2) |
| `PwmStop(ch)` | channel off, pin back to a latch-driven input; Timer2 stops with the last channel |

All channels share one frequency and each has its own duty. The module owns Timer2 while a channel
runs: do not use the `timer` module's Timer2 or a Timer2 interrupt then. With `T2PR` = 255 the
maximum duty is 1023 of 1024 steps, so 100 % is not reachable.

```basic
Include "pwm"
Dim ok As Byte
ok = Pwm.PwmInit(1000)
ok = Pwm.PwmStart(3, 16, 0)       ' PWM3 on RC0
Pwm.PwmPercent(3, 25)
```

## i2c  (MSSP1 host)

| Routine | Effect |
|---|---|
| `I2cInit(hz, scl, sda)` | host at `hz` (1..1,000,000), pins 8..23 (ports B and C). Returns 1, or 0 for a bad pin, equal pins or no divider in range (at 64 MHz the slowest clock is 62 kHz) |
| `I2cStart()` / `I2cRestart()` / `I2cStop()` | one bus condition each; return a status code |
| `I2cSend(b)` | address byte (7-bit address << 1, plus R/W) or data. 0 = acknowledged, 3 = not acknowledged |
| `I2cReceive(ack)` | one byte then ACK (`True`) or NACK (`False`); returns 0 and sets the status on error |
| `I2cPing(addr)` | True when a device acknowledges the 7-bit address |
| `I2cWriteReg(addr, reg, value)` / `I2cReadReg(addr, reg)` | register write / read (restart after the register byte) |
| `I2cStatus()` | 0 ok, 1 timeout, 2 bus collision, 3 no acknowledge, 4 not initialised |
| `I2cOff(scl, sda)` | MSSP off, pins back to latches |

Every wait is bounded, so a missing pull-up gives status 1; call `I2cInit` again to recover. External
pull-ups are required. Single host. The module polls `SSP1IF`/`BCL1IF` itself: keep the MSSP1
interrupt disabled. Cannot be used together with `spi` (both own MSSP1).

```basic
Include "i2c"
Dim ok As Byte
Dim ack As Boolean
ok = I2c.I2cInit(100000, 19, 20)       ' RC3 = SCL, RC4 = SDA
ack = I2c.I2cPing($50)
```

## spi  (MSSP1 host)

| Routine | Effect |
|---|---|
| `SpiInit(hz, mode, sck, sdo, sdi)` | host, mode 0..3, pins 8..23 (ports B and C); `sdo` = 255 for receive-only. Returns 1, or 0 for a bad pin or mode, a pin used twice or a clock out of range |
| `SpiTransfer(b)` | send `b`, return the byte received at the same time |
| `SpiWrite(b)` / `SpiRead()` | send ignoring the reply / receive (sends 255) |
| `SpiStatus()` | 0 ok, 1 timeout, 4 not initialised |
| `SpiOff(sck, sdo)` | MSSP off |

The chip select is yours (use a port bit). Clock range: `FOSC/4` down to `FOSC/1024`.

## lcd  (HD44780 character LCD, 4-bit)

Pins are 0..23; R/W is tied to ground; the busy flag is not read (fixed waits).

| Routine | Effect |
|---|---|
| `LcdInit(rs, en, d4, d5, d6, d7, lines)` | initialise (about 55 ms); `lines` is 1 or 2. Returns 1 or 0 |
| `LcdCommand(c)` | any instruction byte |
| `LcdClear()` / `LcdHome()` | |
| `LcdDisplay(on, cursor, blink)` | display control (Booleans) |
| `LcdShift(whole, right)` | shift cursor or whole display |
| `LcdGoto(col, row)` | `col` 0..39, `row` 0..1 |
| `LcdSetAddress(a)` | raw DDRAM address (four-line displays) |
| `LcdWriteChar(ch)` / `LcdWrite(s)` / `LcdWriteWord(v)` / `LcdWriteHex(v)` | character, string (up to 80), unsigned decimal, two hex digits |
| `LcdCustomRow(slot, row, bits)` | one row of user character 0..7; follow with `LcdGoto` |

Read-modify-write of `LATA/B/C`: not for use from a handler and the main program together.

## oled  (SSD1309, 128 x 64, I2C or 4-wire SPI)

You set up the bus first (`I2cInit` at no more than 400 kHz, or `SpiInit` mode 0 at no more than
10 MHz). No frame buffer: you write 8-pixel-high pages, one byte per column, bit 0 on top.

| Routine | Effect |
|---|---|
| `OledInitI2c(addr, res)` | `addr` 60 or 61 (0x3C/0x3D); `res` = reset pin or 255. Returns 1 if all acknowledged |
| `OledInitSpi(dc, cs, res)` | D/C#, CS# (255 = tied low), RES# (255 = none). Returns 0 for a bad or repeated pin |
| `OledStatus()` / `OledClearStatus()` | first I2C error since init (always 0 for SPI) |
| `OledOn(on)`, `OledContrast(v)`, `OledInvert(b)`, `OledAllOn(b)`, `OledFlip(rotated)` | display controls |
| `OledGoto(col, page)` | column 0..127, page 0..7 |
| `OledTextGoto(x, line)` | character cell 0..20, line 0..7 (6 x 8 cells) |
| `OledData(b)` / `OledFill(pattern)` / `OledClear()` | one column / whole RAM / clear |
| `OledWriteChar(ch)` / `OledWrite(s)` / `OledWriteWord(v)` / `OledWriteHex(v)` | text in a 5 x 7 font (ASCII 32..126) |
| `FontByte(i)` | byte `i` (0..474) of the font table |

No pixel, line or bitmap drawing yet.

## floatlib  (automatic)

Not included by hand. Routines `FAdd FSub FMul FDiv`, `FEq FNe FLt FLe FGt FGe`, `FFromLong
FFromULong FToLong` operate on `LongWord` bit patterns. You do not call them; the compiler does.

---

# 4. Diagnostics

Every message has a code, `error[E-TYPE]` or `warning[W-NARROW]`. Full list with meanings:
`docs/DIAGNOSTICS.md`. The ones met most often:

| Code | Cause |
|---|---|
| `E-NODEVICE`, `E-DEVICE` | no `Device`, or no description for it |
| `E-SYNTAX` | the text does not match the grammar (for example a single-line `If`, `High 1`, `Select Case`) |
| `E-ORDER` | a `Dim`, `Include` or routine after the first statement |
| `E-UNDECLARED` | misspelled name, or a module not `Include`d |
| `E-CONFIG` | unknown `Config` name or value |
| `E-TYPE`, `E-SIGN`, `E-MIX`, `E-NARROW` / `W-NARROW` | type rules |
| `E-COND` | condition is not Boolean (a bare bit alias) |
| `E-CONST-RANGE`, `E-BOUNDS` | constant does not fit; constant index out of range |
| `E-RAM`, `E-STACK` | variables exceed RAM; hardware stack deeper than 31 |
| `E-RECURSION` | call cycle |
| `E-ISR-CALL` | call from a handler without `Save ... Restore` (also float maths) |
| `E-BACKEND` | valid per the front end but not generated yet (see below) |
| `E-UNSUPPORTED` | reserved but not available (`BitOf`, `Declare` other than `Xtal`, ...) |
| `W-CLOCK` | `Clock` differs from the `RSTOSC` speed and nothing sets the oscillator |
| `W-REGNAME` | a declaration hides a register name |

`E-BACKEND` ("not supported by the back end yet") means the front end accepted a rare form that the
code generator does not handle: a `Reentrant` routine, a bit passed `ByRef`, a call inside the index
of a bit, an array of strings, a function returning an array or String, and similar. The compiler
reports these rather than miscompiling them.

---

# Appendix A: Positron8 comparison

## Accepted Positron spellings

`Declare Xtal = n`; `Symbol`; `Proc`/`EndProc`/`ExitProc`; `Do`/`Loop` forms; type names `SByte`, `SWord`,
`Dword`, `Long` (and conversions); `$FF`, `%1010`; `:` between statements; `'` and `(* *)` comments;
` _` continuation; `Dim x As Type`; `Toggle`, `Inc`, `Dec`, `DelayMS`, `DelayUS`, `High`, `Low`,
`Input`, `Output` **with parentheses**; `Abs`; `Bound`.

## Not available (or different)

| Positron8 feature | basicc 0.1.6 |
|---|---|
| Other devices | only PIC18F27Q10 |
| Statements without parentheses (`High LED`, `DelayMs 500`, `HRsout "x"`) | parentheses required |
| `Declare` switches (LCD pins, baud, pin routing) | only `Declare Xtal`; peripherals take arguments in `...Init(...)` calls |
| `PinHigh`, `PinLow`, `PinSet`, `PinGet`, `PinMode`, pin numbers in `High` | use register bits / aliases |
| `Pin` type, `SDword`, `Double`, 24-bit `Long`, `Static`/`Global`/`Shared` variables | not accepted |
| `Print`, `Cls`, `Cursor`, `Plot`, `Line`, graphic LCD commands | `lcd` module routines; no graphics |
| `HRsout`, `HRsin`, `HSerout`, `Rsout`, `Serin`, `Serout` | `serial` / `serial2` routines |
| `Dec`, `Hex`, `Bin`, `Str$`, `Val` formatting modifiers | `SerialWriteWord`, `SerialWriteHex` only |
| `ADin`, `Pot`, `RCin` | `adc` module |
| `HPWM`, `PWM`, `Servo`, `Freqout`, `Sound` | `pwm` module (no servo/sound) |
| `Busin/Busout`, `I2Cin/I2Cout`, `Hbusin`, `Shin/Shout`, `Owrite/Oread`, `USBin` | `i2c`, `spi` modules; no 1-wire, USB, software SPI |
| `Read`/`Write` EEPROM, `Edata`, `Cdata`, `LookUp`, `LookDown` | `eeprom` module; `Const` arrays |
| `Branch`, `On GoTo`, `On GoSub`, `GoSub`, `Return`, `Call` | not available; use `Select` and routines |
| `Select Case x` | `Select x` |
| `Break`, `Continue`, `While/Wend`, `Repeat/Until`, `For/Next` | supported |
| `Sin`, `Cos`, `Sqr`, `Log`, `Exp`, `Pow`, `ISqr`, `Div32`, `Dcd`, `Ncd`, `@`, `?` | not available; `Abs`, `Min`, `Max` and arithmetic only |
| `Len`, `Left$`, `Mid$`, `Right$`, string arrays | not available |
| `Tern`, `SizeOf` | not available |
| `$config`, `Config` directive | `Config NAME = VALUE` with pack names |
| `$include`, `$asm`, `Asm` | `Include "name"`, `Asm ... End Asm` (pic-as syntax) |
| Interrupt via `On_Hardware_Interrupt` | `Interrupt Name() ... End Interrupt` plus `Enable` |
| `0x` and `0b` literals | `$` and `%` only |
| Overloading, `Reentrant` routines | not yet |

---

# Appendix B: Test checklist

Work down this list. Each item names what to observe.

**Build and size**
1. `basicc --version` prints `0.1.6`. `basicc --check` on a program with a deliberate error prints a
   code, line, column and caret.
2. Compile `my_src/first_test/main.bas`; confirm `.hex`, `.S`, `.map` appear and the size line prints.
3. Compile the same program with `-O0`; it should behave the same and be larger.

**Language (all verifiable on the bench with one LED and a scope or serial port)**
4. Blink with `DelayMS(500)` at your `Clock`: measure the period (should be 1.000 s). Repeat at 64, 32, 16, 8, 4, 1 MHz.
5. `DelayUS` with a pin toggle: measure 10, 100, 1000 us.
6. Integer arithmetic at each width: results printed over serial for `+ - * / Mod << >>` against known values.
7. `Select` with list, range and relational cases; `For` with negative `Step`; `Break`/`Continue`.
8. Arrays: initialiser, `Bound`, `Const` array read, copy; string append and compare.
9. Structure and union field access; `ByRef` parameter modifying the caller's variable.
10. Float: `+ - * /`, comparison, conversion to integer, print the integer part.
11. Interrupt: Timer0 interrupt toggling a pin; then a second priority; a call from the handler wrapped in `Save`.

**Library (hardware only; the simulator cannot show these)**
12. `serial`: 9600 and 115200 baud at 16 MHz and 64 MHz; check the characters and the error at each.
    Echo using `SerialAvailable`/`SerialRead`.
13. `serial2` on RB6/RB7 with the programmer disconnected.
14. `adc`: a potentiometer on RA0, readings 0..1023; the internal FVR channel; `AdcRefFvr(1)` scale.
15. `pwm`: frequency and duty on a scope on CCP1/CCP2/PWM3/PWM4 pins; `PwmInvert`; 100 % corner case.
16. `i2c`: `I2cPing` against a known device; read a register; remove the pull-up and confirm status 1.
17. `spi`: loop MOSI to MISO and confirm `SpiTransfer` returns what was sent, in all four modes.
18. `eeprom`: write, power-cycle, read back; byte and word forms; an out-of-range address.
19. `timer`: Timer0/1/2 flag periods; Timer1 as an external counter on RC0; gate and pulse measurement.
20. `lcd` and `oled`: text, cursor, custom character, contrast, invert, flip.
21. `intosc`/`system`: `Clock` at several values; `SysClockHz()` and `SysClockOk()` agree with a scope;
    `SysResetCause()` after power-on, MCLR and a watchdog reset.

Record anything that disagrees with this manual as a bug against the entry it came from.
