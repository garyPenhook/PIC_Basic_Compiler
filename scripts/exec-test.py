#!/usr/bin/env python3
"""Compile BASIC programs and check their results in the MDB simulator.

Each program names its expectations in comments near the top:

    ' expect: T_A=5 T_B=300      (variable symbol = decimal value; little endian, size from the .S)
    ' cycles: LO HI              (optional: total cycles to __halt must lie in LO..HI)

Usage: exec-test.py [--basil PATH] [--keep] prog.bas ...
Variables are named by their assembly symbols (see `basil --report`). The program must reach
`__halt` (a Terminate, or falling off the end of the program).
"""
import argparse, glob, os, re, subprocess, sys, tempfile

ap = argparse.ArgumentParser()
ap.add_argument("--basil", default=os.path.join(os.path.dirname(__file__), "../target/debug/basil"))
ap.add_argument("--mdb", default=None)
ap.add_argument("--keep", action="store_true")
ap.add_argument("--flags", default="", help="extra compiler flags, e.g. -O0 for the reference build")
ap.add_argument("files", nargs="+")
a = ap.parse_args()
mdb = a.mdb or sorted(glob.glob("/opt/microchip/mplabx/v*/mplab_platform/bin/mdb.sh"))[-1]
work = tempfile.mkdtemp(prefix="basil-exec-")

jobs = []
fails = 0
for src in a.files:
    name = os.path.splitext(os.path.basename(src))[0]
    hexf = os.path.join(work, name + ".hex")
    r = subprocess.run([a.basil, "--keep-vars", *a.flags.split(), src, "-o", hexf], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAIL {name}: compile\n{r.stderr}")
        fails += 1
        continue
    asm = open(os.path.join(work, name + ".S")).read()
    syms = {m.group(1): int(m.group(2), 16) for m in re.finditer(r"^;SYM (\S+) 0x([0-9A-F]+)", asm, re.M)}
    vars_ = {}
    for m in re.finditer(r"^(\w+) equ 0x([0-9A-F]+)(?:  ; .*\((\d+) bytes?\))?", asm, re.M):
        vars_[m.group(1)] = (int(m.group(2), 16), int(m.group(3) or 1))
    head = open(src).read()
    expect = {}
    for line in re.findall(r"^'\s*expect:(.*)$", head, re.M):
        for kv in line.split():
            k, v = kv.split("=")
            expect[k] = int(v, 0)
    if "__halt" not in syms:
        print(f"FAIL {name}: no __halt")
        fails += 1
        continue
    cy = re.search(r"^'\s*cycles:\s*(\d+)\s+(\d+)", head, re.M)
    jobs.append((name, hexf, syms, vars_, expect, (int(cy.group(1)), int(cy.group(2))) if cy else None))

script = ["device PIC18F27Q10", "hwtool SIM"]
for name, hexf, syms, vars_, expect, cyc_range in jobs:
    script += [f"program {hexf}", f"break *0x{syms['__halt']:X}", "run", "wait 60000", "stopwatch"]
    for k in expect:
        if k not in vars_:
            continue
        addr, size = vars_[k]
        script.append(f"x /{size}xb 0x{addr:X}")
    script.append("echo END_" + name)
    script.append("delete")
script.append("quit")
sp = os.path.join(work, "run.mdb")
open(sp, "w").write("\n".join(script) + "\n")
out = subprocess.run([mdb, sp], capture_output=True, text=True, timeout=1800).stdout
if a.keep:
    open(os.path.join(work, "mdb.log"), "w").write(out)
    print("work dir:", work)

pos = 0
for name, hexf, syms, vars_, expect, cyc_range in jobs:
    end = out.find("END_" + name, pos)
    seg = out[pos:end if end >= 0 else len(out)]
    pos = end + 1 if end >= 0 else pos
    cyc = re.findall(r"Stopwatch cycle count = (\d+)", seg)
    blocks = re.findall(r"^x /\d+xb 0x[0-9A-Fa-f]+\n((?:[0-9a-f]{2}\s+)+)", seg, re.M)
    halted = "Simulator halted" in seg or "Single breakpoint" in seg
    bad = []
    bi = 0
    for k, want in expect.items():
        if k not in vars_:
            bad.append(f"{k}: no such symbol")
            continue
        size = vars_[k][1]
        if bi >= len(blocks):
            bad.append(f"{k}: no memory dump")
            continue
        bytes_ = [int(x, 16) for x in blocks[bi].split()][:size]
        bi += 1
        got = sum(b << (8 * i) for i, b in enumerate(bytes_))
        if got != want & ((1 << (8 * size)) - 1):
            bad.append(f"{k}: want {want & ((1 << (8 * size)) - 1)} got {got}")
    if not halted:
        bad.append("did not reach __halt")
    if cyc_range and cyc:
        if not cyc_range[0] <= int(cyc[0]) <= cyc_range[1]:
            bad.append(f"cycles {cyc[0]} outside {cyc_range[0]}..{cyc_range[1]}")
    if bad:
        fails += 1
        print(f"FAIL {name}: " + "; ".join(bad))
    else:
        print(f"ok   {name}  ({cyc[0] if cyc else '?'} cycles)")
sys.exit(1 if fails else 0)
