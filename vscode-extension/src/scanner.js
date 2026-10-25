'use strict';
// A small line scanner that mirrors src/lexer.rs closely enough for editor features: it knows
// strings, ' and // comments, nested (* *) and { } block comments, $hex / %binary / #char
// literals, preprocessor lines and Asm...End Asm blocks. It does not parse.

const { KEYWORDS } = require('./keywords');

const isAlpha = (c) => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '_';
const isDigit = (c) => c >= '0' && c <= '9';
const isHex = (c) => isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
const isBin = (c) => c === '0' || c === '1';

/** True when a line closes an Asm block (`End Asm`, optionally followed by a comment). */
function isEndAsm(text) {
  const m = /^\s*end\s+asm(?![A-Za-z0-9_])/i.exec(text);
  return m !== null;
}

/**
 * Scans `text` into lines of tokens.
 * Token: { t: 'word'|'string'|'comment'|'number'|'punct'|'pp', s, e, text, member? }
 * Line:  { text, tokens, raw, inComment }
 *   raw       — inside an Asm block: the line is not BASIC and must be left alone
 *   inComment — the line starts inside a block comment
 */
function scan(text) {
  const src = text.split(/\r?\n/);
  const lines = [];
  const blocks = []; // open block comments: '(' or '{'
  let asmPending = false;
  let inAsm = false;

  for (const lineText of src) {
    const line = { text: lineText, tokens: [], raw: false, inComment: blocks.length > 0 };
    lines.push(line);

    if (inAsm) {
      if (isEndAsm(lineText)) inAsm = false;
      else {
        line.raw = true;
        continue;
      }
    }

    const n = lineText.length;
    let i = 0;
    let stmtStart = true; // no token yet in this statement
    const push = (t, s, e, extra) => line.tokens.push(Object.assign({ t, s, e, text: lineText.slice(s, e) }, extra));

    // Preprocessor directive: the whole line, apart from a trailing comment, is not BASIC.
    if (blocks.length === 0 && /^\s*#[A-Za-z]/.test(lineText)) {
      const s = lineText.search(/\S/);
      push('pp', s, n);
      continue;
    }

    while (i < n) {
      const c = lineText[i];
      if (blocks.length > 0) {
        const open = blocks[blocks.length - 1];
        if (c === '*' && lineText[i + 1] === ')' && open === '(') {
          blocks.pop();
          i += 2;
        } else if (c === '}' && open === '{') {
          blocks.pop();
          i += 1;
        } else if (c === '(' && lineText[i + 1] === '*') {
          blocks.push('(');
          i += 2;
        } else if (c === '{') {
          blocks.push('{');
          i += 1;
        } else i += 1;
        continue;
      }
      if (c === ' ' || c === '\t') {
        i += 1;
      } else if (c === "'" || (c === '/' && lineText[i + 1] === '/')) {
        push('comment', i, n);
        i = n;
      } else if (c === '(' && lineText[i + 1] === '*') {
        blocks.push('(');
        i += 2;
      } else if (c === '{') {
        blocks.push('{');
        i += 1;
      } else if (c === '"') {
        let j = i + 1;
        while (j < n && lineText[j] !== '"') j += 1;
        if (j < n) j += 1;
        push('string', i, j);
        i = j;
        stmtStart = false;
      } else if (isAlpha(c)) {
        let j = i + 1;
        while (j < n && (isAlpha(lineText[j]) || isDigit(lineText[j]))) j += 1;
        const member = line.tokens.length > 0 && line.tokens[line.tokens.length - 1].text === '.' && line.tokens[line.tokens.length - 1].e === i;
        push('word', i, j, { member, stmtStart });
        if (asmPending === false && stmtStart && !member && lineText.slice(i, j).toLowerCase() === 'asm') asmPending = true;
        i = j;
        stmtStart = false;
      } else if (isDigit(c)) {
        let j = i + 1;
        while (j < n && isDigit(lineText[j])) j += 1;
        if (lineText[j] === '.' && isDigit(lineText[j + 1] || '')) {
          j += 1;
          while (j < n && isDigit(lineText[j])) j += 1;
          if (lineText[j] === 'e' || lineText[j] === 'E') {
            let k = j + 1;
            if (lineText[k] === '+' || lineText[k] === '-') k += 1;
            if (isDigit(lineText[k] || '')) {
              while (k < n && isDigit(lineText[k])) k += 1;
              j = k;
            }
          }
        }
        // A literal glued to letters (a device name such as 18F27Q10) is one lexeme.
        while (j < n && (isAlpha(lineText[j]) || isDigit(lineText[j]))) j += 1;
        push('number', i, j);
        i = j;
        stmtStart = false;
      } else if ((c === '$' && isHex(lineText[i + 1] || '')) || (c === '%' && isBin(lineText[i + 1] || ''))) {
        const ok = c === '$' ? isHex : isBin;
        let j = i + 1;
        while (j < n && ok(lineText[j])) j += 1;
        push('number', i, j);
        i = j;
        stmtStart = false;
      } else if (c === '#') {
        let j = i + 1;
        if (lineText[j] === '$' || lineText[j] === '%') j += 1;
        while (j < n && (isDigit(lineText[j]) || isHex(lineText[j]))) j += 1;
        push('number', i, j);
        i = j;
        stmtStart = false;
      } else {
        push('punct', i, i + 1);
        stmtStart = c === ':';
        i += 1;
      }
    }

    if (asmPending) {
      asmPending = false;
      inAsm = true;
    }
  }
  return lines;
}

/** The significant (non-comment) tokens of a line. */
function code(line) {
  return line.tokens.filter((t) => t.t !== 'comment');
}

const lower = (t) => (t && t.t === 'word' ? t.text.toLowerCase() : '');

// Words after these name something the program declares, which then shadows a device name.
const DECLARERS = new Set(['dim', 'const', 'symbol', 'sub', 'function', 'proc', 'event', 'interrupt', 'structure']);

/**
 * Edits that put every reserved word in its canonical spelling, and, given `names` (lower-case to
 * canonical, from the device description), every register and bit name too. A name the program
 * declares itself is left as typed.
 * Returns [{ line, s, e, text }] (0-based line, column offsets).
 */
function caseEdits(lines, names) {
  const edits = [];
  const own = new Set();
  if (names) {
    for (const line of lines) {
      if (line.raw) continue;
      const toks = code(line);
      toks.forEach((t, i) => {
        if (t.t === 'word' && !t.member && DECLARERS.has(t.text.toLowerCase()) && toks[i + 1] && toks[i + 1].t === 'word') own.add(toks[i + 1].text.toLowerCase());
      });
    }
  }
  lines.forEach((line, ln) => {
    if (line.raw) return;
    const toks = code(line);
    let inConfig = false; // after `Config`, words are setting names and values, not keywords
    toks.forEach((tok, ti) => {
      if (tok.t === 'punct' && tok.text === ':') inConfig = false;
      if (tok.t !== 'word') return;
      const low = tok.text.toLowerCase();
      if (tok.member) {
        // `lata.lata0`: a bit of a register is corrected only after a device name.
        const owner = toks[ti - 2];
        const canonBit = names && !inConfig && owner && owner.t === 'word' && names.has(owner.text.toLowerCase()) && !own.has(owner.text.toLowerCase()) ? names.get(low) : undefined;
        if (canonBit && tok.text !== canonBit) edits.push({ line: ln, s: tok.s, e: tok.e, text: canonBit });
        return;
      }
      const canon = KEYWORDS.get(low) || (names && !own.has(low) ? names.get(low) : undefined);
      if (inConfig || !canon) return;
      if (canon === 'Config' && tok.stmtStart) inConfig = true;
      if (tok.text !== canon) edits.push({ line: ln, s: tok.s, e: tok.e, text: canon });
    });
  });
  return edits;
}

// --- indentation -------------------------------------------------------------------------

const MODIFIERS = new Set(['public', 'private', 'inline', 'noinline', 'reentrant']);
const ROUTINE = new Set(['sub', 'function', 'proc', 'interrupt', 'event', 'structure']);
const END_KIND = { sub: 'sub', function: 'function', if: 'if', select: 'select', structure: 'structure', interrupt: 'interrupt', event: 'event', asm: 'asm' };
const SINGLE_CLOSE = { endif: 'if', endselect: 'select', endproc: 'proc', wend: 'while', next: 'for', until: 'repeat', loop: 'do', restore: 'save' };

/** The statement head of a line: [kind, tokens after modifiers]. */
function head(toks) {
  let k = 0;
  while (k < toks.length && toks[k].t === 'word' && MODIFIERS.has(lower(toks[k])) && k + 1 < toks.length) k += 1;
  return { word: lower(toks[k]), rest: toks.slice(k + 1), k };
}

/**
 * Indent level for each line (null = leave the line alone).
 */
function indentLevels(lines) {
  const out = new Array(lines.length).fill(null);
  const stack = []; // block kinds: 'sub', 'if', 'select', 'case', ...
  let continued = false;

  const popTo = (kind) => {
    const at = stack.lastIndexOf(kind);
    if (at >= 0) stack.length = at;
  };

  lines.forEach((line, ln) => {
    if (line.raw || line.inComment) return;
    const toks = code(line);
    const wasContinued = continued;
    const last = toks[toks.length - 1];
    continued = !!last && last.t === 'punct' && last.text === '_' ;
    // `_` is lexed as a word when alone; handle both forms.
    if (!continued && last && last.t === 'word' && last.text === '_') continued = true;
    if (wasContinued) return;
    if (toks.length === 0) {
      // Blank or comment-only: a comment follows the current depth.
      out[ln] = line.tokens.length > 0 ? stack.length : null;
      return;
    }
    if (toks[0].t === 'pp') {
      out[ln] = 0;
      return;
    }
    const { word, rest, k } = head(toks);
    const w2 = lower(rest[0]);
    let level;

    if (toks[k] && toks[k].t === 'word' && !toks[k].member) {
      if (word === 'end' && END_KIND[w2]) {
        const kind = END_KIND[w2];
        if (kind === 'select' && stack[stack.length - 1] === 'case') stack.pop();
        popTo(kind);
        level = stack.length;
      } else if (SINGLE_CLOSE[word]) {
        if (word === 'endselect' && stack[stack.length - 1] === 'case') stack.pop();
        popTo(SINGLE_CLOSE[word]);
        level = stack.length;
      } else if (word === 'case' || ((word === 'else') && (stack[stack.length - 1] === 'case' || stack[stack.length - 1] === 'select'))) {
        if (stack[stack.length - 1] === 'case') stack.pop();
        level = stack.length;
        if (stack[stack.length - 1] === 'select') stack.push('case');
      } else if (word === 'else' || word === 'elseif') {
        level = Math.max(0, stack.lastIndexOf('if'));
        if (stack.lastIndexOf('if') < 0) level = stack.length;
      } else if (ROUTINE.has(word)) {
        level = stack.length;
        stack.push(word === 'proc' ? 'proc' : word);
      } else if (word === 'if') {
        level = stack.length;
        if (lower(toks[toks.length - 1]) === 'then') stack.push('if');
      } else if (word === 'select') {
        level = stack.length;
        stack.push('select');
      } else if (word === 'while') {
        level = stack.length;
        stack.push('while');
      } else if (word === 'for') {
        level = stack.length;
        stack.push('for');
      } else if (word === 'repeat') {
        level = stack.length;
        stack.push('repeat');
      } else if (word === 'do') {
        level = stack.length;
        stack.push('do');
      } else if (word === 'save' && rest[0] && rest[0].text === '(') {
        level = stack.length;
        stack.push('save');
      } else if (word === 'asm' && toks[k].stmtStart) {
        level = stack.length;
        stack.push('asm');
      } else {
        level = stack.length;
      }
    } else {
      level = stack.length;
    }
    out[ln] = level;
  });
  return out;
}

module.exports = { scan, code, caseEdits, indentLevels, isEndAsm, lower };
