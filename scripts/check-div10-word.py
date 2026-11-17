#!/usr/bin/env python3
"""Compare PIC16 Word /10 and Mod against Python divmod for every input."""
import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--basil', default=str(root / 'target/release/basil'))
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='basil-div10-') as work:
    files = []
    # Each image fits the 16F17146; both assignment orders are exercised.
    for base in range(0, 65536, 2048):
        values = [divmod(n, 10) for n in range(base, base + 2048)]
        tables = '\n'.join(
            f'Const {name}(2048) As Word = (' + ','.join(str(v[col]) for v in values) + ')'
            for name, col in [('Qref', 0), ('Rref', 1)])
        pair = 'q = n / 10\nr = n Mod 10' if base % 4096 == 0 else 'r = n Mod 10\nq = n / 10'
        source = f"""' expect: T_ERRORS=0 T_CHECKED=2048
Program T
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
{tables}
Dim i, n, q, r As Word
Volatile Dim errors, checked As Word
For i = 0 To 2047
n = i + {base}
{pair}
If q <> Qref(i) Or r <> Rref(i) Then
errors = errors + 1
End If
checked = checked + 1
Next
"""
        path = Path(work) / f'div10_{base:05}.bas'
        path.write_text(source)
        files.append(str(path))
    subprocess.run(['python3', str(root / 'scripts/exec-test.py'), '--basil', args.basil,
                    '--engine', 'sim', '--device', '16F17146', '--no-keep-vars', *files], check=True)
