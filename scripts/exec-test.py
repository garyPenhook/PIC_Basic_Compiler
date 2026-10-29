#!/usr/bin/env python3
"""Compile BASIC programs and check their results in the MDB simulator.

Each program names its expectations in comments near the top:

    ' expect: T_A=5 T_B=300      (variable symbol = decimal value; little endian, size from the .S)
    ' expect-18F16Q41: T_A=7    (optional: for that part, each name given overrides the same name in the ' expect: lines; names not given keep that value)
    ' devices: 18F27Q10 18F16Q41 (optional: run only for the listed parts (separated by spaces or commas); others are skipped, e.g. a program that tests _device or RB0.
                                  Skipped programs are counted, and a run in which every program is skipped fails)
    ' cycles: LO HI              (optional: total cycles to __halt must lie in LO..HI)

Usage: exec-test.py [--basil PATH] [--keep] prog.bas ...
Variables are named by their assembly symbols (see `basil --report`). The program must reach
`__halt` (a Terminate, or falling off the end of the program).

MDB has no DMA model. A program with a `' dma:` line runs instead in a live MDB session with the DMA model of
dma_sim.py attached (the line's words: `mailbox=SYMBOL` for the command byte the program writes to raise peripheral
requests, `slow` to let a started message wait for step commands, `sfr=NAME:1,2,3` for the bytes a DMA read of that
SFR returns, `ee=OFFSET:1,2,3` for data put in the EEPROM before the run). A `' dma-writes: NAME=1,2,3` line checks the bytes the DMA wrote, in order, to an SFR or address.
Expectations may name SFRs of the part as well as program variables.
"""
import argparse, glob, os, re, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dma_sim

ap = argparse.ArgumentParser()
ap.add_argument("--basil", default=os.path.join(os.path.dirname(__file__), "../target/debug/basil"))
ap.add_argument("--mdb", default=None)
ap.add_argument("--keep", action="store_true")
ap.add_argument("--device", default="18F27Q10", help="part to build for and simulate; the program's Device line is replaced")
ap.add_argument("--flags", default="", help="extra compiler flags, e.g. -O0 for the reference build")
ap.add_argument("files", nargs="+")
a = ap.parse_args()
mdb = a.mdb or sorted(glob.glob("/opt/microchip/mplabx/v*/mplab_platform/bin/mdb.sh"))[-1]
work = tempfile.mkdtemp(prefix="basil-exec-")

jobs = []
fails = 0
skipped = 0
for src in a.files:
    name = os.path.splitext(os.path.basename(src))[0]
    hexf = os.path.join(work, name + ".hex")
    text = open(src).read()
    only = re.search(r"^'\s*devices:(.*)$", text, re.M)
    if only and a.device not in re.split(r"[,\s]+", only.group(1).strip()):
        print(f"skip {name}  (only for {only.group(1).strip()})")
        skipped += 1
        continue
    if a.device != "18F27Q10":
        # Same program, other part: only the Device header changes (pins and peripherals are not touched).
        text = re.sub(r"^(\s*Device\s*=\s*)\S+", lambda m: m.group(1) + a.device, text, count=1, flags=re.M | re.I)
        src = os.path.join(work, name + ".bas")
        open(src, "w").write(text)
    r = subprocess.run([a.basil, "--keep-vars", *a.flags.split(), src, "-o", hexf], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAIL {name}: compile\n{r.stderr}")
        fails += 1
        continue
    asm_path = os.path.join(work, name + ".S")
    base = 0
    if not os.path.exists(asm_path):
        # A program that calls C: the code is relocatable, so the label table holds offsets from `_basil_entry`.
        asm_path = os.path.join(work, name + "_basil.S")
        entry = re.search(r"^_basil_entry\s+\w+\s+([0-9A-F]+)", open(os.path.join(work, name + ".map")).read(), re.M)
        if not entry:
            print(f"FAIL {name}: no _basil_entry in the map")
            fails += 1
            continue
        base = int(entry.group(1), 16)
    asm = open(asm_path).read()
    syms = {m.group(1): base + int(m.group(2), 16) for m in re.finditer(r"^;SYM (\S+) 0x([0-9A-F]+)", asm, re.M)}
    vars_ = {}
    for m in re.finditer(r"^(\w+) equ 0x([0-9A-F]+)(?:  ; .*\((\d+) bytes?\))?", asm, re.M):
        vars_[m.group(1)] = (int(m.group(2), 16), int(m.group(3) or 1))
    head = text
    expect = {}
    for line in re.findall(r"^'\s*expect:(.*)$", head, re.M) + re.findall(rf"^'\s*expect-{re.escape(a.device)}:(.*)$", head, re.M):
        for kv in line.split():
            k, v = kv.split("=")
            expect[k] = int(v, 0)
    if "__halt" not in syms:
        print(f"FAIL {name}: no __halt")
        fails += 1
        continue
    cy = re.search(r"^'\s*cycles:\s*(\d+)\s+(\d+)", head, re.M)
    dma = None
    dl = re.search(r"^'\s*dma:(.*)$", head, re.M)
    if dl:
        dma = {"mailbox": None, "slow": False, "sfr": {}, "writes": {}, "ee": []}
        for w in dl.group(1).split():
            if w == "slow":
                dma["slow"] = True
            elif w.startswith("mailbox="):
                dma["mailbox"] = w[8:]
            elif w.startswith("sfr="):
                k, v = w[4:].split(":")
                dma["sfr"][k] = [int(x, 0) for x in v.split(",")]
            elif w.startswith("ee="):
                k, v = w[3:].split(":")
                dma["ee"].append((int(k, 0), [int(x, 0) for x in v.split(",")]))
        for line in re.findall(r"^'\s*dma-writes:(.*)$", head, re.M):
            for kv in line.split():
                k, v = kv.split("=")
                dma["writes"][k] = [int(x, 0) for x in v.split(",")]
    jobs.append((name, hexf, syms, vars_, expect, (int(cy.group(1)), int(cy.group(2))) if cy else None, dma))

script = [f"device PIC{a.device}", "hwtool SIM"]
for name, hexf, syms, vars_, expect, cyc_range, dma in jobs:
    if dma:
        continue
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
out = subprocess.run([mdb, sp], capture_output=True, text=True, timeout=1800).stdout if any(not j[6] for j in jobs) else ""
if a.keep:
    open(os.path.join(work, "mdb.log"), "w").write(out)
    print("work dir:", work)

def run_dma(name, hexf, syms, vars_, expect, dma):
    """The program in MDB with the replayed DMA model; returns (problems, cycles)."""
    info = dma_sim.DeviceInfo(os.path.join(os.path.dirname(os.path.abspath(__file__)), f"../devices/{a.device}.toml"))
    bad = []

    def addr_of(k):
        if k in vars_:
            return vars_[k]
        if k in info.sfr:
            return info.sfr[k], 1
        if re.fullmatch(r"0x[0-9A-Fa-f]+|\d+", k):
            return int(k, 0), 1
        return None

    mailbox = None
    if dma["mailbox"]:
        if dma["mailbox"] not in vars_:
            return [f"mailbox {dma['mailbox']}: no such symbol"], None
        mailbox = vars_[dma["mailbox"]][0]
    feed = {}
    for k, v in dma["sfr"].items():
        loc = addr_of(k)
        if loc is None:
            return [f"dma sfr {k}: unknown"], None
        feed[loc[0]] = v
    plan = []  # (key, address, size) of what to read back at the end
    for k in expect:
        loc = addr_of(k)
        if loc is None:
            bad.append(f"{k}: no such symbol")
        else:
            plan.append((k, loc[0], loc[1]))
    lo = min(ad for ad, _ in vars_.values())
    hi = max(ad + sz for ad, sz in vars_.values())
    rp = dma_sim.Replay(mdb, a.device, hexf, syms["__halt"], info, mailbox, feed, dma["slow"], [(ad, sz, "r") for _, ad, sz in plan], (lo, hi - lo), dma["ee"])
    cyc = None
    try:
        cyc, blocks, writes = rp.run()
        for (k, ad, sz), blk in zip(plan, blocks):
            got = sum(b << (8 * i) for i, b in enumerate(blk[:sz]))
            want = expect[k] & ((1 << (8 * sz)) - 1)
            if got != want:
                bad.append(f"{k}: want {want} got {got}")
        for k, want in dma["writes"].items():
            loc = addr_of(k)
            got = writes.get(loc[0], []) if loc else None
            if got != want:
                bad.append(f"dma writes to {k}: want {want} got {got}")
    except (RuntimeError, subprocess.TimeoutExpired) as e:
        bad.append(str(e))
    return bad, cyc


pos = 0
for name, hexf, syms, vars_, expect, cyc_range, dma in jobs:
    if dma:
        bad, cy_ = run_dma(name, hexf, syms, vars_, expect, dma)
        if bad:
            fails += 1
            print(f"FAIL {name}: " + "; ".join(bad))
        else:
            print(f"ok   {name}  (DMA model)")
        continue
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
if skipped:
    print(f"{skipped} skipped for {a.device}")
if skipped == len(a.files):
    print("FAIL: every program was skipped")
    fails += 1
sys.exit(1 if fails else 0)
