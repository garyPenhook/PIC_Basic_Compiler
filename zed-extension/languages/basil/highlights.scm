; Case-insensitive word lists come from vscode-extension/src/keywords.js (the compiler's own reserved words).
(comment) @comment
(string) @string
(number) @number
(directive) @preproc
(operator) @operator
(punctuation) @punctuation.delimiter

[(kw_program) (kw_module) (kw_sub) (kw_function) (kw_proc) (kw_interrupt) (kw_structure) (kw_const) (kw_end) (kw_exit)] @keyword

(program_declaration name: (_) @namespace)
(module_declaration name: (_) @namespace)
(sub_declaration name: (_) @function)
(function_declaration name: (_) @function)
(proc_declaration name: (_) @function)
(interrupt_declaration name: (_) @function)
(structure_declaration name: (_) @type)
(const_declaration name: (_) @constant)

((identifier) @boolean (#match? @boolean "^(?i)(true|false)$"))
((identifier) @constant.builtin (#match? @constant.builtin "^(?i)null$"))
((identifier) @type.builtin (#match? @type.builtin "^(?i)(bit|boolean|byte|char|float|integer|longint|longword|shortint|string|word|sbyte|sword|long|dword)$"))
((identifier) @function.builtin (#match? @function.builtin "^(?i)(addressof|bound|clear|dec|delayms|delayus|disable|enable|high|inc|input|low|output|terminate|toggle)$"))
((identifier) @keyword (#match? @keyword "^(?i)(absolute|access|and|as|asm|bitof|break|byref|byrefconst|byval|case|cfile|clock|compound|config|const|continue|device|dim|else|elseif|end|endif|endselect|event|exit|export|extern|for|function|goto|if|include|inline|interrupt|mod|module|next|noinline|not|or|private|program|public|reentrant|repeat|restore|result|save|select|static|step|structure|sub|then|to|type|until|volatile|wend|while|xor|declare|do|endproc|exitproc|loop|proc|symbol)$"))
