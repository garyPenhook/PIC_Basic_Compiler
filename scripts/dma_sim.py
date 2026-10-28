"""DMA model for the PIC18-Q41 and a replay driver that adds it to MPLAB X's MDB.

MDB does not model the DMA engine (SimPeripheralSupport.csv lists no DMA for any Q41 part) and has one flat register
set where the part overlays four channels by DMASELECT. This module adds both from the data sheet (DS40002214G
chapter 16). MDB cannot be driven live (after a watchpoint stop an interactive session does not resume), so the DMA
is replayed through scripts:

  1. A script runs the program with watchpoints on DMASELECT, DMAnCON0 and the test's mailbox byte. After every stop
     it logs the channel registers, PRLOCK, the data memory, the EEPROM and the DMA interrupt flags.
  2. The engine below replays that log: it keeps one register set per channel, acts on each write (start, soft stop,
     hard stop, run the message, a request or abort from the mailbox) and yields the `write` commands that put the
     moved bytes, the counters and pointers, DMAnCON0 and the flags into MDB.
  3. The script is built again with those commands after the stop they answer. A program that reads what the DMA did
     (DmaDone) then takes a different path, so the log changes; the passes repeat until the commands stop changing.

Mailbox: a test program that wants a peripheral to raise a request, or an abort, writes one command byte to the
variable named in its `' dma: mailbox=SYMBOL` header line; bits 7:6 are the command, 5:4 the channel minus one, 3:0 the
count:
    0  count start requests (SIRQ)          2  run count transactions of the message in progress (slow mode)
    1  abort request (AIRQ), after count    3  level request: keep requesting until SIRQEN clears (at most 4096 times)
    transactions of the message in progress

What is modelled: the pointers, counters and modes of Tables 16-3 to 16-5, messages ending when the smaller counter
reloads, SSTP/DSTP clearing SIRQEN, EN as a hard stop, DGO as a soft stop, the abort of 16.3.4.2.2, the four
interrupt flags, the arbiter's PRLOCKED gate [7.1.1], and the three source spaces (SFR/GPR, flash, data EEPROM).
What is not: bus timing (a message completes at once unless the header says `slow`), the one-cycle stop latency,
XIP and DMAnBUF in flight, trigger sources (the test says when a request arrives), and the arbiter priorities.
The EEPROM source address is taken as a byte offset, the form of TB3164 section 7.1 that library `dma` uses.
"""
import os, re, subprocess, tempfile

try:
    import tomllib
except ImportError:  # Python < 3.11
    tomllib = None

SSA_MASK = (1 << 22) - 1
DSA_MASK = 0xFFFF


class Channel:
    def __init__(self):
        self.reset()

    def reset(self):
        """Reset values of every channel register [16.9]."""
        self.ssa = self.ssz = self.dsa = self.dsz = 0
        self.con1 = self.sirq = self.airq = 0
        self.en = self.sirqen = self.dgo = self.airqen = 0
        self.sptr = self.dptr = self.scnt = self.dcnt = self.buf = 0

    @property
    def smode(self): return (self.con1 >> 1) & 3
    @property
    def dmode(self): return (self.con1 >> 6) & 3
    @property
    def smr(self): return (self.con1 >> 3) & 3
    @property
    def sstp(self): return self.con1 & 1
    @property
    def dstp(self): return (self.con1 >> 5) & 1

    def load_counters(self):
        self.sptr, self.scnt = self.ssa, self.ssz
        self.dptr, self.dcnt = self.dsa, self.dsz

    def con0(self):
        return self.en << 7 | self.sirqen << 6 | self.dgo << 5 | self.airqen << 2


class Engine:
    """Four DMA channels. `bus.read(space, addr)` with space 'r', 'p' or 'e' returns a byte; `bus.write(addr, byte)`
    stores one into SFR/GPR space; `bus.flag(name)` sets an interrupt flag such as DMA1AIF."""

    def __init__(self, bus, channels=4, slow=False):
        self.bus = bus
        self.ch = [Channel() for _ in range(channels)]
        self.locked = True   # PRLOCKED; the driver keeps it current
        self.slow = slow     # a started message waits for `step` commands instead of completing at once
        self.cur = 0         # DMASELECT

    def load_config(self, n, cfg):
        """The writable registers as the program left them in the overlay: ssa, ssz, dsa, dsz, con1, sirq, airq."""
        c = self.ch[n]
        c.ssa, c.ssz = cfg["ssa"] & SSA_MASK, cfg["ssz"] & 0xFFF
        c.dsa, c.dsz = cfg["dsa"] & DSA_MASK, cfg["dsz"] & 0xFFF
        c.con1, c.sirq, c.airq = cfg["con1"] & 0xFF, cfg["sirq"] & 0xFF, cfg["airq"] & 0xFF

    def write_con0(self, n, val):
        """The program wrote DMAnCON0 of channel n [16.13.2]."""
        c = self.ch[n]
        en = val >> 7 & 1
        if not en:
            if c.en:
                c.reset()  # hard stop: back to the default configuration [16.3.4.2.5]
            return
        if not c.en:
            c.en = 1
            c.load_counters()
        c.sirqen = val >> 6 & 1
        c.airqen = val >> 2 & 1
        if val >> 5 & 1:
            if not c.dgo:
                c.dgo = 1
                if not self.slow:
                    self.run(n)
        else:
            c.dgo = 0  # soft stop: pointers and counters stay [16.3.4.2.1]

    def request(self, n, count=1):
        """`count` start requests from the peripheral selected by SIRQ [16.3.4.1.2]."""
        c = self.ch[n]
        for _ in range(count):
            if not (c.en and c.sirqen):
                return
            if c.dgo:
                self.bus.flag(f"DMA{n + 1}ORIF")  # a request while a message runs [16.8.5]
                continue
            c.dgo = 1
            if not self.slow:
                self.run(n)

    def level(self, n, cap=4096):
        """A level request: asserted until the DMA stops accepting it. Returns how many messages it started."""
        c = self.ch[n]
        started = 0
        while c.en and c.sirqen and started < cap:
            before = c.dgo
            self.request(n)
            if before:
                break  # busy in slow mode: the request stays up, nothing more to do now
            started += 1
        return started

    def abort(self, n, after=0):
        """An abort request [16.3.4.2.2]; `after` transactions of the message in progress still complete first."""
        c = self.ch[n]
        if not (c.en and c.airqen):
            return
        if after:
            self.run(n, after)
        c.dgo = 0
        c.sirqen = 0
        c.airqen = 0
        self.bus.flag(f"DMA{n + 1}AIF")

    def step(self, n, count):
        self.run(n, count)

    def run(self, n, limit=None):
        """Run transactions of the message in progress, to its end or for `limit` of them."""
        c = self.ch[n]
        done = 0
        while c.dgo and self.locked and (limit is None or done < limit):
            self.transaction(n)
            done += 1

    def transaction(self, n):
        c = self.ch[n]
        space = "e" if c.smr & 2 else "p" if c.smr == 1 else "r"
        c.buf = self.bus.read(space, c.sptr)
        self.bus.write(c.dptr, c.buf)
        end = False
        if c.scnt == 1:
            c.scnt, c.sptr = c.ssz, c.ssa
            self.bus.flag(f"DMA{n + 1}SCNTIF")
            end = True
            if c.sstp:
                c.sirqen = 0
        else:
            c.scnt -= 1
            c.sptr += {0: 0, 1: 1, 2: -1}.get(c.smode, 0)
        if c.dcnt == 1:
            c.dcnt, c.dptr = c.dsz, c.dsa
            self.bus.flag(f"DMA{n + 1}DCNTIF")
            end = True
            if c.dstp:
                c.sirqen = 0
        else:
            c.dcnt -= 1
            c.dptr += {0: 0, 1: 1, 2: -1}.get(c.dmode, 0)
        c.sptr &= SSA_MASK
        c.dptr &= DSA_MASK
        if end:
            c.dgo = 0  # the smaller counter reloaded: message complete [16.3.3]


DMASELECT, DMA_FIRST, DMA_SSZL, DMA_CON0, DMA_CON1, DMA_AIRQ, DMA_SIRQ, PRLOCK = 0xE8, 0xE9, 0xF7, 0xFC, 0xFD, 0xFE, 0xFF, 0xB4


class DeviceInfo:
    """SFR addresses and interrupt-flag locations from devices/<part>.toml."""

    def __init__(self, path):
        self.sfr = {}   # name -> address
        self.bit = {}   # field name -> (address, bit)
        self.sfr_addrs = set()
        self.eeprom = 0
        self.eeprom_base = 0  # where MDB addresses the data EEPROM
        if tomllib is None or not os.path.exists(path):
            return
        with open(path, "rb") as f:
            d = tomllib.load(f)
        for s in d.get("sfr", []):
            self.sfr[s["name"]] = s["addr"]
            for fl in s.get("fields", []):
                if fl.get("width") == 1:
                    self.bit.setdefault(fl["name"], (s["addr"], fl["pos"]))
        self.sfr_addrs = set(self.sfr.values())
        ee = d.get("memory", {}).get("eeprom", {})
        self.eeprom, self.eeprom_base = ee.get("size", 0), ee.get("start", 0)




HEX_LINE = re.compile(r"^:([0-9A-Fa-f]{2})([0-9A-Fa-f]{4})([0-9A-Fa-f]{2})([0-9A-Fa-f]*)([0-9A-Fa-f]{2})$")


def hex_image(path):
    """Program memory of an Intel hex file as {byte address: byte}."""
    img, base = {}, 0
    for line in open(path):
        m = HEX_LINE.match(line.strip())
        if not m:
            continue
        n, addr, kind, data = int(m.group(1), 16), int(m.group(2), 16), int(m.group(3), 16), m.group(4)
        if kind == 0:
            for i in range(n):
                img[base + addr + i] = int(data[2 * i:2 * i + 2], 16)
        elif kind == 4:
            base = int(data[:4], 16) << 16
    return img


def blocks_of(text):
    """The byte lists printed by the `x` commands in `text`, in order."""
    out, cur = [], None
    for line in text.splitlines():
        line = line.lstrip(">").strip()
        if re.match(r"^x /\w*\d+xb ", line):
            cur = []
            out.append(cur)
        elif cur is not None and re.fullmatch(r"(?:[0-9a-fA-F]{2}\s*)+", line):
            cur += [int(x, 16) for x in line.split()]
        elif line:
            cur = None
    return out


class Event:
    """What MDB showed at one stop."""

    def __init__(self, text, info, mailbox):
        m = re.search(r"Single breakpoint: @0x([0-9A-Fa-f]+)", text)
        self.hit = int(m.group(1), 16) if m else None
        self.blocks = blocks_of(text)
        self.flag_addrs = sorted({info.bit[f"DMA{n}{k}IF"][0] for n in range(1, 5) for k in ("SCNT", "DCNT", "OR", "A")})
        self.mailbox = mailbox

    def parse(self, info):
        b = self.blocks
        if len(b) < 5 or len(b[0]) < 9:
            return False
        self.cfg, self.dsz, self.sel, self.prlock = b[0], b[1], b[2][0], b[3][0]
        i = 4
        self.mail = None
        if self.mailbox is not None:
            self.mail = b[i][0]
            i += 1
        self.ram = b[i]
        i += 1
        self.ee = b[i] if info.eeprom else []
        i += 1 if info.eeprom else 0
        self.flags = {a: b[i + k][0] for k, a in enumerate(self.flag_addrs)}
        return True

    def key(self):
        return (self.hit, self.cfg, self.dsz, self.sel, self.prlock, self.mail, self.ram, self.ee, tuple(sorted(self.flags.items())))


class Replay:
    """Runs one program through MDB with the DMA engine replayed into it; see the module comment."""

    def __init__(self, mdb, device, hexf, halt, info, mailbox=None, feed=None, slow=False, reads=(), ram=(0, 0), eeinit=(), timeout_ms=60000):
        self.mdb, self.device, self.hexf, self.halt, self.info = mdb, device, hexf, halt, info
        self.mailbox, self.feed, self.slow, self.reads, self.timeout_ms = mailbox, feed or {}, slow, list(reads), timeout_ms
        self.eeinit = list(eeinit)
        self.ram_lo, self.ram_n = ram  # the data memory window MDB is asked for at every stop: the program's variables
        self.flash = hex_image(hexf)
        self.work = tempfile.mkdtemp(prefix="basil-dma-")
        self.writes = {}
        self.passes = 0

    def script(self, inj, nev):
        s = [f"device PIC{self.device}", "hwtool SIM", f"program {self.hexf}", f"break *0x{self.halt:X}"]
        s += [f"write /e 0x{self.info.eeprom_base + o:X} " + " ".join(map(str, v)) for o, v in self.eeinit]
        for a in (DMASELECT, DMA_CON0) + ((self.mailbox,) if self.mailbox is not None else ()):
            s.append(f"watch 0x{a:X} W")
        flag_addrs = sorted({self.info.bit[f"DMA{n}{k}IF"][0] for n in range(1, 5) for k in ("SCNT", "DCNT", "OR", "A")})
        for i in range(nev):
            s += ["run", f"wait {self.timeout_ms}",
                  f"x /r9xb 0x{DMA_SSZL:X}", "x /r4xb 0xEE", f"x /r1xb 0x{DMASELECT:X}", f"x /r1xb 0x{PRLOCK:X}"]
            if self.mailbox is not None:
                s.append(f"x /r1xb 0x{self.mailbox:X}")
            s.append(f"x /r{self.ram_n}xb 0x{self.ram_lo:X}")
            if self.info.eeprom:
                s.append(f"x /e{self.info.eeprom}xb 0x{self.info.eeprom_base:X}")
            s += [f"x /r1xb 0x{a:X}" for a in flag_addrs]
            s += inj.get(i, [])
            s.append(f"echo EV{i}")
        s += ["stopwatch"] + [f"x /{mem}{n}xb 0x{a:X}" for a, n, mem in self.reads] + ["echo FINAL", "quit"]
        return "\n".join(s) + "\n"

    def replay(self, events):
        """Run the engine over the stops; returns the commands to inject after each, and the SFR write log."""
        info = self.info
        pend, writes, flagbits = {}, {}, {}
        feed = {a: list(v) for a, v in self.feed.items()}
        cur = {"ev": None}

        class Bus:
            def read(_, space, addr):
                ev = cur["ev"]
                if space == "p":
                    return self.flash.get(addr, 0xFF)
                if space == "e":
                    return ev.ee[addr] if addr < len(ev.ee) else 0xFF
                if addr in pend:
                    return pend[addr]
                if addr in feed:
                    q = feed[addr]
                    return q.pop(0) if len(q) > 1 else q[0]
                return ev.ram[addr - self.ram_lo] if 0 <= addr - self.ram_lo < len(ev.ram) else 0

            def write(_, addr, val):
                if addr in info.sfr_addrs:
                    writes.setdefault(addr, []).append(val)
                else:
                    pend[addr] = val

            def flag(_, name):
                a, bit = info.bit[name]
                flagbits[a] = flagbits.get(a, 0) | 1 << bit

        eng = Engine(Bus(), slow=self.slow)
        inj = {}
        for i, ev in enumerate(events):
            if ev.hit == self.halt:
                break
            cur["ev"] = ev
            pend.clear()
            flagbits.clear()
            eng.locked = bool(ev.prlock & 1)
            n = eng.cur

            def pull():
                c = ev.cfg
                eng.load_config(n, dict(ssz=c[0] | c[1] << 8, ssa=c[2] | c[3] << 8 | c[4] << 16,
                                        dsz=ev.dsz[0] | ev.dsz[1] << 8, dsa=ev.dsz[2] | ev.dsz[3] << 8,
                                        con1=c[6], airq=c[7], sirq=c[8]))
                return c[5]

            if ev.hit == DMASELECT:
                pull()
                eng.cur = ev.sel & 3
            elif ev.hit == DMA_CON0:
                eng.write_con0(n, pull())
            elif ev.hit == self.mailbox:
                cmd = ev.mail
                op, chn, cnt = cmd >> 6, cmd >> 4 & 3, cmd & 15
                if op == 0:
                    eng.request(chn, cnt)
                elif op == 1:
                    eng.abort(chn, cnt)
                elif op == 2:
                    eng.step(chn, cnt)
                else:
                    eng.level(chn)
            else:
                raise RuntimeError(f"stop at unexpected address 0x{ev.hit:X}")
            c = eng.ch[eng.cur]
            cmds = []
            run = []
            for a in sorted(pend):
                if run and a == run[-1][0] + 1:
                    run.append((a, pend[a]))
                else:
                    if run:
                        cmds.append(f"write /r 0x{run[0][0]:X} " + " ".join(str(v) for _, v in run))
                    run = [(a, pend[a])]
            if run:
                cmds.append(f"write /r 0x{run[0][0]:X} " + " ".join(str(v) for _, v in run))
            regs = [c.buf, c.dcnt & 255, c.dcnt >> 8 & 255, c.dptr & 255, c.dptr >> 8 & 255,
                    c.dsz & 255, c.dsz >> 8, c.dsa & 255, c.dsa >> 8,
                    c.scnt & 255, c.scnt >> 8 & 255, c.sptr & 255, c.sptr >> 8 & 255, c.sptr >> 16 & 255,
                    c.ssz & 255, c.ssz >> 8, c.ssa & 255, c.ssa >> 8, c.ssa >> 16 & 255]
            cmds.append(f"write /r 0x{DMA_FIRST:X} " + " ".join(map(str, regs)))
            cmds.append(f"write /r 0x{DMA_CON0:X} {c.con0()} {c.con1} {c.airq} {c.sirq}")
            for a, bits in flagbits.items():
                cmds.append(f"write /r 0x{a:X} {ev.flags[a] | bits}")
            inj[i] = cmds
        return inj, writes

    def run(self):
        """Returns (cycles or None, byte lists of `reads`, SFR write log). Raises RuntimeError when the program does not halt."""
        inj, nev, prev = {}, 24, None
        for _ in range(8):
            self.passes += 1
            sp = os.path.join(self.work, "run.mdb")
            open(sp, "w").write(self.script(inj, nev))
            out = subprocess.run([self.mdb, sp], capture_output=True, text=True, timeout=3600).stdout
            parts = re.split(r"/\*EV(\d+)\*/", out)
            texts = parts[0::2]  # the text before each marker, the last one is the tail
            events = []
            for t in texts[:-1]:
                ev = Event(t, self.info, self.mailbox)
                if ev.hit is None or not ev.parse(self.info):
                    break
                events.append(ev)
                if ev.hit == self.halt:
                    break
            if not events or events[-1].hit != self.halt:
                if len(events) == nev:
                    nev *= 2  # more stops than the script allowed for
                    continue
                raise RuntimeError("program did not reach __halt (pass %d, %d stops)" % (self.passes, len(events)))
            new, writes = self.replay(events)
            if new == inj:
                tail = texts[-1]
                m = re.search(r"Stopwatch cycle count = (\d+)", out)
                return (m.group(1) if m else None), blocks_of(tail), writes
            inj, nev = new, len(events) + 2
        raise RuntimeError("DMA replay did not settle in 8 passes")
