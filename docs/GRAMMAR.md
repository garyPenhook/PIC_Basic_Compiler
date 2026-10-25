# Grammar (draft 0.1)

EBNF for the core language described in `LANGUAGE.md`. Keywords are case-insensitive. Newlines end
statements; `:` also separates statements; ` _` at line end continues a line. Comments and
whitespace are removed by the lexer. `{ x }` zero or more, `[ x ]` optional, `( a | b )` choice,
terminals in quotes or `UPPER` for token classes.

This grammar is the contract for milestone M3 (front end), implemented in `src/lexer.rs` and
`src/parser.rs`. Alternative spellings (LANGUAGE.md §14) are added below as extra productions;
the parser rewrites them into the core forms.

## Lexical tokens

```
IDENT      = [ "_" ] LETTER { LETTER | DIGIT | "_" } ;
INT        = DIGIT { DIGIT } | "$" HEXDIGIT { HEXDIGIT } | "%" ( "0" | "1" ) { "0" | "1" } ;
FLOAT      = DIGIT { DIGIT } "." DIGIT { DIGIT } [ ( "e" | "E" ) [ "+" | "-" ] DIGIT { DIGIT } ] ;
STRING     = '"' { any-char-except-quote } '"' ;
CHARCODE   = "#" INT ;                                  (* a Char by code, e.g. #13 *)
EOL        = newline | ":" ;
```

Reserved words (initial list; extended by the device layer is **not** allowed — device register
names are ordinary identifiers resolved by the device description):
`absolute access addressof and as asm bit bitof boolean bound break byref byrefconst byte byval case char
clear clock compound config const continue dec delayms delayus device dim disable else elseif enable end
endif endselect event exit false float for function goto high if inc include inline input integer
interrupt longint longword low mod module next noinline not null or output private program public
reentrant repeat restore result save select shortint static step string structure sub terminate then to toggle
true type until volatile wend while word xor`

## Compilation units

```
unit        = program | module ;

program     = [ "Program" IDENT EOL ]
              { header }                      (* Device / Clock / Config, before anything else *)
              { include } { decl } { stmt }
              [ "End" ] ;

module      = "Module" IDENT EOL
              { header } { include } { decl } { stmt }
              [ "End" ] ;

header      = ( "Declare" "Xtal" "=" const_expr             (* alternative spelling of Clock *)
              | "Device" "=" device_name
              | "Clock"  "=" const_expr
              | "Config" config_item { "," config_item } ) EOL ;
device_name = IDENT | INT IDENT | INT ;           (* glued, no spaces: 18F27Q10, PIC18F27Q10 *)
config_item = IDENT "=" ( IDENT | INT ) ;

include     = "Include" STRING EOL ;
```

*Ordering rules* (enforced by the parser, not expressible in EBNF): headers → includes →
declarations → statements; no declaration or include after the first executable statement; every
identifier declared before use.

## Declarations

```
decl        = [ vis ] ( const_decl | dim_decl | struct_decl | type_decl | routine_decl
                      | interrupt_decl | event_decl | symbol_decl ) EOL ;
symbol_decl = "Symbol" IDENT [ "=" ] expr ;       (* alias or constant, decided by the value *)
vis         = "Public" | "Private" ;

const_decl  = "Const" const_item { "," const_item } ;
const_item  = IDENT [ "(" const_expr ")" ] [ "As" type ] "=" ( expr | "(" expr { "," expr } ")" ) ;

dim_decl    = { "Static" | "Volatile" } "Dim" dim_item { "," dim_item } [ "As" ( type | alias_target ) [ "=" ( expr | array_init ) ] ] ;
                                                  (* the trailing "=" needs a single scalar item *)
dim_item    = IDENT [ "(" const_expr ")" ] [ "=" ( expr | array_init ) ] ;
array_init  = "(" const_expr "," const_expr { "," const_expr } ")" ;   (* one value per element *)
alias_target= designator ;                        (* alias form: Dim LED As PORTB.0 *)

struct_decl = "Structure" IDENT EOL { field EOL } "End" "Structure" ;
field       = IDENT [ "(" const_expr ")" ] "As" ( type | designator ) ;

type_decl   = "Type" IDENT "=" ( "Event" "(" ")" ) ;

type        = "Boolean" | "Bit" | "Byte" | "ShortInt" | "Word" | "Integer"
            | "LongWord" | "LongInt" | "Float" | "Char"
            | "String" [ "(" const_expr ")" ] | IDENT ;       (* IDENT = structure/event type *)

routine_decl= { "Inline" | "NoInline" | "Reentrant" }
              ( "Sub" IDENT "(" [ params ] ")" EOL body "End" "Sub"
              | "Function" IDENT "(" [ params ] ")" "As" type EOL body "End" "Function"
              | "Proc" IDENT "(" [ params ] ")" [ "," type ] EOL body "EndProc" ) ;
params      = param { "," param } ;
param       = [ "ByVal" | "ByRef" | "ByRefConst" ] IDENT [ "(" ")" ] "As" type [ "=" const_expr ] ;
body        = { local_decl } { stmt } ;
local_decl  = ( const_decl | dim_decl | struct_decl ) EOL ;       (* as decl, but no vis prefix *)

interrupt_decl = "Interrupt" IDENT "(" [ const_expr ] ")" EOL body "End" "Interrupt" ;
event_decl     = "Event" IDENT "(" ")" EOL body "End" "Event" ;
```

## Statements

```
stmt        = ( assign | call | if_stmt | select_stmt | while_stmt | repeat_stmt | do_stmt | for_stmt
              | "Break" | "Continue" | "Exit" | "ExitProc" | goto_stmt | label | save_block
              | asm_block | enable_stmt ) EOL ;

assign      = designator "=" expr ;
call        = designator [ "(" [ expr { "," expr } ] ")" ] ;   (* arguments need parentheses;
                                                      a call with none may omit them *)

if_stmt     = "If" expr "Then" EOL { stmt } { "ElseIf" expr "Then" EOL { stmt } }
              [ "Else" EOL { stmt } ] "EndIf"
            | "If" expr "GoTo" IDENT ;

select_stmt = "Select" expr EOL
              { "Case" case_cond { "," case_cond } EOL { stmt } }
              [ "Else" EOL { stmt } ] "EndSelect" ;
case_cond   = expr [ "To" expr ] | relop expr ;   (* "Case Else" is accepted as "Else" *)

while_stmt  = "While" expr EOL { stmt } "Wend" ;
do_stmt     = "Do" [ ( "While" | "Until" ) expr ] EOL { stmt } "Loop" [ ( "Until" | "While" ) expr ] ;
                                                  (* a test at the top or at the bottom, not both *)
repeat_stmt = "Repeat" EOL { stmt } "Until" expr ;
for_stmt    = "For" designator "=" expr "To" expr [ "Step" expr ] EOL { stmt } "Next" ;

goto_stmt   = "GoTo" IDENT ;
label       = IDENT ":" ;                         (* first on its line, nothing after the colon *)
enable_stmt = ( "Enable" | "Disable" ) "(" IDENT ")" ;
save_block  = "Save" "(" save_item { "," save_item } ")" EOL { stmt } "Restore" ;
save_item   = designator | INT ;
asm_block   = "Asm" [ "Preserves" "(" IDENT { "," IDENT } ")" ] EOL { raw_asm_line } "End" "Asm" ;
```

## Expressions

Precedence is encoded in the production order (lowest first), matching `LANGUAGE.md` §5.1.

```
expr        = or_expr ;
or_expr     = and_expr { ( "Or" | "Xor" ) and_expr } ;
and_expr    = rel_expr { "And" rel_expr } ;
rel_expr    = shift_expr [ relop shift_expr ] ;
relop       = "=" | "<>" | "<" | ">" | "<=" | ">=" ;
shift_expr  = add_expr { ( "<<" | ">>" ) add_expr } ;
add_expr    = mul_expr { ( "+" | "-" ) mul_expr } ;
mul_expr    = unary { ( "*" | "/" | "Mod" ) unary } ;
unary       = ( "-" | "+" | "Not" | "@" ) unary | primary ;
primary     = INT | FLOAT | STRING | CHARCODE | "True" | "False" | "Null"
            | designator [ "(" [ expr { "," expr } ] ")" ]        (* function call or index *)
            | "(" expr ")" ;

designator  = IDENT { "." IDENT | "(" expr { "," expr } ")" } ;   (* name, field, modifier, index *)
const_expr  = expr ;                                               (* checked constant by the semantic pass *)
```

Block ends may be written closed (`EndIf`, `EndSelect`) or open (`End If`, `End Select`).
A single-line `If c Then statement` is not part of the grammar and is rejected with a message.
Preprocessor lines (`#define`, `#ifdef` …) are handled before lexing (`src/pp.rs`).

Disambiguation notes (resolved in semantic analysis, not in the grammar):
* `name(args)` is a function call, a subroutine call, or an array index depending on what `name`
  was declared as; modifiers (`.Byte1`, `.Bits(3)`, `.7`) are resolved the same way.
* A bare `.7` after a designator selects a bit; `PORTB.0` is a port bit alias target.
* `=` is assignment at statement start and equality inside an expression.
* `@x` takes the address of `x`; `AddressOf(x)` is the equivalent intrinsic form.

## Not yet covered

Overloading and compound subroutines (M9), `With` statements, multi-dimensional arrays (not
supported in 0.1).
