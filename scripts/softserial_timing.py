#!/usr/bin/env python3
"""Measure the bit times of a software-serial transmission in the cycle-exact simulator (basil-sim).

    softserial_timing.py prog.hex prog.S --device 18F27Q10 --latch LATB --bit 1 --baud 9600 --fosc 64 [--invert] [--expect 0xA5]

Runs the program with `--trace` and watches one bit of one latch. It prints every edge (cycle, level), then the
bit time in instruction cycles of each bit of the first frame, the decoded byte and the largest error against the
ideal bit time (fosc * 1e6 / 4 / baud). Exit status 1 when the error is above --tol (percent, default 3) or the
decoded byte differs from --expect.
"""
import argparse, os, re, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("hex")
ap.add_argument("asm")
ap.add_argument("--device", default="18F27Q10")
ap.add_argument("--latch", default="LATB")
ap.add_argument("--bit", type=int, default=1)
ap.add_argument("--baud", type=int, default=9600)
ap.add_argument("--fosc", type=float, default=64.0)
ap.add_argument("--invert", action="store_true")
ap.add_argument("--expect", default=None)
ap.add_argument("--tol", type=float, default=3.0)
ap.add_argument("--gie", default=None, help="register whose bit 7 is the global interrupt enable (INTCON, INTCON0): it must be 0 from the start bit to the end of the frame and set again after it (the program sets it before the byte)")
ap.add_argument("--to", type=int, default=0, help="last cycle traced (default: 40 bit times after cycle 0 plus the start-up)")
ap.add_argument("--sim", default=os.path.join(os.path.dirname(__file__), "../../picsim/target/release/basil-sim"))
a = ap.parse_args()

ideal = a.fosc * 1e6 / 4 / a.baud
to = a.to or int(ideal * 40) + 4000
r = subprocess.run([a.sim, a.hex, "--device", a.device, "--asm", a.asm, "--trace", f"0-{to}", "--trace-regs", a.latch + ("," + a.gie if a.gie else "")],
                   capture_output=True, text=True)
level, edges, gie = None, [], []
for line in r.stdout.splitlines():
    m = re.match(r"\s*(\d+)\s.*\b" + a.latch + r"=([0-9A-Fa-f]{2})", line)
    if not m:
        continue
    cyc, v = int(m.group(1)), (int(m.group(2), 16) >> a.bit) & 1
    if level is not None and v != level:
        edges.append((cyc, v))
    level = v
    if a.gie:
        g = re.search(r"\b" + a.gie + r"=([0-9A-Fa-f]{2})", line)
        if g:
            gie.append((cyc, int(g.group(1), 16) >> 7))
idle = 0 if a.invert else 1
# the first edge away from idle is the start bit; skip the initial drive to idle
frame = None
for i, (c, v) in enumerate(edges):
    if v == 1 - idle:
        frame = i
        break
if frame is None:
    print("no start bit found; edges:", edges[:10])
    sys.exit(1)
t0 = edges[frame][0]
# sample each bit in the middle of its ideal slot, using the real edges to know the level
def level_at(t):
    lv = idle
    for c, v in edges:
        if c <= t:
            lv = v
        else:
            break
    return lv
byte = 0
for k in range(8):
    lv = level_at(t0 + int(ideal * (k + 1.5)))
    bit = lv if not a.invert else 1 - lv
    byte |= bit << k
# the measured bit time: from the start edge to the last edge of the frame / number of bit slots that edge ends
rel = [(c - t0, v) for c, v in edges[frame:frame + 12]]
errs = []
for c, v in rel[1:]:
    n = round(c / ideal)
    if n:
        errs.append(abs(c / n - ideal) / ideal * 100)
print(f"ideal bit {ideal:.1f} cycles; edges (cycle from start): {[c for c, _ in rel]}")
print(f"decoded 0x{byte:02X}; largest edge error {max(errs):.2f} %")
bad = max(errs) > a.tol
if a.gie:
    t_end = t0 + 10 * ideal          # the end of the stop bit
    inside = [g for c, g in gie if t0 <= c < t_end - ideal]
    after = [g for c, g in gie if c > t_end + 4 * ideal]
    ok_gie = bool(inside) and not any(inside) and bool(after) and all(after)
    print(f"{a.gie} bit 7 during the frame: {'always 0' if inside and not any(inside) else 'NOT held low'}; after: {'1 again' if after and all(after) else 'NOT restored'}")
    if not ok_gie:
        print("FAIL: interrupts not held off and restored")
        bad = True
if a.expect is not None and byte != int(a.expect, 0):
    print(f"FAIL: expected {a.expect}")
    bad = True
sys.exit(1 if bad else 0)
