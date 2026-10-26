'use strict';
// Project files, device catalog and Microchip tool names (no VS Code dependency, so `npm test` covers it).
const fs = require('fs');
const path = require('path');

const SETTINGS = 'picbasic.json';

/** Every device description in `dirs`: `{ name: '18F27Q10', family, pack, packVersion }`, sorted, first directory wins. */
function listDevices(dirs) {
  const seen = new Map();
  for (const dir of dirs) {
    let files;
    try {
      files = fs.readdirSync(dir);
    } catch {
      continue;
    }
    for (const f of files) {
      if (!/\.toml$/.test(f) || /\.expect\.toml$/.test(f)) continue;
      const stem = f.slice(0, -5).toUpperCase();
      if (seen.has(stem)) continue;
      const text = fs.readFileSync(path.join(dir, f), 'utf8');
      const field = (k) => new RegExp(`^${k}\\s*=\\s*"([^"]*)"`, 'm').exec(text)?.[1] || '';
      seen.set(stem, { name: stem, family: field('family'), pack: field('pack'), packVersion: field('pack_version') });
    }
  }
  return [...seen.values()].sort((a, b) => a.name.localeCompare(b.name, 'en', { numeric: true }));
}

/** `18F27Q10` or `pic18f27q10` to the `PIC18F27Q10` the Microchip debugger expects. */
function mplabDevice(device) {
  const d = String(device || '').trim().toUpperCase();
  return !d ? '' : d.startsWith('PIC') ? d : `PIC${d}`;
}

function basilDevice(device) {
  return String(device || '').trim().replace(/^PIC/i, '').toUpperCase();
}

const TOOL_ALIASES = {
  pk4: 'PICkit 4', pickit4: 'PICkit 4', 'pickit 4': 'PICkit 4',
  pk5: 'PICkit 5', pickit5: 'PICkit 5', 'pickit 5': 'PICkit 5',
  icd4: 'ICD 4', 'icd 4': 'ICD 4', icd5: 'ICD 5', 'icd 5': 'ICD 5',
  snap: 'Snap', simulator: 'Simulator', sim: 'Simulator',
};
const toolName = (t) => TOOL_ALIASES[String(t || '').trim().toLowerCase()] || String(t || '').trim();

const FALLBACK_TOOLS = ['Simulator', 'PICkit Basic', 'PICkit 5', 'PICkit 4', 'ICD 5', 'ICD 4', 'Snap'];

/** Programmer/debugger names in whatever shape the MPLAB extension lists them (strings, objects, nested arrays). */
function parseTools(value) {
  const out = [];
  const find = (text) => {
    const n = String(text || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ');
    const hit = [
      [/\bsimulator\b/, 'Simulator'], [/\bpic ?kit basic\b/, 'PICkit Basic'], [/\bpic ?kit 5\b/, 'PICkit 5'],
      [/\bpic ?kit 4\b/, 'PICkit 4'], [/\bicd 5\b/, 'ICD 5'], [/\bicd 4\b/, 'ICD 4'], [/\bsnap\b/, 'Snap'],
    ].find(([re]) => re.test(n));
    return hit ? hit[1] : '';
  };
  const visit = (v) => {
    if (!v) return;
    if (Array.isArray(v)) return v.forEach(visit);
    if (typeof v === 'string') {
      try {
        if (/^\s*[[{]/.test(v)) return visit(JSON.parse(v));
      } catch {
        /* plain text */
      }
      const tool = find(v);
      if (tool) out.push({ tool, description: v });
    } else if (typeof v === 'object') {
      const name = [v.tool, v.toolName, v.name, v.type, v.displayName, v.label].find((x) => typeof x === 'string');
      const tool = find(name || JSON.stringify(v));
      if (!tool) return Object.values(v).forEach(visit);
      const serial = [v.serial, v.serialNumber, v.toolSerial].find((x) => typeof x === 'string');
      out.push({ tool, serial, description: serial ? `Serial ${serial}` : name || tool });
    }
  };
  visit(value);
  return out;
}

function readSettings(dir) {
  try {
    const j = JSON.parse(fs.readFileSync(path.join(dir, SETTINGS), 'utf8'));
    return j && typeof j === 'object' && !Array.isArray(j) ? j : {};
  } catch {
    return {};
  }
}

function writeSettings(dir, update) {
  const next = update(readSettings(dir));
  fs.writeFileSync(path.join(dir, SETTINGS), JSON.stringify(next, null, 2) + '\n');
  return next;
}

/** The MPLAB debug configuration: simulator or hardware, ELF to debug or HEX to program only. */
function launchConfig({ name, device, packName, packVersion, tool = 'Simulator', serial, program, programOnly }) {
  const t = toolName(tool);
  const sim = t === 'Simulator';
  const c = {
    type: 'mplab-core-da',
    request: 'launch',
    name: programOnly ? 'PIC BASIC: Program' : 'PIC BASIC: Debug',
    program: program || `\${workspaceFolder}/dist/${name}.${programOnly ? 'hex' : 'elf'}`,
    device: mplabDevice(device),
    tool: t,
  };
  if (!sim) c.interface = 'ICSP';
  if (serial && !sim) c.serial = serial;
  if (programOnly) c.noDebug = true;
  else {
    c.stopOnEntry = true;
    c.debugAdapterLogFile = '${workspaceFolder}/dap.log';
  }
  if (packName && packVersion) Object.assign(c, { packName, packVendor: 'Microchip', packVersion });
  return c;
}

function launchJson(opts) {
  return { version: '0.2.0', configurations: [launchConfig(opts)] };
}

function tasksJson(source) {
  const task = (label, mode, isDefault) => ({
    label,
    type: 'picbasic',
    file: `\${workspaceFolder}/${source}`,
    mode,
    group: isDefault ? { kind: 'build', isDefault: true } : 'build',
    problemMatcher: '$basil',
  });
  return { version: '2.0.0', tasks: [task('PIC BASIC: Build', 'build', true), task('PIC BASIC: Check', 'check', false)] };
}

function starterSource(device, clockHz) {
  return `Program Main
Device = ${basilDevice(device)}
Clock = ${clockHz}

Do
Loop
`;
}

/** Writes a new project into `dir` (which must be empty or missing). Returns the source path. */
function createProject(dir, { name, device, clockHz, tool = 'Simulator', pack }) {
  if (fs.existsSync(dir) && fs.readdirSync(dir).length) throw new Error(`${dir} already exists and is not empty`);
  fs.mkdirSync(path.join(dir, '.vscode'), { recursive: true });
  fs.mkdirSync(path.join(dir, 'dist'), { recursive: true });
  const source = `${name}.bas`;
  const d = basilDevice(device);
  fs.writeFileSync(path.join(dir, source), starterSource(d, clockHz));
  const settings = { name, device: d, clockHz, source, debug: { tool }, programming: { tool: tool === 'Simulator' ? 'PICkit 4' : tool } };
  fs.writeFileSync(path.join(dir, SETTINGS), JSON.stringify(settings, null, 2) + '\n');
  const o = { name, device: d, tool, packName: pack?.pack, packVersion: pack?.packVersion };
  fs.writeFileSync(path.join(dir, '.vscode', 'launch.json'), JSON.stringify(launchJson(o), null, 2) + '\n');
  fs.writeFileSync(path.join(dir, '.vscode', 'tasks.json'), JSON.stringify(tasksJson(source), null, 2) + '\n');
  fs.writeFileSync(path.join(dir, '.gitignore'), 'dist/\ndap.log\n');
  return path.join(dir, source);
}

/** Copies the build products beside `source` into dist/. Returns the files copied. */
function collectArtifacts(source) {
  const dir = path.dirname(source);
  const stem = path.basename(source, path.extname(source));
  const dist = path.join(dir, 'dist');
  fs.mkdirSync(dist, { recursive: true });
  const copied = [];
  for (const ext of ['hex', 'elf', 'map']) {
    const from = path.join(dir, `${stem}.${ext}`);
    if (!fs.existsSync(from)) continue;
    fs.copyFileSync(from, path.join(dist, `${stem}.${ext}`));
    copied.push(`${stem}.${ext}`);
  }
  return copied;
}

/** Keeps the project's launch.json debug entry in step with the chosen device and tool. */
function updateLaunch(dir, opts) {
  const file = path.join(dir, '.vscode', 'launch.json');
  let json = { version: '0.2.0', configurations: [] };
  try {
    json = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    /* new file */
  }
  const fresh = launchConfig(opts);
  const list = Array.isArray(json.configurations) ? json.configurations : [];
  const i = list.findIndex((c) => c && c.type === 'mplab-core-da' && !c.noDebug);
  if (i >= 0) list[i] = { ...list[i], ...fresh, stopOnEntry: list[i].stopOnEntry ?? fresh.stopOnEntry };
  else list.unshift(fresh);
  if (fresh.serial === undefined && i >= 0) delete list[i].serial;
  if (fresh.interface === undefined && i >= 0) delete list[i].interface;
  json.configurations = list;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(json, null, 2) + '\n');
}

module.exports = { SETTINGS, FALLBACK_TOOLS, listDevices, mplabDevice, basilDevice, toolName, parseTools, readSettings, writeSettings, launchConfig, launchJson, tasksJson, starterSource, createProject, collectArtifacts, updateLaunch };
