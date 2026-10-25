# Diagnostic codes

Every message carries a stable code, shown as `error[E-TYPE]` / `warning[W-NARROW]`. Tests match on
codes, not on wording. Warnings can be switched off with `#option Warn.<id> = false` (for example
`Warn.Narrow`); `#option Strict = true` turns `W-NARROW` into the error `E-NARROW`.

## Source text
| Code | Meaning |
|---|---|
| E-LEX | Bad character, unterminated string or comment, number too large |
| E-SYNTAX | The text does not match the grammar |
| E-RESERVED | A reserved word used as a name |
| E-ORDER | Headers, includes, declarations and statements out of order |
| E-PP, E-PP-ERROR, E-PP-UNSUPPORTED | Preprocessor misuse, `#error`, `#if` family not implemented |
| E-OPTION | Unknown `#option` or bad value |
| W-PP-WARNING | `#warning` |

## Program structure
| Code | Meaning |
|---|---|
| E-NODEVICE, E-DEVICE | No `Device`, or no description file for it / it disagrees |
| E-CLOCK | `Clock` not a positive number, or two different values |
| E-CONFIG | Unknown configuration setting or value, setting given twice |
| E-INCLUDE | Module not found, include cycle, name mismatch, program included |
| W-REGNAME | A declaration reuses a device register's name and hides the register |
| E-REDECL, E-UNDECLARED, E-AMBIG, E-PRIVATE | Name clash, unknown name, same name in two modules, Private access |
| E-VIS, E-NESTED | `Public`/`Private` on a local; routine or type declared inside a routine |
| E-RAM | Global variables exceed the device's usable RAM |
| E-RECURSION | Call cycle without `Reentrant` (D13) |
| E-STACK | The hardware return stack can need more than 31 levels: deepest call chain of the main program (library helpers included) plus one level per interrupt priority and that handler's own chain |

## Types and expressions
| Code | Meaning |
|---|---|
| E-TYPE | Wrong type for the operation or assignment |
| E-MIX | Boolean mixed with a number (D11) |
| E-SIGN | Signed and unsigned operands that cannot be combined (D16) |
| E-CONST-EXPR, E-CONST-RANGE, E-CONST, E-CONST-ARRAY | Not constant; constant does not fit; bad constant declaration |
| E-DIM-ARRAY | An array initialiser has a different number of values than the array has elements |
| E-NARROW / W-NARROW | Value may not fit the target (error under `Strict`) |
| E-DIV0 | Constant division by zero |
| E-BOUNDS | Constant index, bit or modifier outside the object |
| E-NOMEMBER, E-NOTVALUE | No such field/modifier/register bit; a type, module or interrupt used as a value |
| E-ASSIGN, E-READONLY, E-ALIAS, E-ADDR | Bad assignment target, read-only target, bad alias or promotion, no address |
| E-DIM, E-STRUCT, E-SYMBOL | Bad `Dim`, empty structure, bad `Symbol` |

## Statements and routines
| Code | Meaning |
|---|---|
| E-COND | Condition is not Boolean |
| E-LOOP, E-EXIT, E-LABEL | `Break`/`Continue` outside a loop, `Exit` outside a routine, missing or duplicate label |
| E-FOR, E-LOOPVAR | Bad `For` variable or step; loop variable modified inside its loop |
| E-CASE-OVERLAP, E-CASE-RANGE, W-CASE-ELSE | Overlapping `Case`, empty range, `Else` that cannot run |
| E-CALL, E-ARGS, E-PARAM, E-STMT | Misused call, wrong argument count, bad parameter or argument, expression used as a statement |
| E-RESULT | `Result` outside a Function |
| W-NORESULT | Function never assigns its result |
| E-ISR-CALL, E-ISR-PRIO, E-ENABLE | Interrupt rules (D22), priorities, `Enable` of a non-interrupt |
| E-SAVE, E-ASM | Bad `Save` item, unknown register in `Asm Preserves` |
| E-UNSUPPORTED | Feature reserved but not specified (`BitOf`) or not built yet |
