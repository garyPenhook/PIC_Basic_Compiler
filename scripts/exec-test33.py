#!/usr/bin/env python3
"""Compile BASIC programs for the dsPIC33CK64MC105 and check their results in the MDB simulator.

Each program names its expectations in comments near the top:

    ' expect: T_A=5 T_B=300 T_C=-7   (variable symbol = decimal value; little endian, size from the .S; a negative value is two's complement)

Usage: exec-test33.py [--basil PATH] [--keep] prog.bas ...
The program must reach `__halt` (a Terminate, or falling off the end of the program). Variables are named by their
assembly symbols (see `basil --report`).
"""
import argparse, glob, os, re, shutil, subprocess, sys, tempfile

ap = argparse.ArgumentParser()
ap.add_argument("--basil", default=os.path.join(os.path.dirname(__file__), "../target/release/basil"))
ap.add_argument("--mdb", default=None)
ap.add_argument("--keep", action="store_true")
ap.add_argument("--wait", type=int, default=1500, help="milliseconds each program runs before it is stopped")
ap.add_argument("--flags", default="", help="extra compiler flags, e.g. -O0")
ap.add_argument("--port", action="store_true", help="port programs written for the PIC18F27Q10 (tests/exec): replace their Device, Config and Clock lines; a program the dsPIC33 back end cannot build yet is skipped, with the reason counted")
ap.add_argument("files", nargs="+")
a = ap.parse_args()
mdb = a.mdb or (sorted(glob.glob("/opt/microchip/mplabx/v*/mplab_platform/bin/mdb.sh")) or [None])[-1]
if mdb is None:
    sys.exit("MDB (MPLAB X) not found")
work = tempfile.mkdtemp(prefix="basil-exec33-")
if not a.keep:
    import atexit
    atexit.register(shutil.rmtree, work, ignore_errors=True)

jobs, fails, skipped = [], 0, {}
for src in a.files:
    orig_src = src
    name = os.path.splitext(os.path.basename(src))[0]
    hexf = os.path.join(work, name + ".hex")
    if a.port:
        text = open(src).read()
        if re.search(r"^'\s*devices:", text, re.M) or re.search(r"^'\s*(dma|stim|engine):", text, re.M):
            skipped["not a plain program"] = skipped.get("not a plain program", 0) + 1
            continue
        text = re.sub(r"^(\s*Device\s*=\s*)\S+", lambda m: m.group(1) + "dsPIC33CK64MC105", text, count=1, flags=re.M | re.I)
        text = re.sub(r"^[ \t]*Config[ \t].*$", "Config FWDTEN = ON_SW", text, flags=re.M | re.I)
        text = re.sub(r"^(\s*Clock\s*=\s*)\d+", lambda m: m.group(1) + "8", text, flags=re.M | re.I)
        for cf in re.findall(r'^\s*Include\s+"([^"]+)"', text, re.M | re.I):
            mod = os.path.join(os.path.dirname(src), cf + ".bas")
            if os.path.exists(mod):
                shutil.copy(mod, work)
        src = os.path.join(work, name + ".bas")
        open(src, "w").write(text)
    r = subprocess.run([a.basil, "--keep-vars", *a.flags.split(), src, "-o", hexf], capture_output=True, text=True)
    if r.returncode != 0:
        if a.port:
            why = next((l for l in r.stderr.splitlines() if "error[" in l), r.stderr.strip()[:80])
            why = re.sub(r"^.*?error\[[^\]]*\]: ", "", why)
            why = re.sub(r"`[^`]*`", "`_`", why)
            skipped[why] = skipped.get(why, 0) + 1
            continue
        print(f"FAIL {name}: compile\n{r.stderr}")
        fails += 1
        continue
    asm = open(os.path.join(work, name + ".S")).read()
    vars_ = {m.group(1): (int(m.group(2), 16), int(m.group(3))) for m in re.finditer(r"^\s*\.equ (\w+), 0x([0-9A-F]+)\s*; .*\((\d+) bytes\)", asm, re.M)}
    halt = re.search(r"^\s+0x([0-9a-f]+)\s+__halt\s*$", open(os.path.join(work, name + ".map")).read(), re.M)
    if not halt:
        print(f"FAIL {name}: no __halt in the map")
        fails += 1
        continue
    text = open(src).read()
    expect = {}
    for line in re.findall(r"^'\s*expect:(.*)$", text, re.M):
        for kv in line.split():
            k, v = kv.split("=")
            expect[k] = int(v, 0)
    cy = re.search(r"^'\s*cycles:\s*(\d+)\s+(\d+)", text, re.M)
    st = re.search(r"^'\s*stim:\s*(\S+)", text, re.M)
    stim = os.path.abspath(os.path.join(os.path.dirname(orig_src), st.group(1))) if st else None
    jobs.append((name, os.path.join(work, name + ".elf"), int(halt.group(1), 16), vars_, expect, (int(cy.group(1)), int(cy.group(2))) if cy else None, stim))

script = ["device dsPIC33CK64MC105", "hwtool sim"]
for name, elf, halt, vars_, expect, cyc, stim in jobs:
    # A breakpoint on the halt loop (`bra __halt`) is not hit in the simulator, so the program runs a while and is stopped; it has
    # finished when it sits on the halt loop.
    # `cycles:` stops on the halt loop with a breakpoint, so the stopwatch is the run time of the program; `stim:` attaches an SCL file (after the program is loaded).
    script += [f"program {elf}"]
    if stim:
        script += [f"stim {stim}"]
    if cyc:
        script += [f"break *0x{halt:X}"]
    script += ["run", f"wait {a.wait}"]
    if cyc:
        script += ["stopwatch"]
    script += ["halt", "print PC"]
    for k in expect:
        if k in vars_:
            addr, size = vars_[k]
            script.append(f"x /{size}xb 0x{addr:X}")
    if cyc:
        script += ["delete"]
    if stim:
        script += ["stim"]
    script += ["echo END_" + name]
script.append("quit")
sp = os.path.join(work, "run.mdb")
open(sp, "w").write("\n".join(script) + "\n")
out = subprocess.run([mdb, sp], capture_output=True, text=True, timeout=3600, stdin=subprocess.DEVNULL).stdout if jobs else ""
if a.keep:
    open(os.path.join(work, "mdb.log"), "w").write(out)
    print("work dir:", work)

pos = 0
for name, elf, halt, vars_, expect, cyc, stim in jobs:
    end = out.find("END_" + name, pos)
    seg = out[pos:end if end >= 0 else len(out)]
    pos = end + 1 if end >= 0 else pos
    pc = re.search(r"^PC=(\d+)", seg, re.M)
    cycles = re.findall(r"cycle count = (\d+)", seg)
    blocks = re.findall(r"^x /\d+xb 0x[0-9A-Fa-f]+\n((?:[0-9a-f]{2}\s+)+)", seg, re.M)
    bad, bi = [], 0
    for k, want in expect.items():
        if k not in vars_:
            bad.append(f"{k}: no such symbol")
            continue
        size = vars_[k][1]
        if bi >= len(blocks):
            bad.append(f"{k}: no memory dump")
            continue
        got = sum(int(b, 16) << (8 * i) for i, b in enumerate(blocks[bi].split()[:size]))
        bi += 1
        m = (1 << (8 * size)) - 1
        if got != want & m:
            if sum(1 for b in bad if "want" in b) < 3:
                bad.append(f"{k}: want {want & m} got {got}")
            elif not any(b == "..." for b in bad):
                bad.append("...")
    if not pc or abs(int(pc.group(1)) - halt) > 4:
        bad.append(f"did not reach __halt (PC {pc.group(1) if pc else '?'}, __halt at {halt})")
    if cyc and not cycles:
        bad.append("no stopwatch reading")
    if cyc and cycles and not cyc[0] <= int(cycles[0]) <= cyc[1]:
        bad.append(f"cycles {cycles[0]} outside {cyc[0]}..{cyc[1]}")
    if bad:
        fails += 1
        print(f"FAIL {name}: " + "; ".join(bad))
    else:
        print(f"ok   {name}")
if skipped:
    print(f"{sum(skipped.values())} not built:")
    for why, n in sorted(skipped.items(), key=lambda x: -x[1]):
        print(f"  {n:4}  {why}")
sys.exit(1 if fails else 0)
