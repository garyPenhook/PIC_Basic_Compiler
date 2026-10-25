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

/** `devices` directories above `start`, nearest first (the compiler's own search). */
function devicesAbove(start) {
  const out = [];
  for (let d = start; ; d = path.dirname(d)) {
    out.push(path.join(d, 'devices'));
    if (path.dirname(d) === d) break;
  }
  return out;
}

module.exports = { parseNames, deviceOf, fileFor, loadNames, devicesAbove };
