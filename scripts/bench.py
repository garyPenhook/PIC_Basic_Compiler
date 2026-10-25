#!/usr/bin/env python3
"""Benchmark basil against XC8 on the kernels in bench/kernels (PLAN 7A.4).

For every NAME.bas / NAME.c pair: program bytes, data bytes and the simulator cycles between
two markers (BASIC: `mark_a:` / `mark_b:` labels in Asm blocks; C: calls to mark_a()/mark_b(),
whose call overhead is measured with an empty kernel and subtracted). The value each kernel
leaves in `sink` must be identical in all builds -- a difference is a bug somewhere.

Usage: bench.py [--md] [kernel ...]
"""
import argparse, glob, os, re, subprocess, sys, tempfile

root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--basil", default=os.path.join(root, "target/release/basil"))
ap.add_argument("--md", action="store_true", help="print a Markdown table")
ap.add_argument("kernels", nargs="*")
a = ap.parse_args()
if not os.path.exists(a.basil):
    a.basil = os.path.join(root, "target/debug/basil")
mdb = sorted(glob.glob("/opt/microchip/mplabx/v*/mplab_platform/bin/mdb.sh"))[-1]
dfp = sorted(glob.glob(os.path.expanduser("~/.mchp_packs/Microchip/PIC18F-Q_DFP/*/xc8")))[-1]
names = a.kernels or sorted(os.path.basename(f)[:-4] for f in glob.glob(os.path.join(root, "bench/kernels/*.bas")))
work = tempfile.mkdtemp(prefix="basil-bench-")


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def xc8(src, opt, out):
    r = sh(["xc8-cc", "-mcpu=18F27Q10", f"-mdfp={dfp}", opt, "-std=c99", "-mno-default-config-bits",
            "-fno-short-double", "-fno-short-float", "-mwarn=-3", "-o", out, src])
    o = r.stdout + r.stderr
    p = re.search(r"Program space\s+used\s+\w+h \(\s*(\d+)\)", o)
    d = re.search(r"Data space\s+used\s+\w+h \(\s*(\d+)\)", o)
    if not p:
        sys.exit(f"xc8 failed for {src}:\n{o}")
    return int(p.group(1)), int(d.group(1))


# ---- builds
jobs = []  # (label, kernel, kind, image, program_bytes, data_bytes, info)
empty_c = os.path.join(work, "empty.c")
open(empty_c, "w").write(open(os.path.join(root, "bench/kernels", "sum16.c")).read().split("void main")[0]
                         + "void main(void){ mark_a(); mark_b(); for(;;){} }\n")
for opt in ("-Os", "-O2"):
    out = os.path.join(work, f"empty{opt}.elf")
    xc8(empty_c, opt, out)
    jobs.append((f"xc8 {opt}", "(empty)", "c", out, 0, 0, None))
for k in names:
    b = os.path.join(root, "bench/kernels", k + ".bas")
    hexf = os.path.join(work, k + ".hex")
    r = sh([a.basil, "--report", b, "-o", hexf])
    if r.returncode != 0:
        sys.exit(f"basil failed for {k}:\n{r.stdout}{r.stderr}")
    words = int(re.search(r"Program: (\d+) words", r.stdout).group(1))
    ram = int(re.search(r"total (\d+) bytes", r.stdout).group(1))
    asm = open(os.path.join(work, k + ".S")).read()
    syms = {m.group(1): int(m.group(2), 16) for m in re.finditer(r"^;SYM (\S+) 0x([0-9A-F]+)", asm, re.M)}
    sink = re.search(r"^K_SINK equ 0x([0-9A-F]+).*\((\d+) bytes?\)", asm, re.M)
    jobs.append(("basil", k, "bas", hexf, words * 2, ram, (syms["mark_a"], syms["mark_b"], int(sink.group(1), 16), int(sink.group(2)))))
    for opt in ("-Os", "-O2"):
        out = os.path.join(work, f"{k}{opt}.elf")
        pb, db = xc8(os.path.join(root, "bench/kernels", k + ".c"), opt, out)
        jobs.append((f"xc8 {opt}", k, "c", out, pb, db, None))

# ---- simulator
script = ["device PIC18F27Q10", "hwtool SIM"]
for i, (label, k, kind, img, pb, db, info) in enumerate(jobs):
    script.append(f"program {img}")
    if kind == "bas":
        script += [f"break *0x{info[0]:X}", f"break *0x{info[1]:X}"]
    else:
        script += ["break mark_a", "break mark_b"]
    script += ["run", "wait 60000", "stopwatch", "run", "wait 60000", "stopwatch"]
    if kind == "bas":
        script.append(f"x /{info[3]}xb 0x{info[2]:X}")
    elif k != "(empty)":
        script.append("print sink")
    script += [f"echo END_{i}", "delete"]
script.append("quit")
sp = os.path.join(work, "bench.mdb")
open(sp, "w").write("\n".join(script) + "\n")
out = sh([mdb, sp], timeout=3600).stdout

results = {}
pos = 0
for i, (label, k, kind, img, pb, db, info) in enumerate(jobs):
    end = out.find(f"END_{i}", pos)
    seg = out[pos:end]
    pos = end + 1
    cyc = re.findall(r"Stopwatch cycle count = (\d+)", seg)
    cycles = int(cyc[1]) if len(cyc) > 1 else None
    val = None
    if kind == "bas":
        m = re.search(r"^x /\d+xb 0x[0-9A-Fa-f]+\n((?:[0-9a-f]{2}\s+)+)", seg, re.M)
        if m:
            bs = [int(x, 16) for x in m.group(1).split()][: info[3]]
            val = sum(b << (8 * j) for j, b in enumerate(bs))
    elif k != "(empty)":
        m = re.search(r"sink=\s*\n?\s*(-?\d+)", seg)
        if m:
            val = int(m.group(1))
    results[(label, k)] = (pb, db, cycles, val)

base = {lab: results[(lab, "(empty)")][2] for lab in ("xc8 -Os", "xc8 -O2")}
rows = []
bad = 0
for k in names:
    ours = results[("basil", k)]
    row = [k]
    ref = None
    for lab in ("basil", "xc8 -Os", "xc8 -O2"):
        pb, db, cy, val = results[(lab, k)]
        if lab != "basil" and cy is not None:
            cy -= base[lab]
        if ref is None:
            ref = val
        elif val != ref:
            bad += 1
            print(f"MISMATCH {k}: {lab} sink={val}, basil sink={ref}", file=sys.stderr)
        row += [pb, db, cy]
    rows.append(row)

hdr = ["kernel", "basil B", "RAM", "cyc", "Os B", "RAM", "cyc", "O2 B", "RAM", "cyc"]
if a.md:
    print("| " + " | ".join(hdr) + " |")
    print("|" + "|".join(["---"] + ["---:"] * 9) + "|")
    for r in rows:
        print("| " + " | ".join(str(x) for x in r) + " |")
else:
    print("  ".join(f"{h:>8}" for h in hdr))
    for r in rows:
        print("  ".join(f"{str(x):>8}" for x in r))
print(f"\nwork dir: {work}", file=sys.stderr)
sys.exit(1 if bad else 0)
