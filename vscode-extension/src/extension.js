'use strict';
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const { scan, caseEdits, indentLevels } = require('./scanner');
const { parseSymbols, parseIncludes } = require('./symbols');
const { CANONICAL, ALIASES, KEYWORDS, TYPES, DOCS } = require('./keywords');
const { deviceOf, loadNames, devicesAbove } = require('./devicenames');

const LANG = 'picbasic';
const cfg = () => vscode.workspace.getConfiguration('picbasic');

// --- keyword case ------------------------------------------------------------------------

const toRange = (e) => new vscode.Range(e.line, e.s, e.line, e.e);
const toEdit = (e) => vscode.TextEdit.replace(toRange(e), e.text);

/** Register and bit names of the document's `Device`, or undefined when off or not found. */
function deviceNames(doc, lines) {
  if (!cfg().get('autoCorrectDeviceNames')) return undefined;
  const device = deviceOf(lines);
  if (!device) return undefined;
  const dirs = [];
  const extra = cfg().get('devicesPath');
  if (extra) dirs.push(extra);
  if (doc.uri.scheme === 'file') dirs.push(...devicesAbove(path.dirname(doc.uri.fsPath)));
  for (const f of vscode.workspace.workspaceFolders || []) dirs.push(path.join(f.uri.fsPath, 'devices'));
  // A development build lives in <repo>/target/<profile>/basicc, next to <repo>/devices.
  const exe = cfg().get('compilerPath');
  if (exe && path.isAbsolute(exe)) dirs.push(...devicesAbove(path.dirname(exe)));
  return loadNames(device, dirs) || undefined;
}

/** Keyword and device-name corrections for a whole document. */
function docCaseEdits(doc, lines) {
  lines = lines || scan(doc.getText());
  return caseEdits(lines, deviceNames(doc, lines));
}

function allCaseEdits(doc) {
  return docCaseEdits(doc).map(toEdit);
}

let applying = false;

/** Corrects the word completed by a just-typed separator. */
function onTyped(ev) {
  if (applying || !cfg().get('autoCorrectKeywords')) return;
  const doc = ev.document;
  if (doc.languageId !== LANG || ev.contentChanges.length === 0) return;
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document !== doc) return;

  // Lines that received a typed separator (a single non-word character, or a newline).
  const lines = new Set();
  for (const ch of ev.contentChanges) {
    if (ch.rangeLength > 0 && ch.text === '') continue; // deletion
    if (ch.text.length === 0 || ch.text.length > 12) continue; // paste or auto-indent only: left to the formatter
    if (/^[A-Za-z0-9_$%#]$/.test(ch.text)) continue; // still inside a word
    const ln = ch.range.start.line;
    lines.add(ln);
  }
  if (lines.size === 0) return;

  const edits = docCaseEdits(doc).filter((e) => lines.has(e.line));
  // Only a word that ends at or before the typed separator; never one the cursor is inside.
  const sel = editor.selections.map((s) => s.active);
  const safe = edits.filter((e) => !sel.some((p) => p.line === e.line && p.character > e.s && p.character < e.e));
  if (safe.length === 0) return;
  applying = true;
  editor
    .edit((b) => safe.forEach((e) => b.replace(toRange(e), e.text)), { undoStopBefore: false, undoStopAfter: false })
    .then(() => (applying = false), () => (applying = false));
}

// --- formatting --------------------------------------------------------------------------

function formatEdits(doc, options) {
  const text = doc.getText();
  const lines = scan(text);
  const edits = docCaseEdits(doc, lines).map(toEdit);
  if (cfg().get('formatIndentation')) {
    const unit = options.insertSpaces ? ' '.repeat(options.tabSize) : '\t';
    const levels = indentLevels(lines);
    lines.forEach((line, ln) => {
      if (line.raw) return;
      const lead = /^[ \t]*/.exec(line.text)[0];
      const trimmed = line.text.replace(/[ \t]+$/, '');
      if (levels[ln] !== null && line.tokens.length > 0) {
        const want = unit.repeat(levels[ln]);
        if (lead !== want) edits.push(vscode.TextEdit.replace(new vscode.Range(ln, 0, ln, lead.length), want));
      }
      if (trimmed.length !== line.text.length && !line.inComment) {
        edits.push(vscode.TextEdit.delete(new vscode.Range(ln, trimmed.length, ln, line.text.length)));
      }
    });
  }
  return edits;
}

const formatter = {
  provideDocumentFormattingEdits: (doc, options) => formatEdits(doc, options),
  provideDocumentRangeFormattingEdits: (doc, range, options) => {
    return formatEdits(doc, options).filter((e) => range.intersection(e.range) !== undefined);
  },
};

/** After Enter: indent the new line for the block it is in, and re-level the line just finished. */
const onTypeFormatter = {
  provideOnTypeFormattingEdits(doc, pos, ch, options) {
    if (!cfg().get('formatIndentation') || pos.line === 0) return [];
    const src = doc.getText().split(/\r?\n/);
    src[pos.line] = 'x'; // a placeholder so the empty line gets a level
    const lines = scan(src.join('\n'));
    const levels = indentLevels(lines);
    const unit = options.insertSpaces ? ' '.repeat(options.tabSize) : '\t';
    const out = [];
    for (const ln of [pos.line - 1, pos.line]) {
      if (levels[ln] === null || lines[ln].raw) continue;
      const cur = doc.lineAt(ln).text;
      const lead = /^[ \t]*/.exec(cur)[0];
      const want = unit.repeat(levels[ln]);
      if (lead !== want && (ln === pos.line || cur.trim().length > 0)) out.push(vscode.TextEdit.replace(new vscode.Range(ln, 0, ln, lead.length), want));
    }
    return out;
  },
};

// --- symbols and libraries ---------------------------------------------------------------

const KIND = {
  module: vscode.SymbolKind.Module,
  program: vscode.SymbolKind.Module,
  sub: vscode.SymbolKind.Method,
  proc: vscode.SymbolKind.Method,
  function: vscode.SymbolKind.Function,
  interrupt: vscode.SymbolKind.Event,
  event: vscode.SymbolKind.Event,
  structure: vscode.SymbolKind.Struct,
  type: vscode.SymbolKind.Class,
  const: vscode.SymbolKind.Constant,
  dim: vscode.SymbolKind.Variable,
  symbol: vscode.SymbolKind.Constant,
};

const fileCache = new Map(); // path -> { mtime, syms, text }
function indexFile(file) {
  try {
    const st = fs.statSync(file);
    const hit = fileCache.get(file);
    if (hit && hit.mtime === st.mtimeMs) return hit;
    const text = fs.readFileSync(file, 'utf8');
    const rec = { mtime: st.mtimeMs, syms: parseSymbols(text), text };
    fileCache.set(file, rec);
    return rec;
  } catch {
    return null;
  }
}

/** Library folders: the nearest `lib` above the file, plus a `lib` in each workspace folder. */
function libDirs(file) {
  const dirs = [];
  for (let d = path.dirname(file); ; d = path.dirname(d)) {
    const c = path.join(d, 'lib');
    if (fs.existsSync(c) && fs.statSync(c).isDirectory()) {
      dirs.push(c);
      break;
    }
    if (path.dirname(d) === d) break;
  }
  for (const f of vscode.workspace.workspaceFolders || []) {
    const c = path.join(f.uri.fsPath, 'lib');
    if (!dirs.includes(c) && fs.existsSync(c)) dirs.push(c);
  }
  return dirs;
}

function libFiles(file) {
  const out = [];
  for (const d of libDirs(file)) {
    try {
      for (const f of fs.readdirSync(d)) if (/\.bas$/i.test(f)) out.push(path.join(d, f));
    } catch {
      /* unreadable folder */
    }
  }
  return out;
}

/** Files whose public symbols are visible from `doc`: itself, its includes, then every library. */
function visibleFiles(doc) {
  const files = [];
  const libs = libFiles(doc.uri.fsPath);
  const byName = new Map(libs.map((f) => [path.basename(f, path.extname(f)).toLowerCase(), f]));
  for (const inc of parseIncludes(doc.getText())) {
    const f = byName.get(inc.name.toLowerCase()) || path.join(path.dirname(doc.uri.fsPath), inc.name + '.bas');
    if (fs.existsSync(f)) files.push(f);
  }
  return { included: files, all: libs };
}

function symbolsFor(doc) {
  const own = parseSymbols(doc.getText()).map((s) => ({ ...s, file: doc.uri.fsPath, own: true }));
  const { included, all } = visibleFiles(doc);
  const seen = new Set(included);
  const ext = [];
  for (const f of [...included, ...all.filter((x) => !seen.has(x))]) {
    const rec = indexFile(f);
    if (!rec) continue;
    const mod = rec.syms.find((s) => s.kind === 'module');
    for (const s of rec.syms) {
      if (s.vis === 'public' && !s.local) ext.push({ ...s, file: f, module: mod && mod.name, included: seen.has(f) });
    }
  }
  return { own, ext };
}

const outline = {
  provideDocumentSymbols(doc) {
    const syms = parseSymbols(doc.getText());
    const out = [];
    for (const s of syms) {
      if (s.local) continue;
      const range = new vscode.Range(s.line, 0, s.endLine, doc.lineAt(Math.min(s.endLine, doc.lineCount - 1)).text.length);
      const sel = new vscode.Range(s.line, s.col, s.line, s.col + s.name.length);
      out.push(new vscode.DocumentSymbol(s.name, s.returns ? `As ${s.returns}` : s.kind, KIND[s.kind], range, sel));
    }
    return out;
  },
};

function wordAt(doc, pos) {
  const r = doc.getWordRangeAtPosition(pos, /[A-Za-z_][A-Za-z0-9_]*/);
  return r ? { range: r, word: doc.getText(r) } : null;
}

function resolve(doc, name, line) {
  const { own, ext } = symbolsFor(doc);
  const low = name.toLowerCase();
  const sameName = (s) => s.name.toLowerCase() === low;
  // A local declared in the routine that contains `line` wins over a global.
  const inRoutine = own.filter((s) => ['sub', 'function', 'proc', 'interrupt', 'event'].includes(s.kind) && s.line <= line && line <= s.endLine).pop();
  if (inRoutine) {
    const loc = own.find((s) => s.local && sameName(s) && s.line > inRoutine.line && s.line <= inRoutine.endLine);
    if (loc) return loc;
  }
  return own.find((s) => !s.local && sameName(s)) || ext.find((s) => sameName(s) && s.included) || ext.find(sameName) || null;
}

const toLocation = (s) => new vscode.Location(vscode.Uri.file(s.file), new vscode.Position(s.line, s.col));

const definition = {
  provideDefinition(doc, pos) {
    const w = wordAt(doc, pos);
    if (!w) return null;
    const s = resolve(doc, w.word, pos.line);
    return s ? toLocation(s) : null;
  },
};

const hover = {
  provideHover(doc, pos) {
    const w = wordAt(doc, pos);
    if (!w) return null;
    // Not a member access: `x.Word` would be a field, not the keyword.
    const before = w.range.start.character > 0 ? doc.getText(new vscode.Range(pos.line, w.range.start.character - 1, pos.line, w.range.start.character)) : '';
    const canon = before === '.' ? undefined : KEYWORDS.get(w.word.toLowerCase());
    const s = canon ? null : resolve(doc, w.word, pos.line);
    const md = new vscode.MarkdownString();
    if (canon) {
      md.appendCodeblock(canon, LANG);
      if (DOCS[canon]) md.appendMarkdown(DOCS[canon]);
    } else if (s) {
      md.appendCodeblock(s.signature || `${s.kind} ${s.name}`, LANG);
      if (s.doc) md.appendMarkdown(s.doc.replace(/\n/g, '  \n'));
      if (!s.own) md.appendMarkdown(`\n\n*${s.module || path.basename(s.file)}*`);
    } else return null;
    return new vscode.Hover(md, w.range);
  },
};

const CK = vscode.CompletionItemKind;
const completion = {
  provideCompletionItems(doc, pos) {
    const prefix = doc.lineAt(pos.line).text.slice(0, pos.character);
    if (/'|\/\/|"[^"]*$/.test(prefix)) return []; // comment or string
    const items = [];
    for (const k of CANONICAL.concat(ALIASES)) {
      const it = new vscode.CompletionItem(k, TYPES.has(k) ? CK.TypeParameter : CK.Keyword);
      it.documentation = DOCS[k] && new vscode.MarkdownString(DOCS[k]);
      it.sortText = '2' + k;
      items.push(it);
    }
    const { own, ext } = symbolsFor(doc);
    const seen = new Set();
    for (const s of [...own.filter((x) => !x.local || (x.line <= pos.line)), ...ext]) {
      const key = s.kind + s.name.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      const kind = { sub: CK.Method, proc: CK.Method, function: CK.Function, interrupt: CK.Event, event: CK.Event, structure: CK.Struct, type: CK.Class, const: CK.Constant, symbol: CK.Constant, dim: CK.Variable, module: CK.Module }[s.kind] || CK.Text;
      const it = new vscode.CompletionItem(s.name, kind);
      it.detail = s.signature || s.kind;
      it.documentation = s.doc ? new vscode.MarkdownString(s.doc) : undefined;
      it.sortText = (s.own ? '0' : '1') + s.name;
      if (!s.own && !s.included) it.detail += `  (Include "${s.module || path.basename(s.file, '.bas')}")`;
      items.push(it);
    }
    return items;
  },
};

const signatureHelp = {
  provideSignatureHelp(doc, pos) {
    const text = doc.lineAt(pos.line).text.slice(0, pos.character);
    let depth = 0;
    let commas = 0;
    let open = -1;
    for (let i = text.length - 1; i >= 0; i -= 1) {
      const c = text[i];
      if (c === ')') depth += 1;
      else if (c === '(') {
        if (depth === 0) {
          open = i;
          break;
        }
        depth -= 1;
      } else if (c === ',' && depth === 0) commas += 1;
    }
    if (open < 0) return null;
    const m = /([A-Za-z_][A-Za-z0-9_]*)\s*$/.exec(text.slice(0, open));
    if (!m) return null;
    const s = resolve(doc, m[1], pos.line);
    if (!s || !['sub', 'function', 'proc'].includes(s.kind)) return null;
    const sig = new vscode.SignatureInformation(s.signature, s.doc ? new vscode.MarkdownString(s.doc) : undefined);
    sig.parameters = (s.params || '').split(',').map((p) => p.trim()).filter(Boolean).map((p) => new vscode.ParameterInformation(p));
    const help = new vscode.SignatureHelp();
    help.signatures = [sig];
    help.activeSignature = 0;
    help.activeParameter = Math.min(commas, Math.max(0, sig.parameters.length - 1));
    return help;
  },
};

// --- compiler: diagnostics, build, tasks --------------------------------------------------

const diagnostics = vscode.languages.createDiagnosticCollection('basicc');
const output = vscode.window.createOutputChannel('PIC BASIC');
const RE_DIAG = /^(.+?):(\d+):(\d+): (error|warning)\[([^\]]+)\]: (.*)$/;

function compilerArgs(extra) {
  return [...extra, ...cfg().get('compilerArgs', [])];
}

/** Runs `basicc --check` on `file` (the document itself, or a temporary copy of it) and publishes the results. */
function runCheck(doc, file, done) {
  const cwd = path.dirname(doc.uri.fsPath);
  const exe = cfg().get('compilerPath') || 'basicc';
  cp.execFile(exe, compilerArgs(['--check', file]), { cwd, timeout: 30000 }, (err, stdout, stderr) => {
    if (done) done();
    if (err && err.code === 'ENOENT') {
      diagnostics.delete(doc.uri);
      if (!runCheck.warned) {
        runCheck.warned = true;
        vscode.window.showWarningMessage(`PIC BASIC: cannot run "${exe}". Set picbasic.compilerPath.`);
      }
      return;
    }
    const byFile = new Map();
    for (const raw of (stdout + '\n' + stderr).split(/\r?\n/)) {
      const m = RE_DIAG.exec(raw);
      if (!m) continue;
      let f = path.resolve(cwd, m[1]);
      if (f === file) f = doc.uri.fsPath;
      const ln = Math.max(0, +m[2] - 1);
      const col = Math.max(0, +m[3] - 1);
      const lineText = f === doc.uri.fsPath ? (ln < doc.lineCount ? doc.lineAt(ln).text : '') : '';
      const w = /^[A-Za-z0-9_$%#]+/.exec(lineText.slice(col));
      const d = new vscode.Diagnostic(new vscode.Range(ln, col, ln, col + (w ? w[0].length : Math.max(1, lineText.length - col))), m[6], m[4] === 'error' ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning);
      d.code = m[5];
      d.source = 'basicc';
      if (!byFile.has(f)) byFile.set(f, []);
      byFile.get(f).push(d);
    }
    diagnostics.clear();
    for (const [f, ds] of byFile) diagnostics.set(vscode.Uri.file(f), ds);
    if (!byFile.has(doc.uri.fsPath)) diagnostics.set(doc.uri, []);
  });
}

const timers = new Map();
function check(doc, typing) {
  if (doc.languageId !== LANG || doc.uri.scheme !== 'file') return;
  const mode = cfg().get('diagnostics');
  if (mode === 'off') return;
  // A library module has no Device, so checking it alone reports every register as undeclared.
  if (parseSymbols(doc.getText()).some((x) => x.kind === 'module')) {
    diagnostics.delete(doc.uri);
    return;
  }
  if (!typing) return runCheck(doc, doc.uri.fsPath);
  if (mode !== 'onType') return;
  clearTimeout(timers.get(doc.uri.fsPath));
  timers.set(
    doc.uri.fsPath,
    setTimeout(() => {
      // A temporary copy beside the file keeps relative Includes working.
      const tmp = path.join(path.dirname(doc.uri.fsPath), `.${path.basename(doc.uri.fsPath, '.bas')}.picbasic-tmp.bas`);
      try {
        fs.writeFileSync(tmp, doc.getText());
      } catch {
        return;
      }
      runCheck(doc, tmp, () => fs.rm(tmp, { force: true }, () => {}));
    }, 700)
  );
}

function taskFor(file, mode) {
  const exe = cfg().get('compilerPath') || 'basicc';
  const args = compilerArgs(mode === 'check' ? ['--check'] : mode === 'report' ? ['--report'] : []);
  const exec = new vscode.ShellExecution(exe, [...args, { value: file, quoting: vscode.ShellQuoting.Strong }], { cwd: path.dirname(file) });
  const t = new vscode.Task({ type: 'picbasic', file, mode }, vscode.TaskScope.Workspace, `${mode === 'check' ? 'Check' : mode === 'report' ? 'Report' : 'Build'} ${path.basename(file)}`, 'picbasic', exec, '$basicc');
  t.group = mode === 'build' ? vscode.TaskGroup.Build : undefined;
  return t;
}

function activeBas() {
  const ed = vscode.window.activeTextEditor;
  if (!ed || ed.document.languageId !== LANG) {
    vscode.window.showWarningMessage('PIC BASIC: open a .bas file first.');
    return null;
  }
  return ed.document.save().then(() => ed.document.uri.fsPath);
}

function activate(ctx) {
  const sel = { language: LANG };
  const reg = (d) => ctx.subscriptions.push(d);
  reg(diagnostics);
  reg(output);
  reg(vscode.workspace.onDidChangeTextDocument((ev) => {
    onTyped(ev);
    if (cfg().get('diagnostics') === 'onType') check(ev.document, true);
  }));
  reg(vscode.workspace.onWillSaveTextDocument((ev) => {
    if (ev.document.languageId === LANG && cfg().get('fixKeywordCaseOnSave')) ev.waitUntil(Promise.resolve(allCaseEdits(ev.document)));
  }));
  reg(vscode.workspace.onDidSaveTextDocument((d) => check(d, false)));
  reg(vscode.workspace.onDidOpenTextDocument((d) => check(d, false)));
  reg(vscode.workspace.onDidCloseTextDocument((d) => diagnostics.delete(d.uri)));
  vscode.workspace.textDocuments.forEach((d) => check(d, false));

  reg(vscode.languages.registerDocumentFormattingEditProvider(sel, formatter));
  reg(vscode.languages.registerDocumentRangeFormattingEditProvider(sel, formatter));
  reg(vscode.languages.registerOnTypeFormattingEditProvider(sel, onTypeFormatter, '\n'));
  reg(vscode.languages.registerDocumentSymbolProvider(sel, outline));
  reg(vscode.languages.registerDefinitionProvider(sel, definition));
  reg(vscode.languages.registerHoverProvider(sel, hover));
  reg(vscode.languages.registerCompletionItemProvider(sel, completion));
  reg(vscode.languages.registerSignatureHelpProvider(sel, signatureHelp, '(', ','));

  reg(vscode.commands.registerCommand('picbasic.fixKeywordCase', () => {
    const ed = vscode.window.activeTextEditor;
    if (!ed || ed.document.languageId !== LANG) return;
    const edits = docCaseEdits(ed.document);
    applying = true;
    ed.edit((b) => edits.forEach((e) => b.replace(toRange(e), e.text))).then(() => {
      applying = false;
      vscode.window.setStatusBarMessage(`PIC BASIC: ${edits.length} name(s) corrected`, 3000);
    });
  }));
  for (const mode of ['check', 'build', 'report']) {
    reg(vscode.commands.registerCommand(`picbasic.${mode}`, async () => {
      const file = await activeBas();
      if (file) vscode.tasks.executeTask(taskFor(file, mode));
    }));
  }
  reg(vscode.tasks.registerTaskProvider('picbasic', {
    provideTasks: () => {
      const ed = vscode.window.activeTextEditor;
      return ed && ed.document.languageId === LANG ? [taskFor(ed.document.uri.fsPath, 'build'), taskFor(ed.document.uri.fsPath, 'check')] : [];
    },
    resolveTask: (t) => (t.definition.file ? taskFor(t.definition.file, t.definition.mode || 'build') : undefined),
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
