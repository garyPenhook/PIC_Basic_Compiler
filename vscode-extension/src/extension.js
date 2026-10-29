'use strict';
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const { scan, caseEdits, indentLevels } = require('./scanner');
const { parseSymbols, parseIncludes } = require('./symbols');
const { CANONICAL, ALIASES, CONTEXTUAL, KEYWORDS, TYPES, DOCS } = require('./keywords');
const { deviceOf, loadNames, loadInfo, devicesAbove } = require('./devicenames');
const docs = require('./hoverdocs');
const proj = require('./project');

const LANG = 'picbasic';
const cfg = () => vscode.workspace.getConfiguration('picbasic');

// --- keyword case ------------------------------------------------------------------------

const toRange = (e) => new vscode.Range(e.line, e.s, e.line, e.e);
const toEdit = (e) => vscode.TextEdit.replace(toRange(e), e.text);

/** Directories that may hold the device descriptions for `doc`, best first. */
function deviceDirs(doc) {
  const dirs = [];
  const extra = cfg().get('devicesPath');
  if (extra) dirs.push(extra);
  if (doc.uri.scheme === 'file') dirs.push(...devicesAbove(path.dirname(doc.uri.fsPath)));
  for (const f of vscode.workspace.workspaceFolders || []) dirs.push(path.join(f.uri.fsPath, 'devices'));
  // A development build lives in <repo>/target/<profile>/basil, next to <repo>/devices.
  const exe = cfg().get('compilerPath');
  if (exe && path.isAbsolute(exe)) dirs.push(...devicesAbove(path.dirname(exe)));
  return dirs;
}

/** Register and bit names of the document's `Device`, or undefined when off or not found. */
function deviceNames(doc, lines) {
  if (!cfg().get('autoCorrectDeviceNames')) return undefined;
  const device = deviceOf(lines);
  if (!device) return undefined;
  return loadNames(device, deviceDirs(doc)) || undefined;
}

/** Registers, bits and configuration fields of the document's `Device` (for hover and completion). */
function deviceInfo(doc) {
  const device = deviceOf(scan(doc.getText()));
  return device ? loadInfo(device, deviceDirs(doc)) : null;
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

const md = (text, lang) => {
  const m = new vscode.MarkdownString();
  if (lang) m.appendCodeblock(text, LANG);
  else m.appendMarkdown(text);
  return m;
};

/** The library file whose module is called `name` and is visible from `doc`, with its parse. */
function moduleNamed(doc, name) {
  const low = name.toLowerCase();
  const { included, all } = visibleFiles(doc);
  for (const f of [...included, ...all]) {
    const rec = indexFile(f);
    const mod = rec && rec.syms.find((x) => x.kind === 'module' && x.name.toLowerCase() === low);
    if (mod) return { file: f, rec, mod };
  }
  return null;
}

function moduleHover(doc, name) {
  const m = moduleNamed(doc, name);
  if (!m) return null;
  const lines = [`**Module ${m.mod.name}**`, docs.moduleDoc(m.rec.text)];
  const pub = m.rec.syms.filter((x) => x.vis === 'public' && !x.local);
  if (pub.length) lines.push(pub.map((x) => '- `' + (x.signature || x.name) + '`').join('\n'));
  lines.push(`*${path.basename(m.file)}*`);
  return md(lines.filter(Boolean).join('\n\n'));
}

/** Symbol hover: signature, parameter list, doc comment, where it is defined. */
function symbolHover(s) {
  const m = md(s.signature || `${s.kind} ${s.name}`, true);
  if (['sub', 'function', 'proc', 'interrupt', 'event'].includes(s.kind)) {
    const ps = docs.parseParams(s.params);
    const bits = [];
    if (ps.length) bits.push('**Parameters**\n' + ps.map((p) => '- `' + p.name + (p.type ? ' As ' + p.type : '') + '` — ' + docs.paramMode(p)).join('\n'));
    if (s.returns) bits.push(`**Returns** \`${s.returns}\``);
    if (bits.length) m.appendMarkdown(bits.join('\n\n') + '\n\n');
  }
  if (s.doc) m.appendMarkdown(s.doc.replace(/\n/g, '  \n'));
  const where = s.own ? `line ${s.line + 1}` : `${s.module || path.basename(s.file)}, ${path.basename(s.file)}:${s.line + 1}`;
  m.appendMarkdown(`\n\n*${s.vis === 'public' ? 'public ' : ''}${s.kind}, ${where}*`);
  return m;
}

/** The sub/function/proc/interrupt/event of `own` that contains `line`. */
function routineAt(doc, line) {
  return parseSymbols(doc.getText()).filter((x) => ['sub', 'function', 'proc', 'interrupt', 'event'].includes(x.kind) && x.line <= line && line <= x.endLine).pop();
}

const hover = {
  provideHover(doc, pos) {
    const lineText = doc.lineAt(pos.line).text;
    const prefix = lineText.slice(0, pos.character);
    if (/'|\/\//.test(prefix.replace(/"[^"]*"/g, ''))) return null; // inside a comment

    // Include "name" -> the module's description.
    const inc = /^\s*Include\s+"([^"]*)"/i.exec(lineText);
    if (inc && pos.character > lineText.indexOf('"') && pos.character <= lineText.indexOf('"') + inc[1].length + 1) {
      const r = new vscode.Range(pos.line, lineText.indexOf('"') + 1, pos.line, lineText.indexOf('"') + 1 + inc[1].length);
      const h = moduleHover(doc, inc[1]);
      return h ? new vscode.Hover(h, r) : new vscode.Hover(md(`No library module \`${inc[1]}\` found in a \`lib\` folder or next to this file.`), r);
    }

    // Numeric literal: all radixes.
    const numR = doc.getWordRangeAtPosition(pos, /(0[xX][0-9A-Fa-f_]+|0[bB][01_]+|\$[0-9A-Fa-f]+|%[01]+|\b[0-9][0-9_]*\b)/);
    if (numR) {
      const t = doc.getText(numR);
      const nd = docs.numberDoc(t);
      if (nd && !/[A-Za-z_]/.test(lineText[numR.start.character - 1] || '')) return new vscode.Hover(md(nd), numR);
    }

    const w = wordAt(doc, pos);
    if (!w) return null;
    const startCh = w.range.start.character;
    const before = startCh > 0 ? lineText[startCh - 1] : '';
    const qualM = before === '.' ? /([A-Za-z_][A-Za-z0-9_]*)\.$/.exec(lineText.slice(0, startCh)) : null;
    const qualifier = qualM && qualM[1];
    const low = w.word.toLowerCase();
    const info = deviceInfo(doc);
    const out = [];

    // Config FIELD = SETTING
    if (/^\s*Config\b/i.test(lineText) && info) {
      const eq = lineText.slice(0, startCh).lastIndexOf('=');
      const comma = lineText.slice(0, startCh).lastIndexOf(',');
      if (eq > comma) {
        const fm = /([A-Za-z_][A-Za-z0-9_]*)\s*=\s*$/.exec(lineText.slice(0, startCh));
        const f = fm && info.config.get(fm[1].toLowerCase());
        const st = f && f.settings.find((x) => x.name.toLowerCase() === low);
        if (st) return new vscode.Hover(md(docs.settingDoc(info, f, st)), w.range);
      } else if (info.config.has(low)) return new vscode.Hover(md(docs.configDoc(info, info.config.get(low))), w.range);
    }

    // Module.Member and the module name itself.
    if (qualifier) {
      const m = moduleNamed(doc, qualifier);
      const mem = m && m.rec.syms.find((x) => x.vis === 'public' && !x.local && x.name.toLowerCase() === low);
      if (mem) return new vscode.Hover(symbolHover({ ...mem, file: m.file, module: m.mod.name }), w.range);
    } else if (!KEYWORDS.has(low) && lineText[w.range.end.character] === '.') {
      const mh = moduleHover(doc, w.word);
      if (mh && !resolve(doc, w.word, pos.line)) return new vscode.Hover(mh, w.range);
    }

    // Keywords and intrinsics.
    const canon = qualifier ? undefined : KEYWORDS.get(low);
    if (canon) {
      const m = md(canon, true);
      if (DOCS[canon]) m.appendMarkdown(DOCS[canon]);
      return new vscode.Hover(m, w.range);
    }

    // The program's own declarations, then library ones.
    if (!qualifier) {
      const rt = routineAt(doc, pos.line);
      const p = rt && docs.parseParams(rt.params).find((x) => x.name.toLowerCase() === low);
      const s = resolve(doc, w.word, pos.line);
      if (s && s.local && rt && s.line >= rt.line && s.line <= rt.endLine) return new vscode.Hover(symbolHover({ ...s, kind: 'local ' + s.kind, own: true }), w.range);
      if (p) return new vscode.Hover(md(docs.paramDoc(rt, p)), w.range);
      if (s) {
        const h = symbolHover(s);
        // `Dim led As PORTB.0`: also describe the register behind the alias.
        const am = info && s.signature && /\bAs\s+([A-Za-z_][A-Za-z0-9_]*)(?:\.(\d+))?\s*$/i.exec(s.signature);
        const ar = am && info.regs.get(am[1].toLowerCase());
        if (ar) h.appendMarkdown(`\n\n---\n\n${am[2] !== undefined ? `Alias for bit ${am[2]} of ` : 'Alias for '}**${ar.name}** at \`${docs.hex(ar.addr, 3)}\`.`);
        return new vscode.Hover(h, w.range);
      }
    }

    // Device registers and bits (`PORTB`, `RB0`, `PORTB.3`).
    if (info) {
      const reg = !qualifier && info.regs.get(low);
      if (reg) out.push(docs.regDoc(info, reg));
      const bit = info.bits.get(low);
      if (bit && !reg) out.push(docs.bitDoc(info, qualifier ? bit.filter((b) => info.regs.get(qualifier.toLowerCase()) === info.regs.get(b.reg.toLowerCase())) : bit));
    }
    if (out.length && out[0]) return new vscode.Hover(md(out.join('\n\n')), w.range);
    return null;
  },
};

const CK = vscode.CompletionItemKind;

function memberItem(s) {
  const kind = { sub: CK.Method, proc: CK.Method, function: CK.Function, interrupt: CK.Event, event: CK.Event, structure: CK.Struct, type: CK.Class, const: CK.Constant, symbol: CK.Constant, dim: CK.Variable }[s.kind] || CK.Text;
  const it = new vscode.CompletionItem(s.name, kind);
  it.detail = s.signature || s.kind;
  it.documentation = symbolHover(s);
  return it;
}

function bitItem(info, f, regName) {
  const it = new vscode.CompletionItem(f.name, CK.EnumMember);
  it.detail = `${regName} ${f.width === 1 ? 'bit ' + f.pos : 'bits ' + (f.pos + f.width - 1) + ':' + f.pos}`;
  return it;
}

const completion = {
  provideCompletionItems(doc, pos) {
    const prefix = doc.lineAt(pos.line).text.slice(0, pos.character);
    if (/'|\/\/|"[^"]*$/.test(prefix)) return []; // comment or string
    const info = deviceInfo(doc);

    // After `Module.` offer only that module's public members.
    const qm = /([A-Za-z_][A-Za-z0-9_]*)\.[A-Za-z0-9_]*$/.exec(prefix);
    if (qm) {
      const m = moduleNamed(doc, qm[1]);
      if (m) {
        return m.rec.syms.filter((x) => x.vis === 'public' && !x.local).map((x) => memberItem({ ...x, file: m.file, module: m.mod.name, included: true }));
      }
      const reg = info && info.regs.get(qm[1].toLowerCase());
      if (reg) return reg.fields.filter((f) => !f.legacy).map((f) => bitItem(info, f, reg.name));
    }

    // Config FIELD = SETTING: the fields, or the values of the field just before `=`.
    if (/^\s*Config\b/i.test(prefix) && info) {
      const fm = /([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[A-Za-z0-9_]*$/.exec(prefix);
      const f = fm && info.config.get(fm[1].toLowerCase());
      if (f) {
        return f.settings.map((x) => {
          const it = new vscode.CompletionItem(x.name, CK.EnumMember);
          it.detail = `${f.name} = ${x.value}`;
          it.documentation = md(docs.settingDoc(info, f, x));
          return it;
        });
      }
      return [...info.config.values()].map((f) => {
        const it = new vscode.CompletionItem(f.name, CK.Property);
        it.detail = `${f.reg}, ${f.settings.length} values`;
        it.documentation = md(docs.configDoc(info, f));
        return it;
      });
    }

    const items = [];
    if (info) {
      for (const r of new Set(info.regs.values())) {
        const it = new vscode.CompletionItem(r.name, CK.Field);
        it.detail = `register ${docs.hex(r.addr, 3)}, ${r.width} bits`;
        it.documentation = md(docs.regDoc(info, r));
        it.sortText = '3' + r.name;
        items.push(it);
      }
      for (const list of info.bits.values()) {
        const b = list[0];
        const it = new vscode.CompletionItem(b.name, CK.EnumMember);
        it.detail = `${b.reg} ${b.width === 1 ? 'bit ' + b.pos : 'bits ' + (b.pos + b.width - 1) + ':' + b.pos}`;
        it.documentation = md(docs.bitDoc(info, list));
        it.sortText = '4' + b.name;
        items.push(it);
      }
    }
    for (const k of CANONICAL.concat(ALIASES, CONTEXTUAL)) {
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
      it.documentation = symbolHover(s);
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

const diagnostics = vscode.languages.createDiagnosticCollection('basil');
const output = vscode.window.createOutputChannel('PIC BASIC');
const RE_DIAG = /^(.+?):(\d+):(\d+): (error|warning)\[([^\]]+)\]: (.*)$/;

function compilerArgs(extra) {
  return [...extra, ...cfg().get('compilerArgs', [])];
}

/** Runs `basil --check` on `file` (the document itself, or a temporary copy of it) and publishes the results. */
function runCheck(doc, file, done) {
  const cwd = path.dirname(doc.uri.fsPath);
  const exe = cfg().get('compilerPath') || 'basil';
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
      d.source = 'basil';
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
  const exe = cfg().get('compilerPath') || 'basil';
  const args = compilerArgs(mode === 'check' ? ['--check'] : mode === 'report' ? ['--report'] : mode === 'debug' ? ['-g'] : []);
  const exec = new vscode.ShellExecution(exe, [...args, { value: file, quoting: vscode.ShellQuoting.Strong }], { cwd: path.dirname(file) });
  const t = new vscode.Task({ type: 'picbasic', file, mode }, vscode.TaskScope.Workspace, `${mode === 'check' ? 'Check' : mode === 'report' ? 'Report' : mode === 'debug' ? 'Debug build' : 'Build'} ${path.basename(file)}`, 'picbasic', exec, '$basil');
  t.group = mode === 'build' || mode === 'debug' ? vscode.TaskGroup.Build : undefined;
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


// --- project, programming and debugging -------------------------------------------------------

/** Where the compiler's device descriptions live, for the device catalog. */
function catalogDirs() {
  const dirs = [];
  const extra = cfg().get('devicesPath');
  if (extra) dirs.push(extra);
  for (const f of vscode.workspace.workspaceFolders || []) dirs.push(...devicesAbove(f.uri.fsPath));
  const ed = vscode.window.activeTextEditor;
  if (ed && ed.document.uri.scheme === 'file') dirs.push(...devicesAbove(path.dirname(ed.document.uri.fsPath)));
  const exe = cfg().get('compilerPath');
  if (exe && path.isAbsolute(exe)) dirs.push(...devicesAbove(path.dirname(exe)));
  return dirs;
}

async function pickDevice(current) {
  const devices = proj.listDevices(catalogDirs());
  if (!devices.length) {
    vscode.window.showErrorMessage('PIC BASIC: no device descriptions found. Set picbasic.devicesPath.');
    return undefined;
  }
  const cur = proj.basilDevice(current);
  const pick = await vscode.window.showQuickPick(
    devices.map((d) => ({ label: d.name, description: d.family, detail: d.pack && `${d.pack} ${d.packVersion}`, picked: d.name === cur, device: d })),
    { title: 'Target Device', placeHolder: 'Search the device descriptions' }
  );
  return pick && pick.device;
}

/** The project of the active .bas file: its folder, settings and source. */
function activeProject() {
  const ed = vscode.window.activeTextEditor;
  let file = ed && ed.document.languageId === LANG && ed.document.uri.scheme === 'file' ? ed.document.uri.fsPath : null;
  const root = (vscode.workspace.workspaceFolders || [])[0];
  if (!file && root) {
    const dir = root.uri.fsPath;
    const src = proj.readSettings(dir).source;
    if (src && fs.existsSync(path.join(dir, src))) file = path.join(dir, src);
  }
  if (!file) {
    vscode.window.showErrorMessage('PIC BASIC: open a .bas file or a folder created by New Project.');
    return null;
  }
  const dir = path.dirname(file);
  const settings = proj.readSettings(dir);
  const device = deviceOf(scan(fs.readFileSync(file, 'utf8'))) || settings.device || '';
  return { dir, file, settings, device, name: path.basename(file, '.bas') };
}

function packOf(device) {
  return proj.listDevices(catalogDirs()).find((d) => d.name === proj.basilDevice(device));
}

async function newProject() {
  const parent = await vscode.window.showOpenDialog({ title: 'Parent folder for the new project', canSelectFiles: false, canSelectFolders: true, canSelectMany: false, openLabel: 'Select Folder' });
  if (!parent || !parent[0]) return;
  const name = await vscode.window.showInputBox({
    title: 'Project name',
    prompt: 'Becomes the folder, the .bas file and the output name',
    validateInput: (v) => (/^[A-Za-z_][A-Za-z0-9_]*$/.test(v.trim()) ? undefined : 'Letters, digits and underscores, starting with a letter.'),
  });
  if (!name) return;
  const device = await pickDevice('18F27Q10');
  if (!device) return;
  const clock = await vscode.window.showInputBox({ title: 'Oscillator frequency (Hz)', value: '4000000', validateInput: (v) => (/^\d+$/.test(v.trim()) ? undefined : 'Enter a whole number.') });
  if (!clock) return;
  const dir = path.join(parent[0].fsPath, name.trim());
  let source;
  try {
    source = proj.createProject(dir, { name: name.trim(), device: device.name, clockHz: Number(clock), pack: device });
  } catch (e) {
    vscode.window.showErrorMessage(`PIC BASIC: ${e.message}`);
    return;
  }
  const open = await vscode.window.showInformationMessage(`PIC BASIC: created ${name.trim()}`, 'Open Project');
  if (open) await vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(dir), false);
  else await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(source));
}

async function pickTarget() {
  const p = activeProject();
  if (!p) return;
  const device = await pickDevice(p.device);
  if (!device) return;
  const text = fs.readFileSync(p.file, 'utf8');
  const next = /^(\s*device\s*=\s*)\w+/im.test(text) ? text.replace(/^(\s*device\s*=\s*)\w+/im, `$1${device.name}`) : `Device = ${device.name}\n${text}`;
  if (next !== text) {
    const open = vscode.workspace.textDocuments.find((d) => d.uri.fsPath === p.file);
    if (open) {
      const all = new vscode.Range(0, 0, open.lineCount, 0);
      const we = new vscode.WorkspaceEdit();
      we.replace(open.uri, all, next);
      await vscode.workspace.applyEdit(we);
      await open.save();
    } else fs.writeFileSync(p.file, next);
  }
  proj.writeSettings(p.dir, (j) => ({ ...j, device: device.name }));
  const dbg = proj.readSettings(p.dir).debug || {};
  proj.updateLaunch(p.dir, { name: p.name, device: device.name, tool: dbg.tool, serial: dbg.serial, packName: device.pack, packVersion: device.packVersion });
  vscode.window.showInformationMessage(`PIC BASIC: target ${device.name}`);
}

async function connectedTools() {
  const sets = await Promise.all(['mplab-core-da.listConnectedTools', 'mplab-core-da.listConnectedKits'].map((c) => Promise.resolve(vscode.commands.executeCommand(c)).catch(() => [])));
  return proj.parseTools(sets);
}

async function pickTool() {
  const found = await connectedTools();
  const items = new Map();
  for (const t of found.length ? [{ tool: 'Simulator', description: 'Software simulator' }, ...found] : proj.FALLBACK_TOOLS.map((tool) => ({ tool }))) items.set(`${t.tool}\0${t.serial || ''}`, t);
  const pick = await vscode.window.showQuickPick([...items.values()].map((t) => ({ label: t.tool, description: t.serial ? `Serial ${t.serial}` : t.description, t })), {
    title: 'Programmer / Debugger',
    placeHolder: found.length ? 'Simulator or a connected Microchip tool' : 'No connected tools reported; choose one',
  });
  return pick && pick.t;
}

async function selectTool() {
  const p = activeProject();
  if (!p) return;
  const t = await pickTool();
  if (!t) return;
  const sim = t.tool === 'Simulator';
  proj.writeSettings(p.dir, (j) => {
    const entry = { tool: t.tool, ...(t.serial && !sim ? { serial: t.serial } : {}) };
    // The simulator cannot program a chip, so programming keeps its last hardware tool.
    return { ...j, debug: entry, programming: sim ? j.programming || { tool: 'PICkit 4' } : entry };
  });
  const dev = packOf(p.device);
  proj.updateLaunch(p.dir, { name: p.name, device: p.device, tool: t.tool, serial: t.serial, packName: dev && dev.pack, packVersion: dev && dev.packVersion });
  vscode.window.showInformationMessage(`PIC BASIC: ${t.tool}${t.serial ? ` (${t.serial})` : ''} for ${p.name}`);
}

/** Runs the build task, then copies the hex/elf/map into dist/. Resolves true on success. */
let building = false;
async function buildProject(debug) {
  if (building) {
    vscode.window.showWarningMessage('PIC BASIC: a build is already running.');
    return false;
  }
  const p = activeProject();
  if (!p) return false;
  building = true;
  try {
    return await runBuild(p, debug);
  } finally {
    building = false;
  }
}

async function runBuild(p, debug) {
  const doc = vscode.workspace.textDocuments.find((d) => d.uri.fsPath === p.file);
  if (doc) await doc.save();
  const task = taskFor(p.file, debug ? 'debug' : 'build');
  let sub;
  const ended = new Promise((resolve) => {
    sub = vscode.tasks.onDidEndTaskProcess((e) => {
      if (e.execution.task.definition.file === p.file && e.execution.task.definition.type === 'picbasic') resolve(e.exitCode);
    });
  });
  await vscode.tasks.executeTask(task);
  const code = await ended;
  sub.dispose();
  if (code !== 0) return false;
  const copied = proj.collectArtifacts(p.file);
  const need = debug ? `${p.name}.elf` : `${p.name}.hex`;
  if (!copied.includes(need)) {
    vscode.window.showErrorMessage(`PIC BASIC: the build did not produce ${need}.`);
    return false;
  }
  output.appendLine(`PIC BASIC: dist/ now holds ${copied.join(', ')}`);
  return true;
}

async function programDevice() {
  const p = activeProject();
  if (!p) return;
  if (!(await buildProject(false))) return;
  let prog = p.settings.programming || {};
  if (!prog.tool || prog.tool === 'Simulator') {
    const t = await pickTool();
    if (!t) return;
    prog = { tool: t.tool, serial: t.serial };
  }
  if (prog.tool === 'Simulator') {
    vscode.window.showErrorMessage('PIC BASIC: the simulator cannot program a device. Select PICkit, ICD or Snap.');
    return;
  }
  const dev = packOf(p.device);
  const cfgLaunch = proj.launchConfig({ name: p.name, device: p.device, tool: prog.tool, serial: prog.serial, packName: dev && dev.pack, packVersion: dev && dev.packVersion, program: path.join(p.dir, 'dist', `${p.name}.hex`), programOnly: true });
  await vscode.debug.startDebugging(undefined, cfgLaunch);
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
  reg(vscode.languages.registerCompletionItemProvider(sel, completion, '.'));
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
  reg(vscode.commands.registerCommand('picbasic.newProject', newProject));
  reg(vscode.commands.registerCommand('picbasic.pickDevice', pickTarget));
  reg(vscode.commands.registerCommand('picbasic.selectTool', selectTool));
  reg(vscode.commands.registerCommand('picbasic.buildRelease', () => buildProject(false)));
  reg(vscode.commands.registerCommand('picbasic.buildDebug', () => buildProject(true)));
  reg(vscode.commands.registerCommand('picbasic.program', programDevice));
  reg(vscode.commands.registerCommand('picbasic.showOutput', () => output.show()));
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
