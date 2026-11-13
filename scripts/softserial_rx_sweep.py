#!/usr/bin/env python3
"""Sweep the sender's bit time against the software-serial receiver in the cycle-exact simulator (basil-sim).

    softserial_rx_sweep.py --device 18F27Q10 --clock 64 --baud 9600 --port B --bit 1 [--pin 9] [--invert]

Builds a program that calls SoftInit(255, pin, baud) and SoftReadByte twice, then for sender bit times from -8 % to
+8 % of the ideal one (fosc / 4 / baud cycles) drives two characters (0x55 and 0xC3, to start at different phases)
on the pin and checks both are received. Prints the window of scales that work: it should be centred on 0 %, and wide
(a real UART needs about +-3 %). A window centred off 0 means PollCyc, RxBitCyc or RxStartCyc in lib/softserial.bas
is wrong by that many percent of a bit. `--print-stim` prints the stimulus of the 0 % case and exits.
"""
import argparse, os, re, subprocess, sys, tempfile

ap = argparse.ArgumentParser()
ap.add_argument("--device", default="18F27Q10")
ap.add_argument("--clock", type=float, default=64)
ap.add_argument("--baud", type=int, default=9600)
ap.add_argument("--port", default="B")
ap.add_argument("--bit", type=int, default=1)
ap.add_argument("--pin", type=int, default=None, help="pin number 0..23 (default: from port and bit)")
ap.add_argument("--invert", action="store_true")
ap.add_argument("--config", default=None)
ap.add_argument("--basil", default=os.path.join(os.path.dirname(__file__), "../target/release/basil"))
ap.add_argument("--sim", default=os.path.join(os.path.dirname(__file__), "../../picsim/target/release/basil-sim"))
ap.add_argument("--print-stim", action="store_true")
ap.add_argument("--bad-stop", action="store_true", help="with --print-stim: a third character, 0x0F, whose stop bit is low (a framing error)")
a = ap.parse_args()
pin = a.pin if a.pin is not None else (ord(a.port) - 65) * 8 + a.bit
ideal = a.clock * 1e6 / 4 / a.baud
chars = [0x55, 0xC3]

def stim(scale, start=12000, bad_stop=False):
    T = ideal * scale
    idle = 0 if a.invert else 1
    ev = [(0, idle)]
    t = start
    for ch in chars + ([0x0F] if bad_stop else []):
        last = bad_stop and ch == 0x0F
        bits = [1 - idle] + [((ch >> k) & 1) ^ (1 if a.invert else 0) for k in range(8)] + [1 - idle if last else idle]
        # an inverted line: data 1 is a low level; level = bit XOR invert
        lv = idle
        for i, b in enumerate(bits):
            when = round(t + i * T)
            if b != lv:
                ev.append((when, b)); lv = b
        if last:
            ev.append((round(t + 10 * T), idle))   # the framing-error character ends; the line returns to idle
        t += 10 * T + 2 * T   # two bit times of idle between characters
    out = []
    for when, b in ev:
        out.append(f'[[pin]]\nport = "{a.port}"\nbit = {a.bit}\nlevel = {b}\nat = {when}\n')
    return "\n".join(out)

if a.print_stim:
    print(stim(1.0, bad_stop=a.bad_stop)); sys.exit(0)

cfg = a.config or (f"Config FEXTOSC = OFF, RSTOSC = HFINTOSC_{int(a.clock)}MHZ, WDTE = OFF, LVP = ON")
src = f"""Program Rx
Device = {a.device}
Clock = {int(a.clock) if a.clock == int(a.clock) else a.clock}
{cfg}
Include "softserial"
Dim ok As Boolean
Dim a As Integer
Dim b As Integer
ok = SoftInit(255, {pin}, {a.baud}, {'True' if a.invert else 'False'})
a = SoftReadByte(50)
b = SoftReadByte(50)
"""
work = tempfile.mkdtemp(prefix="ssrx-")
bas = os.path.join(work, "rx.bas")
open(bas, "w").write(src)
r = subprocess.run([a.basil, "--keep-vars", bas], capture_output=True, text=True)
if r.returncode:
    print(r.stdout, r.stderr); sys.exit(2)
good = []
for pct in range(-80, 81, 5):
    sc = 1 + pct / 1000
    sf = os.path.join(work, "s.toml")
    open(sf, "w").write(stim(sc))
    r = subprocess.run([a.sim, os.path.join(work, "rx.hex"), "--device", a.device, "--asm", os.path.join(work, "rx.S"),
                        "--stim", sf, "--dump", "RX_A:2,RX_B:2"], capture_output=True, text=True)
    vals = [int(m) for m in re.findall(r"RX_[AB] = (\d+)", r.stdout)]
    ok = vals == chars
    good.append((pct / 10, ok, vals))
span = [p for p, ok, _ in good if ok]
print(f"{a.device} {a.clock} MHz {a.baud} baud pin {pin}{' inverted' if a.invert else ''}: works for sender bit time {min(span):+.1f} % .. {max(span):+.1f} %" if span else f"never works; sample: {good[len(good)//2]}")
