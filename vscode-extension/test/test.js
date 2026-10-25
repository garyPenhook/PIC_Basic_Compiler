'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { scan, caseEdits, indentLevels } = require('../src/scanner');
const { parseSymbols, parseIncludes } = require('../src/symbols');
const { CANONICAL } = require('../src/keywords');

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

// Basic correction.
assert.strictEqual(fix('dim x as byte'), 'Dim x As Byte');
assert.strictEqual(fix('IF a THEN\nendif'), 'If a Then\nEndIf');
assert.strictEqual(fix('end if'), 'End If');
assert.strictEqual(fix('dim a as longword'), 'Dim a As LongWord');
assert.strictEqual(fix('delayms(5)'), 'DelayMs(5)');
assert.strictEqual(fix('goto done'), 'GoTo done');
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
console.log('ok');
