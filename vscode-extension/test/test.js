'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { scan, caseEdits, indentLevels } = require('../src/scanner');
const { parseSymbols, parseIncludes } = require('../src/symbols');
const { CANONICAL, ALIASES, TYPES } = require('../src/keywords');
const { parseNames, deviceOf, loadNames, devicesAbove } = require('../src/devicenames');

function fix(src) {
  const lines = src.split('\n');
  const edits = caseEdits(scan(src)).sort((a, b) => b.line - a.line || b.s - a.s);
  for (const e of edits) lines[e.line] = lines[e.line].slice(0, e.s) + e.text + lines[e.line].slice(e.e);
  return lines.join('\n');
}

// The keyword table matches the compiler's.
const lexer = fs.readFileSync(path.join(__dirname, '../../src/lexer.rs'), 'utf8');
const block = /pub const KEYWORDS: &\[&str\] = &\[([\s\S]*?)\];/.exec(lexer)[1];
const rust = [...block.matchAll(/"(\w+)"/g)].map((m) => m[1]).sort();
assert.deepStrictEqual(CANONICAL.map((k) => k.toLowerCase()).sort(), rust, 'keywords.js differs from src/lexer.rs');

const aliasBlock = /const TYPE_ALIASES[^=]*=\s*&\[([\s\S]*?)\];/.exec(lexer)[1];
assert.deepStrictEqual([...aliasBlock.matchAll(/\("(\w+)",/g)].map((m) => m[1]).sort(), ALIASES.map((k) => k.toLowerCase()).sort(), 'ALIASES differs from TYPE_ALIASES in src/lexer.rs');
assert.ok(ALIASES.every((k) => TYPES.has(k)));
assert.strictEqual(fix('dim a as sbyte, b as sword, c as dword, d as long'), 'Dim a As SByte, b As SWord, c As Dword, d As Long');

// Basic correction.
assert.strictEqual(fix('dim x as byte'), 'Dim x As Byte');
assert.strictEqual(fix('IF a THEN\nendif'), 'If a Then\nEndIf');
assert.strictEqual(fix('end if'), 'End If');
assert.strictEqual(fix('dim a as longword'), 'Dim a As LongWord');
assert.strictEqual(fix('delayms(5)'), 'DelayMs(5)');
assert.strictEqual(fix('goto done'), 'GoTo done');
// Device register and bit names.
const devNames = loadNames('PIC18F27Q10', devicesAbove(__dirname));
assert.ok(devNames && devNames.get("lata") === "LATA" && devNames.get("lata0") === 'LATA0', 'device names load');
assert.strictEqual(deviceOf(scan('Program T\nDevice = 18F27Q10')), '18F27Q10');
assert.strictEqual(deviceOf(scan("device = pic18f27q10 ' x")), 'pic18f27q10');
assert.strictEqual(deviceOf(scan('Dim device2 As Byte')), null);
const fixd = (src) => {
  const lines = src.split('\n');
  for (const e of caseEdits(scan(src), devNames).sort((a, b) => b.line - a.line || b.s - a.s)) lines[e.line] = lines[e.line].slice(0, e.s) + e.text + lines[e.line].slice(e.e);
  return lines.join('\n');
};
assert.strictEqual(fixd("lata = 0 ' set all port A pins low"), "LATA = 0 ' set all port A pins low");
assert.strictEqual(fixd('trisb = 0 : portb.0 = 1'), 'TRISB = 0 : PORTB.0 = 1');
assert.strictEqual(fixd('lata.lata0 = 1'), 'LATA.LATA0 = 1');
assert.strictEqual(fixd('dim led as lata.0'), 'Dim led As LATA.0');
assert.strictEqual(fixd('x.lata = 1'), 'x.lata = 1'); // a field of something else
assert.strictEqual(fixd('dim lata as byte\nlata = 1'), 'Dim lata As Byte\nlata = 1'); // the program's own name wins
assert.strictEqual(fixd('print "lata"'), 'print "lata"');
assert.strictEqual(fixd('config lvp = on'), 'Config lvp = on');
assert.strictEqual(fixd('lata = 0'), fixd(fixd('lata = 0'))); // idempotent
// Left alone: identifiers, strings, comments, literals, members, config values, asm, preprocessor.
assert.strictEqual(fix('dimension = 1'), 'dimension = 1');
assert.strictEqual(fix('x = _Clock'), 'x = _Clock');
assert.strictEqual(fix('x = "dim as if"'), 'x = "dim as if"');
assert.strictEqual(fix("x = 1 ' dim as if"), "x = 1 ' dim as if");
assert.strictEqual(fix('x = 2 // dim'), 'x = 2 // dim');
assert.strictEqual(fix('x = $dec + $add + %101'), 'x = $dec + $add + %101');
assert.strictEqual(fix('x = #13'), 'x = #13');
assert.strictEqual(fix('s.word = 1'), 's.word = 1');
assert.strictEqual(fix('device = 18f27q10'), 'Device = 18f27q10');
assert.strictEqual(fix('config lvp = on, wdte = off'), 'Config lvp = on, wdte = off');
assert.strictEqual(fix('config lvp = on : dim x as byte'), 'Config lvp = on : Dim x As Byte');
assert.strictEqual(fix('#define dim 1'), '#define dim 1');
assert.strictEqual(fix('(* dim\nif *) dim a as byte'), '(* dim\nif *) Dim a As Byte');
assert.strictEqual(fix('{ if { dim } if } if x then'), '{ if { dim } if } If x Then');
assert.strictEqual(fix('asm\n  movlw 1\n  end if\nend asm\ndim a as byte'), 'Asm\n  movlw 1\n  end if\nEnd Asm\nDim a As Byte');
assert.strictEqual(fix('Dim a As Byte\nDim b'), 'Dim a As Byte\nDim b');
// Idempotent on already-correct text.
assert.strictEqual(fix('Public Sub A()\nEnd Sub'), 'Public Sub A()\nEnd Sub');

// Every library and test source is already in canonical case except where it is deliberately not.
const root = path.join(__dirname, '../..');
for (const f of fs.readdirSync(path.join(root, 'lib')).filter((x) => x.endsWith('.bas'))) {
  const text = fs.readFileSync(path.join(root, 'lib', f), 'utf8').replace(/\r/g, '');
  const bad = caseEdits(scan(text)).filter((e) => text.split('\n')[e.line].slice(e.s, e.e).toLowerCase() === e.text.toLowerCase());
  // Informational only: the compiler is case-insensitive.
  if (process.env.VERBOSE && bad.length) console.log(f, bad.length, 'differences');
}

// Indentation.
const src = `Program T
Device = 18F27Q10
Dim i As Byte
Public Sub A(ByVal x As Byte)
If x = 1 Then
i = 1
ElseIf x = 2 Then
i = 2
Else
i = 3
End If
Select i
Case 1
i = 2
Case Else
i = 3
End Select
For i = 1 To 3
While True
Break
Wend
Next
Asm
  nop
End Asm
End Sub
End`;
const want = `Program T
Device = 18F27Q10
Dim i As Byte
Public Sub A(ByVal x As Byte)
    If x = 1 Then
        i = 1
    ElseIf x = 2 Then
        i = 2
    Else
        i = 3
    End If
    Select i
        Case 1
            i = 2
        Case Else
            i = 3
    End Select
    For i = 1 To 3
        While True
            Break
        Wend
    Next
    Asm
  nop
    End Asm
End Sub
End`;
const lv = indentLevels(scan(src));
const got = src.split('\n').map((l, i) => (lv[i] === null ? l : '    '.repeat(lv[i]) + l.trim())).join('\n');
assert.strictEqual(got, want);
// A one-line If does not open a block.
const one = indentLevels(scan('If a Then b = 1\nx = 2'));
assert.deepStrictEqual(one, [0, 0]);

// Symbols.
const syms = parseSymbols(`Module M
' Adds two.
Public Function Add(ByVal a As Byte, ByVal b As Byte) As Byte
    Dim t As Byte
    Result = a + b
End Function
Public Const K = 3
Dim p, q(4) As Byte
Proc Old(a As Byte), Word
EndProc
`);
const names = syms.map((s) => `${s.kind}:${s.name}${s.local ? '*' : ''}`);
assert.deepStrictEqual(names, ['module:M', 'function:Add', 'dim:t*', 'const:K', 'dim:p', 'dim:q', 'proc:Old']);
assert.strictEqual(syms[1].returns, 'Byte');
assert.strictEqual(syms[1].doc, 'Adds two.');
assert.strictEqual(syms[1].endLine, 5);
assert.strictEqual(syms[6].returns, 'Word');
assert.deepStrictEqual(parseIncludes('Include "Serial"\n'), [{ name: 'Serial', line: 0 }]);

// All library files scan and parse without throwing.
for (const f of fs.readdirSync(path.join(root, 'lib')).filter((x) => x.endsWith('.bas'))) {
  const text = fs.readFileSync(path.join(root, 'lib', f), 'utf8');
  const s = parseSymbols(text);
  assert.ok(s.some((x) => x.kind === 'module'), f + ' has no Module');
}

// Hover and completion documentation.
{
  const { parseDevice } = require('../src/devicenames');
  const hd = require('../src/hoverdocs');
  const info = parseDevice(fs.readFileSync(path.join(root, 'devices', '18F27Q10.toml'), 'utf8'));
  assert.strictEqual(info.device, 'PIC18F27Q10');
  assert.strictEqual(info.regs.get('latb').addr, 3971);
  assert.deepStrictEqual(info.bits.get('rb0').map((b) => [b.reg, b.pos, b.width]), [['PORTB', 0, 1]]);
  assert.ok(info.config.get('rstosc').settings.some((x) => x.name === 'HFINTOSC_64MHZ'));
  assert.deepStrictEqual(info.regs.get('sp2brg').members, ['SP2BRGL', 'SP2BRGH']);
  assert.ok(hd.regDoc(info, info.regs.get('portb')).includes('0xF8D'));
  assert.ok(hd.bitDoc(info, info.bits.get('rb0')).includes('bit 0 of `PORTB`'));
  assert.ok(hd.configDoc(info, info.config.get('rstosc')).includes('HFINTOSC_64MHZ'));
  assert.ok(hd.numberDoc('0x1F').includes('= 31 ='));
  assert.ok(hd.numberDoc('$FF').includes('0b11111111'));
  assert.ok(hd.numberDoc('300').includes('2 bytes'));
  assert.strictEqual(hd.numberDoc('18F27Q10'), null);
  assert.deepStrictEqual(hd.parseParams('ByVal a As Byte, ByRefConst s As String(80), n'), [
    { name: 'a', mode: 'ByVal', type: 'Byte' }, { name: 's', mode: 'ByRefConst', type: 'String(80)' }, { name: 'n', mode: '', type: '' }]);
  assert.ok(hd.moduleDoc(fs.readFileSync(path.join(root, 'lib', 'serial.bas'), 'utf8')).includes('EUSART1'));
}
console.log('ok');

// Project files, device catalog, tool names.
{
  const os = require('os');
  const proj = require('../src/project');
  const devs = proj.listDevices([path.join(__dirname, '../../devices')]);
  assert.ok(devs.some((d) => d.name === '18F27Q10' && d.pack === 'PIC18F-Q_DFP' && d.packVersion), 'device catalog');
  assert.ok(devs.every((d) => !/expect/i.test(d.name)));
  assert.strictEqual(proj.mplabDevice('18f27q10'), 'PIC18F27Q10');
  assert.strictEqual(proj.mplabDevice('PIC18F27Q10'), 'PIC18F27Q10');
  assert.strictEqual(proj.toolName('pk4'), 'PICkit 4');
  assert.deepStrictEqual(proj.parseTools([[{ name: 'PICkit 4', serial: 'BUR1' }], 'MPLAB Snap']).map((t) => [t.tool, t.serial]), [['PICkit 4', 'BUR1'], ['Snap', undefined]]);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'picbasic-'));
  const target = path.join(dir, 'Blink');
  const src = proj.createProject(target, { name: 'Blink', device: 'PIC18F27Q10', clockHz: 4000000, pack: devs.find((d) => d.name === '18F27Q10') });
  assert.ok(/Device = 18F27Q10\nClock = 4000000/.test(fs.readFileSync(src, 'utf8')));
  const launch = JSON.parse(fs.readFileSync(path.join(target, '.vscode/launch.json'), 'utf8')).configurations[0];
  assert.deepStrictEqual([launch.type, launch.device, launch.tool, launch.packName, launch.program], ['mplab-core-da', 'PIC18F27Q10', 'Simulator', 'PIC18F-Q_DFP', '${workspaceFolder}/dist/Blink.elf']);
  assert.ok(!('interface' in launch));
  assert.throws(() => proj.createProject(target, { name: 'Blink', device: '18F27Q10', clockHz: 1 }), /not empty/);
  proj.updateLaunch(target, { name: 'Blink', device: '18F27Q10', tool: 'PICkit 4', serial: 'X1' });
  const l2 = JSON.parse(fs.readFileSync(path.join(target, '.vscode/launch.json'), 'utf8')).configurations;
  assert.strictEqual(l2.length, 1);
  assert.deepStrictEqual([l2[0].tool, l2[0].interface, l2[0].serial], ['PICkit 4', 'ICSP', 'X1']);
  proj.updateLaunch(target, { name: 'Blink', device: '18F27Q10', tool: 'Simulator' });
  const l3 = JSON.parse(fs.readFileSync(path.join(target, '.vscode/launch.json'), 'utf8')).configurations[0];
  assert.ok(!('serial' in l3) && !('interface' in l3));
  const prog = proj.launchConfig({ name: 'Blink', device: '18F27Q10', tool: 'Snap', programOnly: true });
  assert.ok(prog.noDebug && /\.hex$/.test(prog.program) && !('stopOnEntry' in prog));
  fs.writeFileSync(path.join(target, 'Blink.hex'), ':00000001FF\n');
  assert.deepStrictEqual(proj.collectArtifacts(src), ['Blink.hex']);
  assert.ok(fs.existsSync(path.join(target, 'dist/Blink.hex')));
  fs.rmSync(dir, { recursive: true, force: true });
}
console.log('project ok');
