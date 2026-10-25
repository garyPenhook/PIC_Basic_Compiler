'use strict';
// Canonical spelling of the register and bit names in a device description (../devices/*.toml),
// so `lata = 0` can be corrected to `LATA = 0` the same way reserved words are. Pure: no vscode.

const fs = require('fs');
const path = require('path');

// Tables whose `name = "..."` entries are names a program can use. Config settings are left out:
// their values are spelled by the Config statement, which case correction skips.
const NAME_TABLES = new Set(['sfr', 'sfr.fields', 'sfr.legacy', 'joined']);

/** Map of lower-case name to canonical name from the text of a device description. */
function parseNames(toml) {
  const names = new Map();
  let table = '';
  for (const raw of toml.split('\n')) {
    const line = raw.trim();
    if (line.startsWith('[')) {
      table = line.replace(/^\[+|\]+$/g, '');
      continue;
    }
    if (!NAME_TABLES.has(table)) continue;
    const m = /^name\s*=\s*"([^"]+)"/.exec(line);
    if (m) names.set(m[1].toLowerCase(), m[1]);
  }
  return names;
}

/**
 * Registers, bits and configuration fields of a device description, for hover and completion.
 * regs: lower-case name or alias -> { name, addr, width, aliases, fields: [{ name, pos, width }] }
 * bits: lower-case field name -> [{ name, reg, pos, width }]
 * config: lower-case field name -> { name, reg, pos, width, settings: [{ name, value }] }
 * Also: device, datasheet.
 */
function parseDevice(toml) {
  const info = { device: '', datasheet: '', regs: new Map(), bits: new Map(), config: new Map() };
  let table = '';
  let reg = null; // current [[sfr]] / [[joined]] / [[config]]
  let field = null; // current field of reg
  let setting = null;
  const str = (v) => /^"(.*)"$/.exec(v)?.[1];
  const all = []; // every register record, in file order
  for (const raw of toml.split('\n')) {
    const line = raw.trim();
    if (line.startsWith('[')) {
      table = line.replace(/^\[+|\]+$/g, '');
      if (table === 'sfr' || table === 'joined' || table === 'config') {
        reg = { name: '', addr: 0, width: 8, aliases: [], fields: [], configReg: table === 'config' };
        all.push(reg);
      } else if (table === 'sfr.fields' || table === 'sfr.legacy' || table === 'config.fields') {
        field = { name: '', pos: 0, width: 1, settings: [], legacy: table === 'sfr.legacy' };
        if (reg) reg.fields.push(field);
      } else if (table === 'config.fields.settings') {
        setting = { name: '', value: 0 };
        if (field) field.settings.push(setting);
      }
      continue;
    }
    const m = /^(\w+)\s*=\s*(.*?)\s*(?:#.*)?$/.exec(line);
    if (!m) continue;
    const [, key, val] = m;
    if (table === 'device') {
      if (key === 'name') info.device = str(val) || '';
      if (key === 'datasheet') info.datasheet = str(val) || '';
    } else if (table === 'sfr' || table === 'joined' || table === 'config') {
      if (key === 'name') reg.name = str(val);
      else if (key === 'addr') reg.addr = Number(val);
      else if (key === 'width') reg.width = Number(val);
      else if (key === 'bytes') reg.width = Number(val) * 8;
      else if (key === 'members') reg.members = val.match(/"[^"]+"/g)?.map((x) => x.slice(1, -1));
      else if (key === 'aliases') reg.aliases = val.match(/"[^"]+"/g)?.map((x) => x.slice(1, -1)) || [];
    } else if (table === 'sfr.fields' || table === 'sfr.legacy' || table === 'config.fields') {
      if (key === 'name') field.name = str(val);
      else if (key === 'pos') field.pos = Number(val);
      else if (key === 'width') field.width = Number(val);
    } else if (table === 'config.fields.settings') {
      if (key === 'name') setting.name = str(val);
      else if (key === 'value') setting.value = Number(val);
    }
  }
  // Names are indexed once the whole record is known: pos and width follow name in the file.
  for (const r of all) {
    if (r.configReg) {
      for (const f of r.fields) info.config.set(f.name.toLowerCase(), { ...f, reg: r.name });
      continue;
    }
    for (const n of [r.name, ...r.aliases]) if (!info.regs.has(n.toLowerCase())) info.regs.set(n.toLowerCase(), r);
    for (const f of r.fields) {
      const k = f.name.toLowerCase();
      if (!info.bits.has(k)) info.bits.set(k, []);
      info.bits.get(k).push({ ...f, reg: r.name });
    }
  }
  return info;
}

/** The device named by a `Device = X` statement in scanned lines, or null. */
function deviceOf(lines) {
  for (const line of lines) {
    if (line.raw) continue;
    const toks = line.tokens.filter((t) => t.t !== 'comment');
    for (let i = 0; i + 1 < toks.length; i += 1) {
      if (toks[i].t !== 'word' || toks[i].member || toks[i].text.toLowerCase() !== 'device' || !toks[i].stmtStart) continue;
      const v = toks[i + 1].text === '=' ? toks[i + 2] : toks[i + 1];
      if (v && (v.t === 'number' || v.t === 'word')) return v.text;
    }
  }
  return null;
}

/** File name of a device description: `PIC18F27Q10` and `18F27Q10` both give `18F27Q10.toml`. */
const fileFor = (device) => device.replace(/^pic/i, '').toUpperCase() + '.toml';

const cache = new Map(); // file -> { mtime, names }

/** Names for `device`, looking in each directory of `dirs` in turn; null when none has the file. */
function loadNames(device, dirs) {
  const file = fileFor(device);
  for (const dir of dirs) {
    const p = path.join(dir, file);
    let st;
    try {
      st = fs.statSync(p);
    } catch (e) {
      continue;
    }
    const hit = cache.get(p);
    if (hit && hit.mtime === st.mtimeMs) return hit.names;
    const names = parseNames(fs.readFileSync(p, 'utf8'));
    cache.set(p, { mtime: st.mtimeMs, names });
    return names;
  }
  return null;
}

const infoCache = new Map();

/** Parsed registers and bits for `device`, looking in `dirs` like loadNames; null when not found. */
function loadInfo(device, dirs) {
  const file = fileFor(device);
  for (const dir of dirs) {
    const p = path.join(dir, file);
    let st;
    try {
      st = fs.statSync(p);
    } catch (e) {
      continue;
    }
    const hit = infoCache.get(p);
    if (hit && hit.mtime === st.mtimeMs) return hit.info;
    const info = parseDevice(fs.readFileSync(p, 'utf8'));
    infoCache.set(p, { mtime: st.mtimeMs, info });
    return info;
  }
  return null;
}

/** `devices` directories above `start`, nearest first (the compiler's own search). */
function devicesAbove(start) {
  const out = [];
  for (let d = start; ; d = path.dirname(d)) {
    out.push(path.join(d, 'devices'));
    if (path.dirname(d) === d) break;
  }
  return out;
}

module.exports = { parseDevice, loadInfo, parseNames, deviceOf, fileFor, loadNames, devicesAbove };
