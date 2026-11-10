#!/usr/bin/env python3
"""Builds every generated pair with basil and XC8 (-Os, -O2); prints flash and RAM per program.
Flash in bytes for the PIC18, in words for the 16F (each tool's own unit).
Usage: for s in $(seq 1 12); do gen.py OUT $s 16; done; run.py OUT"""
import glob, os, re, subprocess, sys

d = sys.argv[1]
basil = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../target/release/basil")
packs = os.path.expanduser("~/.mchp_packs/Microchip")
dfp = {"18F27Q10": sorted(glob.glob(f"{packs}/PIC18F-Q_DFP/*/xc8"))[-1],
       "16F18346": sorted(glob.glob(f"{packs}/PIC16F1xxxx_DFP/*/xc8"))[-1]}
here = os.path.dirname(os.path.abspath(__file__))

def sh(c, cwd=None): return subprocess.run(c, capture_output=True, text=True, cwd=cwd)

def bas(src, dev):
    r = sh([basil, "--report", src]); o = r.stdout + r.stderr
    m = re.search(r"\((\d+) words", o); ram = re.search(r"total (\d+) bytes", o)
    if not m: sys.exit(f"basil failed {src}\n{o}")
    w = int(m.group(1))
    return (w * 2 if dev.startswith("18F") else w), int(ram.group(1))

def xc8(src, dev, opt):
    outd = os.path.join(os.path.dirname(src), "xc" + opt)
    os.makedirs(outd, exist_ok=True)
    r = sh(["xc8-cc", f"-mcpu={dev}", f"-mdfp={dfp[dev]}", opt, "-std=c99", "-mwarn=-3", f"-I{here}",
            "-o", os.path.join(outd, os.path.basename(src)[:-2] + ".elf"), src])
    o = r.stdout + r.stderr
    p = re.search(r"Program space\s+used\s+\w+h \(\s*(\d+)\)", o)
    dd = re.search(r"Data space\s+used\s+\w+h \(\s*(\d+)\)", o)
    if not p: sys.exit(f"xc8 failed {src}\n{o}")
    return int(p.group(1)), int(dd.group(1))

rows = []
for dev in ("18F27Q10", "16F18346"):
    for b in sorted(glob.glob(f"{d}/{dev}/r*.bas")):
        c = b[:-4] + ".c"
        rows.append((dev, os.path.basename(b)[:-4], bas(b, dev), xc8(c, dev, "-Os"), xc8(c, dev, "-O2")))
unit = {"18F27Q10": "bytes", "16F18346": "words"}
for dev in ("18F27Q10", "16F18346"):
    print(f"\n{dev} (flash in {unit[dev]})")
    print(f"{'prog':6} {'basil':>7} {'xc8 Os':>7} {'xc8 O2':>7} {'vs Os':>7}   RAM basil/Os/O2")
    tb = to = t2 = 0
    for r in rows:
        if r[0] != dev: continue
        _, n, (bf, br), (of, orr), (f2, r2) = r
        tb += bf; to += of; t2 += f2
        print(f"{n:6} {bf:7} {of:7} {f2:7} {100 * (bf - of) / of:+6.1f}%   {br}/{orr}/{r2}")
    print(f"{'total':6} {tb:7} {to:7} {t2:7} {100 * (tb - to) / to:+6.1f}%")
