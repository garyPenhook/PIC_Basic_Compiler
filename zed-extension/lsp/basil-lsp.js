#!/usr/bin/env node
'use strict';
// Minimal language server for the basil PIC BASIC compiler: diagnostics from `basil --check`,
// keyword and symbol completion, keyword hover and a document outline. Standard library only.
// The keyword table is shared with the VS Code extension so the two cannot drift apart.

const cp = require('child_process');
const fs = require('fs');
const path = require('path');
const { CANONICAL, ALIASES, KEYWORDS, DOCS } = require('../../vscode-extension/src/keywords');

// diagnostic line: file:line:col: error[E-CODE]: message
const RE_DIAG = /^(.+?):(\d+):(\d+): (error|warning)\[([^\]]+)\]: (.*)$/;
// LSP kinds
const K = { function: 12, variable: 13, constant: 21, struct: 23, module: 2, keyword: 14, event: 24, field: 5 };
const TYPE_NAMES = ['Bit', 'Boolean', 'Byte', 'Char', 'Float', 'Integer', 'LongInt', 'LongWord', 'ShortInt', 'String', 'Word', 'SByte', 'SWord', 'Long', 'Dword'];

let opts = { compilerPath: 'basil', compilerArgs: [], diagnostics: 'onChange' };
const docs = new Map(); // uri -> text
const timers = new Map();

// --- transport -------------------------------------------------------------------------------
function send(msg) {
  const body = JSON.stringify({ jsonrpc: '2.0', ...msg });
  process.stdout.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
}
const reply = (id, result) => send({ id, result });
const notify = (method, params) => send({ method, params });

let buf = Buffer.alloc(0);
process.stdin.on('data', (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  for (;;) {
    const end = buf.indexOf('\r\n\r\n');
    if (end < 0) return;
    const m = /Content-Length: *(\d+)/i.exec(buf.slice(0, end).toString('ascii'));
    if (!m) { buf = buf.slice(end + 4); continue; }
    const len = +m[1];
    if (buf.length < end + 4 + len) return;
    const body = buf.slice(end + 4, end + 4 + len).toString('utf8');
    buf = buf.slice(end + 4 + len);
    try { handle(JSON.parse(body)); } catch (e) { process.stderr.write(`basil-lsp: ${e.stack}\n`); }
  }
});
process.stdin.on('end', () => process.exit(0));

// --- helpers ---------------------------------------------------------------------------------
const uriToPath = (u) => decodeURIComponent(u.replace(/^file:\/\//, ''));
const pathToUri = (p) => 'file://' + p.split('/').map(encodeURIComponent).join('/');

/** Declarations found by a line regex. Good enough for outline and completion; it does not parse. */
function symbols(text) {
  const out = [];
  text.split(/\r?\n/).forEach((line, i) => {
    let m;
    const at = (name, kind, detail) => out.push({ name, kind, detail, line: i, col: line.indexOf(name, m.index) });
    if ((m = /^\s*(?:(?:Public|Private|Inline|NoInline|Reentrant)\s+)*(Sub|Function|Proc)\s+([A-Za-z_]\w*)/i.exec(line))) at(m[2], K.function, m[1]);
    else if ((m = /^\s*Interrupt\s+([A-Za-z_]\w*)/i.exec(line))) at(m[1], K.event, 'Interrupt');
    else if ((m = /^\s*Event\s+([A-Za-z_]\w*)/i.exec(line))) at(m[1], K.event, 'Event');
    else if ((m = /^\s*(?:(?:Public|Private)\s+)?Structure\s+([A-Za-z_]\w*)/i.exec(line))) at(m[1], K.struct, 'Structure');
    else if ((m = /^\s*(?:(?:Public|Private)\s+)?Const\s+([A-Za-z_]\w*)/i.exec(line))) at(m[1], K.constant, 'Const');
    else if ((m = /^\s*(?:(?:Public|Private|Static|Volatile)\s+)*Dim\s+([A-Za-z_]\w*)/i.exec(line))) at(m[1], K.variable, 'Dim');
    else if ((m = /^\s*Symbol\s+([A-Za-z_]\w*)/i.exec(line))) at(m[1], K.constant, 'Symbol');
    else if ((m = /^\s*(Program|Module)\s+([A-Za-z_]\w*)/i.exec(line))) at(m[2], K.module, m[1]);
  });
  return out;
}

function wordAt(text, pos) {
  const line = text.split(/\r?\n/)[pos.line] || '';
  let s = pos.character, e = pos.character;
  while (s > 0 && /\w/.test(line[s - 1])) s--;
  while (e < line.length && /\w/.test(line[e])) e++;
  return line.slice(s, e);
}

// --- diagnostics -----------------------------------------------------------------------------
function runCheck(uri, file, cleanup) {
  const cwd = path.dirname(uriToPath(uri));
  cp.execFile(opts.compilerPath, ['--check', ...opts.compilerArgs, file], { cwd, timeout: 30000 }, (err, stdout, stderr) => {
    if (cleanup) cleanup();
    if (err && err.code === 'ENOENT') {
      notify('window/showMessage', { type: 2, message: `basil-lsp: cannot run "${opts.compilerPath}". Put basil on PATH or set initialization_options.compilerPath.` });
      return;
    }
    const real = uriToPath(uri);
    const lines = (docs.get(uri) || '').split(/\r?\n/);
    const byFile = new Map();
    for (const raw of (stdout + '\n' + stderr).split(/\r?\n/)) {
      const m = RE_DIAG.exec(raw);
      if (!m) continue;
      let f = path.resolve(cwd, m[1]);
      if (f === file) f = real;
      const ln = Math.max(0, +m[2] - 1), col = Math.max(0, +m[3] - 1);
      const text = f === real ? lines[ln] || '' : '';
      const w = /^[A-Za-z0-9_$%#]+/.exec(text.slice(col));
      const d = {
        range: { start: { line: ln, character: col }, end: { line: ln, character: col + (w ? w[0].length : Math.max(1, text.length - col)) } },
        severity: m[4] === 'error' ? 1 : 2, code: m[5], source: 'basil', message: m[6],
      };
      if (!byFile.has(f)) byFile.set(f, []);
      byFile.get(f).push(d);
    }
    // Always publish the open file (empty clears old squiggles); other files only when they have problems.
    if (!byFile.has(real)) byFile.set(real, []);
    for (const [f, diagnostics] of byFile) notify('textDocument/publishDiagnostics', { uri: pathToUri(f), diagnostics });
  });
}

function check(uri, typing) {
  const text = docs.get(uri);
  if (text === undefined || opts.diagnostics === 'off') return;
  // A library module has no Device, so checking it alone reports every register as undeclared.
  if (/^\s*Module\s/im.test(text)) { notify('textDocument/publishDiagnostics', { uri, diagnostics: [] }); return; }
  const file = uriToPath(uri);
  if (!typing) return runCheck(uri, file);
  if (opts.diagnostics !== 'onChange') return;
  clearTimeout(timers.get(uri));
  timers.set(uri, setTimeout(() => {
    // A temporary copy beside the file keeps relative Includes working.
    const tmp = path.join(path.dirname(file), `.${path.basename(file, '.bas')}.zed-tmp.bas`);
    try { fs.writeFileSync(tmp, text); } catch { return; }
    runCheck(uri, tmp, () => fs.rm(tmp, { force: true }, () => {}));
  }, 700));
}

// --- requests --------------------------------------------------------------------------------
function completion(uri) {
  const items = CANONICAL.concat(ALIASES).map((k) => ({
    label: k, kind: TYPE_NAMES.includes(k) ? 7 : K.keyword, detail: 'keyword',
    documentation: DOCS[k] ? { kind: 'markdown', value: DOCS[k] } : undefined,
  }));
  const seen = new Set(items.map((i) => i.label.toLowerCase()));
  for (const s of symbols(docs.get(uri) || '')) {
    if (seen.has(s.name.toLowerCase())) continue;
    seen.add(s.name.toLowerCase());
    items.push({ label: s.name, kind: s.kind, detail: s.detail });
  }
  return { isIncomplete: false, items };
}

function hover(uri, pos) {
  const text = docs.get(uri) || '';
  const w = wordAt(text, pos);
  const kw = KEYWORDS.get(w.toLowerCase());
  if (kw && DOCS[kw]) return { contents: { kind: 'markdown', value: `**${kw}**\n\n${DOCS[kw]}` } };
  const s = symbols(text).find((x) => x.name.toLowerCase() === w.toLowerCase());
  if (s) return { contents: { kind: 'markdown', value: `\`${text.split(/\r?\n/)[s.line].trim()}\`` } };
  return null;
}

function documentSymbols(uri) {
  const lines = (docs.get(uri) || '').split(/\r?\n/);
  return symbols(docs.get(uri) || '')
    .filter((s) => s.detail !== 'Dim' || !/^\s{2,}|^\t/.test(lines[s.line])) // globals only
    .map((s) => {
      const range = { start: { line: s.line, character: 0 }, end: { line: s.line, character: lines[s.line].length } };
      return { name: s.name, detail: s.detail, kind: s.kind, range, selectionRange: { start: { line: s.line, character: s.col }, end: { line: s.line, character: s.col + s.name.length } } };
    });
}

function handle(msg) {
  const { id, method, params } = msg;
  switch (method) {
    case 'initialize':
      opts = Object.assign(opts, params && params.initializationOptions);
      return reply(id, {
        capabilities: {
          textDocumentSync: { openClose: true, change: 1, save: { includeText: false } },
          completionProvider: { triggerCharacters: ['.'] },
          hoverProvider: true,
          documentSymbolProvider: true,
        },
        serverInfo: { name: 'basil-lsp' },
      });
    case 'initialized': return;
    case 'shutdown': return reply(id, null);
    case 'exit': return process.exit(0);
    case 'textDocument/didOpen':
      docs.set(params.textDocument.uri, params.textDocument.text);
      return check(params.textDocument.uri, false);
    case 'textDocument/didChange':
      docs.set(params.textDocument.uri, params.contentChanges[params.contentChanges.length - 1].text);
      return check(params.textDocument.uri, true);
    case 'textDocument/didSave': return check(params.textDocument.uri, false);
    case 'textDocument/didClose':
      docs.delete(params.textDocument.uri);
      clearTimeout(timers.get(params.textDocument.uri));
      return notify('textDocument/publishDiagnostics', { uri: params.textDocument.uri, diagnostics: [] });
    case 'textDocument/completion': return reply(id, completion(params.textDocument.uri));
    case 'textDocument/hover': return reply(id, hover(params.textDocument.uri, params.position));
    case 'textDocument/documentSymbol': return reply(id, documentSymbols(params.textDocument.uri));
    default:
      if (id !== undefined) send({ id, error: { code: -32601, message: `method not found: ${method}` } });
  }
}
