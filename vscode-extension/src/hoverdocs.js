'use strict';
// Markdown for hover and completion documentation. Pure: no vscode, so test/test.js can check it.

const { scan, code, lower } = require('./scanner');

const hex = (n, digits) => '0x' + n.toString(16).toUpperCase().padStart(digits || 1, '0');
const bitsOf = (f) => (f.width === 1 ? `bit ${f.pos}` : `bits ${f.pos + f.width - 1}:${f.pos}`);

/** Documentation of a register (SFR, alias or joined register). */
function regDoc(info, reg) {
  const lines = [`**${reg.name}** — special function register at \`${hex(reg.addr, 3)}\`, ${reg.width} bits`];
  if (reg.members) lines.push(`Joined register of ${reg.members.map((m) => `\`${m}\``).join(', ')} (low byte first).`);
  if (reg.aliases.length) lines.push(`Also known as ${reg.aliases.map((a) => `\`${a}\``).join(', ')}.`);
  const fields = reg.fields.filter((f) => !f.legacy);
  if (fields.length) {
    const show = fields.slice(0, 16).map((f) => `- \`${f.name}\` — ${bitsOf(f)}`);
    if (fields.length > 16) show.push(`- … ${fields.length - 16} more`);
    lines.push('', ...show);
  }
  lines.push('', `Use \`${reg.name}.n\` for a single bit (0 is the least significant).`);
  if (info.datasheet) lines.push('', `*${info.device}, ${info.datasheet}*`);
  return lines.join('\n');
}

/** Documentation of a named bit field; `list` holds every register that has the name. */
function bitDoc(info, list) {
  const out = list.map((b) => {
    const reg = info.regs.get(b.reg.toLowerCase());
    const mask = ((1 << b.width) - 1) << b.pos;
    return `**${b.name}** — ${bitsOf(b)} of \`${b.reg}\`${reg ? ` (\`${hex(reg.addr, 3)}\`)` : ''}, mask \`${hex(mask, 2)}\``;
  });
  if (info.datasheet) out.push(`*${info.device}, ${info.datasheet}*`);
  return out.join('\n\n');
}

/** Documentation of a Config field with every value it accepts. */
function configDoc(info, f) {
  const lines = [`**${f.name}** — configuration field, ${bitsOf(f)} of \`${f.reg}\``, ''];
  lines.push(...f.settings.map((s) => `- \`${s.name}\` = ${s.value}`));
  if (info.datasheet) lines.push('', `*${info.device}, ${info.datasheet}*`);
  return lines.join('\n');
}

/** A setting value such as `HFINTOSC_64MHZ`, with the field it belongs to. */
function settingDoc(info, f, s) {
  return `**${s.name}** — value ${s.value} (\`${hex(s.value << f.pos, 2)}\` in \`${f.reg}\`) for configuration field \`${f.name}\``;
}

/** Decimal, hexadecimal and binary forms of a numeric literal, or null when `text` is not one. */
function numberDoc(text) {
  let n;
  const t = text.replace(/_/g, '');
  if (/^(0x|\$)[0-9a-f]+$/i.test(t)) n = parseInt(t.replace(/^(0x|\$)/i, ''), 16);
  else if (/^(0b|%)[01]+$/i.test(t)) n = parseInt(t.replace(/^(0b|%)/i, ''), 2);
  else if (/^[0-9]+$/.test(t)) n = parseInt(t, 10);
  else return null;
  if (!Number.isSafeInteger(n)) return null;
  const bin = n.toString(2);
  const bytes = Math.max(1, Math.ceil(bin.length / 8));
  return `**${text}** = ${n} = \`${hex(n, bytes * 2)}\` = \`0b${bin.padStart(bytes * 8, '0')}\` (${bytes === 1 ? 'fits a Byte' : `${bytes} bytes`})`;
}

/** Routine parameters as [{ name, mode, type }], from the text between the parentheses. */
function parseParams(params) {
  const out = [];
  let depth = 0;
  let cur = '';
  const parts = [];
  for (const c of params || '') {
    if (c === '(') depth += 1;
    else if (c === ')') depth -= 1;
    if (c === ',' && depth === 0) {
      parts.push(cur);
      cur = '';
    } else cur += c;
  }
  parts.push(cur);
  for (const p of parts) {
    const m = /^\s*(?:(ByRefConst|ByRef|ByVal)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:As\s+(.+?))?\s*$/i.exec(p);
    if (m) out.push({ name: m[2], mode: m[1] || '', type: m[3] || '' });
  }
  return out;
}

const PARAM_MODE = {
  byval: 'passed by value',
  byref: 'passed by reference; the routine may change it',
  byrefconst: 'passed by reference; the routine may not change it',
};

const paramMode = (p) => PARAM_MODE[p.mode.toLowerCase()] || PARAM_MODE.byval;

function paramDoc(routine, p) {
  const mode = paramMode(p);
  return `\`${(p.mode ? p.mode + ' ' : '') + p.name}${p.type ? ' As ' + p.type : ''}\`\n\nParameter of \`${routine.name}\`, ${mode}.`;
}

/** The comment block just under a `Module` line: what the library does. */
function moduleDoc(text) {
  const out = [];
  let seen = false;
  for (const line of scan(text)) {
    if (line.raw || line.inComment) break;
    const toks = code(line);
    if (!seen) {
      if (toks.length && lower(toks[0]) === 'module') seen = true;
      continue;
    }
    if (toks.length) break;
    const c = line.tokens.find((t) => t.t === 'comment');
    if (!c) break;
    out.push(c.text.replace(/^('+|\/\/)\s?/, ''));
  }
  return out.join('\n');
}

module.exports = { hex, regDoc, bitDoc, configDoc, settingDoc, numberDoc, parseParams, paramMode, paramDoc, moduleDoc };
