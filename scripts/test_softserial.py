#!/usr/bin/env python3
"""Check the `softserial` module's baud rate in the cycle-exact simulator (basil-sim) on several parts.

For each part and baud rate: the transmit timing (every edge of a frame within 3 % of the ideal bit time, the byte
decoded, and the global interrupt enable low for the whole frame and set again after it) with `softserial_timing.py`, and the receive window (the receiver must take a sender whose bit time is 3 %
fast or slow) with `softserial_rx_sweep.py`. The rates are the ones each part's Clock supports (see the module's header).
Exit status 1 when a case fails. Needs a built `basil` and the picsim workspace's `basil-sim`.
"""
import os, re, subprocess, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
basil = os.path.join(here, "../target/release/basil")
# (device, clock MHz, latch, bit of the latch = pin bit, pin number, bauds)
cases = [
    ("18F27Q10", 64, "LATB", 1, 9, [1200, 9600, 38400, 115200]),
    ("18F16Q41", 64, "LATB", 4, 12, [9600, 115200]),
    ("16F17146", 32, "LATB", 4, 12, [1200, 9600, 19200]),
    ("16F15244", 32, "LATB", 4, 12, [9600]),
    ("16F18056", 32, "LATB", 4, 12, [9600]),
]
fails = 0
for dev, clk, latch, bit, pin, bauds in cases:
  for flags in ("", "-O0"):   # the cycle counts differ between the optimised and the -O0 build
    # one pass of the -O0 wait is 11 cycles, 8 % of a bit at 115200 baud: that rate is for the optimised build
    for baud in [b for b in bauds if not (flags and b >= 115200)]:
        gie = "INTCON0" if dev.endswith("Q41") else "INTCON"   # the global interrupt enable is bit 7 of it
        work = tempfile.mkdtemp(prefix="sstest-")
        bas = os.path.join(work, "tx.bas")
        open(bas, "w").write(f"""Program Tx
Device = {dev}
Clock = {clk}
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_{clk}MHZ, WDTE = OFF, LVP = ON
Include "softserial"
Dim ok As Boolean
Dim gie As {gie}.7
ok = SoftInit({pin}, 255, {baud}, False)
gie = 1
SoftWriteByte($A5)
""")
        r = subprocess.run([basil, "--keep-vars", *flags.split(), bas], capture_output=True, text=True)
        if r.returncode:
            print(f"FAIL {dev} {flags or '-O1'} {baud}: compile\n{r.stderr}")
            fails += 1
            continue
        t = subprocess.run([sys.executable, os.path.join(here, "softserial_timing.py"), os.path.join(work, "tx.hex"),
                            os.path.join(work, "tx.S"), "--device", dev, "--latch", latch, "--bit", str(bit), "--baud", str(baud),
                            "--fosc", str(clk), "--expect", "0xA5", "--tol", "3", "--gie", gie], capture_output=True, text=True)
        x = subprocess.run([sys.executable, os.path.join(here, "softserial_rx_sweep.py"), "--device", dev, "--clock", str(clk),
                            "--baud", str(baud), "--port", "B", "--bit", str(bit), f"--flags={flags}"], capture_output=True, text=True)
        m = re.search(r"([+-][\d.]+) % \.\. ([+-][\d.]+) %", x.stdout)
        rx_ok = bool(m) and float(m.group(1)) <= -3 and float(m.group(2)) >= 3
        tx_line = t.stdout.strip().splitlines()[-1] if t.stdout.strip() else t.stderr.strip()
        status = "ok  " if t.returncode == 0 and rx_ok else "FAIL"
        if status == "FAIL":
            fails += 1
        print(f"{status} {dev} {clk} MHz {flags or '-O1':>3} {baud:6d} baud: TX {tx_line}; RX {m.group(0) if m else x.stdout.strip() or x.stderr.strip()}")
sys.exit(1 if fails else 0)
