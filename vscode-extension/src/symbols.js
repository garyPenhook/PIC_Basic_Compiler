'use strict';
// Declaration index for outline, go-to-definition, hover, completion and signature help.

const { scan, code, lower } = require('./scanner');

const MODS = new Set(['public', 'private', 'inline', 'noinline', 'reentrant', 'export', 'extern']);

/**
 * Extracts declarations from source text.
 * Symbol: { name, kind, line, col, vis, signature, params, returns, doc, endLine }
 * kind: module | program | sub | function | proc | interrupt | event | structure | type | const | dim | symbol
 */
function parseSymbols(text) {
  const lines = scan(text);
  const syms = [];
  const open = []; // routine/structure symbols still waiting for their End
  let comment = [];

  lines.forEach((line, ln) => {
    if (line.raw || line.inComment) {
      comment = [];
      return;
    }
    const toks = code(line);
    if (toks.length === 0) {
      const c = line.tokens.find((t) => t.t === 'comment');
      if (c) comment.push(c.text.replace(/^('+|\/\/)\s?/, ''));
      else comment = [];
      return;
    }
    const doc = comment.join('\n');
    comment = [];

    let k = 0;
    let vis = 'private';
    let isExtern = false; // `Extern Sub/Function` has no body, so no End to wait for
    while (k < toks.length - 1 && toks[k].t === 'word' && MODS.has(lower(toks[k]))) {
      if (lower(toks[k]) === 'public') vis = 'public';
      if (lower(toks[k]) === 'extern') isExtern = true;
      k += 1;
    }
    const w = lower(toks[k]);
    const nameTok = toks[k + 1];
    const add = (kind, tok, extra) => {
      const s = Object.assign({ name: tok.text, kind, line: ln, col: tok.s, vis, doc, endLine: ln }, extra);
      syms.push(s);
      return s;
    };

    if ((w === 'module' || w === 'program') && nameTok && nameTok.t === 'word') {
      add(w, nameTok);
    } else if (['sub', 'function', 'proc', 'interrupt', 'event'].includes(w) && nameTok && nameTok.t === 'word') {
      // Signature: from the name to the end of the code on this line.
      const sig = line.text.slice(nameTok.s, toks[toks.length - 1].e);
      const open_ = line.text.indexOf('(', nameTok.e);
      let params = '';
      let close = -1;
      if (open_ >= 0) {
        let depth = 0;
        for (let i = open_; i < line.text.length; i += 1) {
          if (line.text[i] === '(') depth += 1;
          else if (line.text[i] === ')' && --depth === 0) {
            close = i;
            break;
          }
        }
        params = line.text.slice(open_ + 1, close < 0 ? undefined : close);
      }
      let returns = '';
      if (close >= 0) {
        const m = /^\s*(?:As\s+|,\s*)([A-Za-z_][A-Za-z0-9_]*(?:\s*\(\s*\d+\s*\))?)/i.exec(line.text.slice(close + 1));
        if (m) returns = m[1];
      }
      const s = add(w, nameTok, { signature: sig, params, returns });
      if (!isExtern) open.push(s);
    } else if (w === 'structure' && nameTok && nameTok.t === 'word') {
      open.push(add('structure', nameTok));
    } else if (w === 'type' && nameTok && nameTok.t === 'word') {
      add('type', nameTok);
    } else if (w === 'symbol' && nameTok && nameTok.t === 'word') {
      add('symbol', nameTok, { signature: line.text.slice(nameTok.s).trim() });
    } else if (w === 'const' || w === 'dim') {
      // `Dim a, b(4) As Byte`: every name before `As` or `=`.
      const inRoutine = open.length > 0;
      let depth = 0;
      let expectName = true;
      for (let i = k + 1; i < toks.length; i += 1) {
        const t = toks[i];
        if (t.t === 'punct' && t.text === '(') depth += 1;
        else if (t.t === 'punct' && t.text === ')') depth -= 1;
        else if (depth === 0 && t.t === 'word' && lower(t) === 'as') break;
        else if (depth === 0 && t.t === 'punct' && t.text === '=') break;
        else if (depth === 0 && t.t === 'punct' && t.text === ',') expectName = true;
        else if (depth === 0 && t.t === 'word' && expectName) {
          add(w, t, { signature: line.text.slice(toks[k].s, toks[toks.length - 1].e).trim(), local: inRoutine });
          expectName = false;
        }
      }
    } else if (w === 'end' || w === 'endproc') {
      const target = lower(toks[k + 1]);
      if (w === 'endproc' || ['sub', 'function', 'interrupt', 'event', 'structure'].includes(target)) {
        const s = open.pop();
        if (s) s.endLine = ln;
      }
    }
  });
  return syms;
}

/** `Include "Name"` targets in a file. */
function parseIncludes(text) {
  const out = [];
  scan(text).forEach((line, ln) => {
    if (line.raw || line.inComment) return;
    const toks = code(line);
    if (toks.length >= 2 && lower(toks[0]) === 'include' && toks[1].t === 'string') {
      out.push({ name: toks[1].text.slice(1, -1), line: ln });
    }
  });
  return out;
}

module.exports = { parseSymbols, parseIncludes };
