#include "tree_sitter/parser.h"
#include <string.h>

// Order must match `externals` in grammar.js.
enum { KW_PROGRAM, KW_MODULE, KW_SUB, KW_FUNCTION, KW_PROC, KW_INTERRUPT, KW_STRUCTURE, KW_CONST, KW_END, KW_EXIT, KW_COUNT };
static const char *const WORDS[KW_COUNT] = {"program", "module", "sub", "function", "proc", "interrupt", "structure", "const", "end", "exit"};

void *tree_sitter_picbasic_external_scanner_create(void) { return NULL; }
void tree_sitter_picbasic_external_scanner_destroy(void *p) { (void)p; }
unsigned tree_sitter_picbasic_external_scanner_serialize(void *p, char *b) { (void)p; (void)b; return 0; }
void tree_sitter_picbasic_external_scanner_deserialize(void *p, const char *b, unsigned n) { (void)p; (void)b; (void)n; }

// Zed's wasm sandbox has no libc ctype (isalnum/tolower are invalid imports), so do ASCII by hand.
static bool word_char(int32_t c) {
  return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
static char lower_ascii(int32_t c) { return (char)((c >= 'A' && c <= 'Z') ? c + 32 : c); }

bool tree_sitter_picbasic_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid) {
  (void)payload;
  while (lexer->lookahead == ' ' || lexer->lookahead == '\t' || lexer->lookahead == '\r' || lexer->lookahead == '\n')
    lexer->advance(lexer, true);

  char buf[16];
  unsigned n = 0;
  bool too_long = false;
  while (word_char(lexer->lookahead)) {
    if (n < sizeof buf - 1) buf[n++] = lower_ascii(lexer->lookahead); else too_long = true;
    lexer->advance(lexer, false);
  }
  if (n == 0 || too_long) return false;
  buf[n] = 0;

  for (int k = 0; k < KW_COUNT; k++) {
    if (valid[k] && strcmp(buf, WORDS[k]) == 0) {
      lexer->mark_end(lexer);
      lexer->result_symbol = (TSSymbol)k;
      return true;
    }
  }
  return false;
}
