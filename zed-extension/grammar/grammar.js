// Token-level grammar: highlighting is driven by queries, not by parse structure.
// Block bodies stay a flat token stream; declarations are recognised only so the outline can list them.
module.exports = grammar({
  name: 'picbasic',
  extras: $ => [/\s+/, $.comment],
  // Whole-word, case-insensitive keywords come from src/scanner.c (lexical precedence cannot express
  // that `Subtotal` is an identifier).
  externals: $ => [
    $.kw_program, $.kw_module, $.kw_sub, $.kw_function, $.kw_proc, $.kw_interrupt,
    $.kw_structure, $.kw_const, $.kw_end, $.kw_exit,
  ],
  rules: {
    source_file: $ => repeat($._token),
    _token: $ => choice(
      $.string, $.number, $.directive, $._declaration, $.end_statement, $.exit_statement,
      $.identifier, $.operator, $.punctuation, $.other,
    ),
    _declaration: $ => choice(
      $.program_declaration, $.module_declaration, $.sub_declaration, $.function_declaration,
      $.proc_declaration, $.interrupt_declaration, $.structure_declaration, $.const_declaration,
    ),
    program_declaration: $ => seq($.kw_program, field('name', $.identifier)),
    module_declaration: $ => seq($.kw_module, field('name', $.identifier)),
    sub_declaration: $ => seq($.kw_sub, field('name', $.identifier)),
    function_declaration: $ => seq($.kw_function, field('name', $.identifier)),
    proc_declaration: $ => seq($.kw_proc, field('name', $.identifier)),
    interrupt_declaration: $ => seq($.kw_interrupt, field('name', $.identifier)),
    structure_declaration: $ => seq($.kw_structure, field('name', $.identifier)),
    const_declaration: $ => seq($.kw_const, field('name', $.identifier)),
    // 'End Sub' / 'Exit Function' must not be read as the start of a declaration.
    end_statement: $ => prec.right(seq($.kw_end, optional(choice($.kw_sub, $.kw_function, $.kw_structure, $.kw_interrupt, $.kw_module, $.kw_program)))),
    exit_statement: $ => prec.right(seq($.kw_exit, optional(choice($.kw_sub, $.kw_function)))),
    // ' and // line comments, (* *) and { } block comments (not nested here; the compiler nests them).
    comment: _ => token(choice(
      /'[^\r\n]*/,
      /\/\/[^\r\n]*/,
      /\(\*([^*]|\*+[^*)])*\*+\)/,
      /\{[^}]*\}/,
    )),
    string: _ => token(/"[^"\r\n]*"/),
    // $FF, %0101, 0xFF, 1.5e3, 42, and #13 / #$0D character codes
    number: _ => token(choice(
      /#?\$[0-9A-Fa-f]+/, /#?0[xX][0-9A-Fa-f]+/, /#?%[01]+/,
      /[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?/, /#?[0-9]+/,
    )),
    directive: _ => token(/#[A-Za-z]+/),
    identifier: _ => /[A-Za-z_][A-Za-z0-9_]*/,
    operator: _ => token(choice('<>', '<=', '>=', '<<', '>>', '=', '<', '>', '+', '-', '*', '/', '@')),
    punctuation: _ => token(choice('(', ')', ',', '.', ':')),
    // Assembly lines inside Asm blocks and anything else unexpected: tolerated, never an error.
    other: _ => token(prec(-1, /[^\s]/)),
  },
});
