#!/usr/bin/env python3
"""Check the `onewire` module's slot timing and its reading of a slave in the cycle-exact simulator (basil-sim).

For each part: a baseline run with nothing on the line (every pin switch of a reset, a write 1, a write 0 and a read slot
is a TRISx edge) gives the low times, which must be inside the 1-Wire standard-speed limits and the global interrupt enable
must be low during each slot and set again after it. Then the simulator's stimulus plays the slave: a presence pulse after
the reset, and a read slot in which the slave holds the line low for 14 us from the falling edge (the bit must read 0)
and for 6 us (it must read 1). Exit status 1 when a case fails. Needs a built `basil` and the picsim workspace's `basil-sim`.
"""
import os, re, subprocess, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
basil = os.path.join(here, "../target/release/basil")
sim = os.path.join(here, "../../picsim/target/release/basil-sim")
# (device, clock MHz, port, bit of the port, pin number)
cases = [
    ("18F27Q10", 64, "B", 1, 9),
    ("18F16Q41", 64, "B", 4, 12),
    ("16F17146", 32, "B", 4, 12),
    ("16F15244", 32, "B", 4, 12),
]
fails = 0

def run(dev, clk, hexf, asmf, port, bit, stim_pts, gie, cycles):
    stim = os.path.join(os.path.dirname(hexf), "stim.toml")
    with open(stim, "w") as f:
        for lvl, at in stim_pts:
            f.write(f'[[pin]]\nport = "{port}"\nbit = {bit}\nlevel = {lvl}\nat = {at}\n\n')
    r = subprocess.run([sim, hexf, "--device", dev, "--asm", asmf, "--stim", stim, "--trace", f"0-{cycles}",
                        "--trace-regs", f"TRIS{port},{gie}"], capture_output=True, text=True)
    prev, edges, g = None, [], []
    for line in r.stdout.splitlines():
        m = re.match(r"\s*(\d+)\s.*\bTRIS" + port + r"=([0-9A-Fa-f]{2})", line)
        if not m:
            continue
        c, v = int(m.group(1)), (int(m.group(2), 16) >> bit) & 1
        if prev is not None and v != prev:
            edges.append((c, v))
        prev = v
        k = re.search(r"\b" + gie + r"=([0-9A-Fa-f]{2})", line)
        if k:
            g.append((c, int(k.group(1), 16) >> 7))
    return edges, g

def dump(dev, hexf, asmf, port, bit, stim_pts, names):
    stim = os.path.join(os.path.dirname(hexf), "stim.toml")
    with open(stim, "w") as f:
        for lvl, at in stim_pts:
            f.write(f'[[pin]]\nport = "{port}"\nbit = {bit}\nlevel = {lvl}\nat = {at}\n\n')
    r = subprocess.run([sim, hexf, "--device", dev, "--asm", asmf, "--stim", stim, "--max-cycles", "400000",
                        "--dump", ",".join(names)], capture_output=True, text=True)
    out = {}
    for n in names:
        m = re.search(n + r"\S*\s*[=:]\s*(?:0x)?([0-9A-Fa-f]+)", r.stdout)
        out[n] = int(m.group(1), 16) if m else None
    return out, r.stdout

for dev, clk, port, bit, pin in cases:
    gie = "INTCON0" if dev.endswith("Q41") else "INTCON"
    work = tempfile.mkdtemp(prefix="owtest-")
    bas = os.path.join(work, "owt.bas")
    open(bas, "w").write(f"""Program Owt
Device = {dev}
Clock = {clk}
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_{clk}MHZ, WDTE = OFF, LVP = ON
Include "onewire"
Dim ok As Boolean
Dim p As Boolean
Dim w As Boolean
Dim b As Boolean
Dim gie As {gie}.7
ok = OwInit({pin})
gie = 1
p = OwReset()
OwWriteBit(True)
OwWriteBit(False)
b = OwReadBit()
w = gie = 1
""")
    r = subprocess.run([basil, "--keep-vars", bas], capture_output=True, text=True)
    hexf, asmf = os.path.join(work, "owt.hex"), os.path.join(work, "owt.S")
    if r.returncode:
        print(f"FAIL {dev} {clk}: compile\n{r.stderr}")
        fails += 1
        continue
    cyc_us = clk / 4.0                       # instruction cycles in a microsecond
    pull = [(1, 0)]
    edges, g = run(dev, clk, hexf, asmf, port, bit, pull, gie, int(cyc_us * 2600))
    # edges: reset fall, rise, write-1 fall, rise, write-0 fall, rise, read fall, rise
    if len(edges) < 8:
        print(f"FAIL {dev} {clk} MHz: only {len(edges)} edges {edges}")
        fails += 1
        continue
    us = lambda a, b: (edges[b][0] - edges[a][0]) / cyc_us
    low = [us(0, 1), us(2, 3), us(4, 5), us(6, 7)]
    slot = [us(2, 4), us(4, 6)]
    rec = [us(3, 4), us(5, 6)]
    msgs = []
    if not 480 <= low[0] <= 520: msgs.append(f"reset low {low[0]:.1f}")
    if not 1 <= low[1] <= 15: msgs.append(f"write-1 low {low[1]:.1f}")
    if not 60 <= low[2] <= 120: msgs.append(f"write-0 low {low[2]:.1f}")
    if not 1 <= low[3] <= 5: msgs.append(f"read low {low[3]:.1f}")
    if not all(60 <= s <= 120 for s in slot): msgs.append(f"slot {slot}")
    if not all(r >= 1 for r in rec): msgs.append(f"recovery {rec}")
    # the global interrupt enable: low from the fall to the rise of each slot, set again after the last slot
    for a in (2, 4, 6):
        inside = [v for c, v in g if edges[a][0] <= c <= edges[a + 1][0]]
        if not inside or any(inside): msgs.append(f"GIE not held low in slot {a // 2}")
    t_read_end = edges[7][0] + 90 * cyc_us
    after = [v for c, v in g if c > t_read_end]
    if not after or not all(after): msgs.append("GIE not restored")
    # slave: presence 30..150 us after the reset's release; read slot held low 14 us / 6 us from its fall
    rel = edges[1][0]
    fall = edges[6][0]
    res = {}
    for hold in (14, 6):
        pts = [(1, 0), (0, rel + int(30 * cyc_us)), (1, rel + int(150 * cyc_us)), (0, fall - 40), (1, fall + int(hold * cyc_us))]
        # the master's own pull is the pin level while it drives: the slave's low only matters while the pin is an input
        v, out = dump(dev, hexf, asmf, port, bit, pts, ["OWT_P", "OWT_B"])
        res[hold] = (v["OWT_P"], v["OWT_B"])
    if res[14][0] != 1: msgs.append("presence not seen")
    if res[14][1] != 0: msgs.append("14 us hold read as 1")
    if res[6][1] != 1: msgs.append("6 us hold read as 0")
    v0, _ = dump(dev, hexf, asmf, port, bit, pull, ["OWT_P"])
    if v0["OWT_P"] != 0: msgs.append("presence seen with nobody on the line")
    status = "FAIL" if msgs else "ok  "
    if msgs: fails += 1
    print(f"{status} {dev} {clk} MHz: reset low {low[0]:.0f} us, write 1 low {low[1]:.1f}, write 0 low {low[2]:.1f}, read low {low[3]:.1f}, slots {slot[0]:.0f}/{slot[1]:.0f}, recovery {rec[0]:.1f}/{rec[1]:.1f} us" + (f"; {'; '.join(msgs)}" if msgs else ""))

if "--search" not in sys.argv:
    sys.exit(1 if fails else 0)

# ---- ROM search against three simulated slaves -------------------------------------------------------------------
# The stimulus cannot answer the master, so the slaves are played by passes: run, read the master's slots from the TRISx
# edges (a long low = reset, a short one = a read or a write 1, a low over 30 us = a write 0), make the stimulus the slaves
# would have given, run again, until the stimulus no longer changes.
def crc8(bs):
    c = 0
    for b in bs:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ 0x8C if c & 1 else c >> 1
    return c
roms = []
for ser in ([1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 0x46], [9, 2, 3, 4, 5, 6]):
    r = [0x28] + ser
    roms.append(r + [crc8(r)])
def bits(r):
    return [(r[i // 8] >> (i % 8)) & 1 for i in range(64)]
expect = sorted(roms, key=bits)

def slaves(edges, cyc_us):
    """The stimulus points the slaves would give for the master slots seen in `edges`. A slot not seen yet is placed
    from the last one seen and the slot-to-slot time measured so far, so each pass sees further into the search."""
    pts = [(1, 0)]
    slots = [(edges[i][0], edges[i + 1][0]) for i in range(0, len(edges) - 1, 2)]
    long_slot = lambda s: (s[1] - s[0]) / cyc_us > 300
    resets = [i for i, s in enumerate(slots) if long_slot(s)]
    for n, i0 in enumerate(resets):
        end = resets[n + 1] if n + 1 < len(resets) else len(slots)
        r = slots[i0][1]
        pts += [(0, r + int(30 * cyc_us)), (1, r + int(150 * cyc_us))]
        blk = slots[i0 + 9:end]                 # after the reset and the command byte: read, read, write per position
        if not blk:
            continue
        per = 75.1 * cyc_us
        if len(blk) >= 6:
            per = (blk[-1][0] - blk[0][0]) / (len(blk) - 1)
        def fall(j):
            return blk[j][0] if j < len(blk) else blk[-1][0] + (j - len(blk) + 1) * per
        part = [bits(x) for x in roms]
        for pos in range(64):
            if not part:
                break
            for k, want in ((0, 0), (1, 1)):
                f1 = fall(3 * pos + k)
                if any(b[pos] == want for b in part):
                    pts += [(0, int(f1 - 4 * cyc_us)), (1, int(f1 + 12 * cyc_us))]
            if 3 * pos + 2 >= len(blk):
                # the write is not seen yet: the master takes the bit the slaves still agree on, else the 0 branch
                d = 0 if any(b[pos] == 0 for b in part) and not all(b[pos] == 1 for b in part) else 1
                if any(b[pos] == 0 for b in part) and any(b[pos] == 1 for b in part):
                    break                       # a fork the master has not shown the choice of
            else:
                f, rr = blk[3 * pos + 2]
                d = 0 if (rr - f) / cyc_us > 30 else 1
            part = [b for b in part if b[pos] == d]
    pts = sorted(set(pts), key=lambda t: (t[1], t[0]))
    return pts

for dev, clk, port, bit, pin in [("18F27Q10", 64, "B", 1, 9)]:
    work = tempfile.mkdtemp(prefix="owsearch-")
    bas = os.path.join(work, "ows.bas")
    open(bas, "w").write(f"""Program Ows
Device = {dev}
Clock = {clk}
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_{clk}MHZ, WDTE = OFF, LVP = ON
Include "onewire"
Dim ok As Boolean
Dim n As Byte
Dim i As Byte
Dim found(32) As Byte
ok = OwInit({pin})
n = 0
ok = OwSearchFirst()
While ok And n < 4
    For i = 0 To 7
        found(n * 8 + i) = OwRom(i)
    Next
    Inc(n)
    ok = OwSearchNext()
Wend
""")
    r = subprocess.run([basil, "--keep-vars", bas], capture_output=True, text=True)
    hexf, asmf = os.path.join(work, "ows.hex"), os.path.join(work, "ows.S")
    if r.returncode:
        print(f"FAIL {dev} search: compile\n{r.stderr}")
        fails += 1
        continue
    cyc_us = clk / 4.0
    pts = [(1, 0)]
    for it in range(60):
        edges, _ = run(dev, clk, hexf, asmf, port, bit, pts, "INTCON0" if dev.endswith("Q41") else "INTCON", int(cyc_us * 1000 * 55))
        new = slaves(edges, cyc_us)
        if new == pts:
            break
        pts = new
    stim = os.path.join(work, "stim.toml")
    with open(stim, "w") as f:
        for lvl, at in pts:
            f.write(f'[[pin]]\nport = "{port}"\nbit = {bit}\nlevel = {lvl}\nat = {at}\n\n')
    o = subprocess.run([sim, hexf, "--device", dev, "--asm", asmf, "--stim", stim, "--max-cycles", str(int(cyc_us * 1000 * 60)),
                        "--dump", "OWS_N,OWS_FOUND:32"], capture_output=True, text=True).stdout
    n = re.search(r"OWS_N\S*\s*[=:]?\s*(?:0x)?([0-9A-Fa-f]+)", o)
    fm = re.search(r"OWS_FOUND[^(]*\(((?:[0-9A-Fa-f]{2}\s*)+)\)", o)
    got = None
    if fm:
        raw = [int(x, 16) for x in fm.group(1).split()]
        got = [raw[i * 8:i * 8 + 8] for i in range(3)]
    ok = bool(n) and int(n.group(1), 16) == 3 and got == expect
    if not ok:
        fails += 1
    print(f"{'ok  ' if ok else 'FAIL'} {dev} {clk} MHz: ROM search of 3 slaves ({it + 1} passes): {'found all three in order' if ok else f'n={n.group(1) if n else None} got={got} dump={o.strip()[-300:]}'}")
sys.exit(1 if fails else 0)
