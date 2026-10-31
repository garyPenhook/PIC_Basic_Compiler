"""Instruction-level simulator for the PIC18 code the Basil compiler writes (.S, pic-as syntax), with a model of the
PIC18-Q41 I2C1 host peripheral and a simulated I2C client.

The peripheral model follows DS40002214G 36.3.12, 36.4.2.x and the register descriptions 36.5.x. Every point where the
data sheet is silent or ambiguous and the driver depends on a choice is marked [A#]; the list at the end of the file
(ASSUMPTIONS) is what has to be confirmed on silicon.
"""
import heapq, re, sys, tomllib

# ----------------------------------------------------------------------------------------------------------------
# Assembly loader
# ----------------------------------------------------------------------------------------------------------------
SIZE4 = {"call", "goto", "movff", "lfsr"}


class Inst:
    __slots__ = ("addr", "op", "args", "size", "line")

    def __init__(self, addr, op, args, size, line):
        self.addr, self.op, self.args, self.size, self.line = addr, op, args, size, line


def split_args(s):
    return [a.strip() for a in s.split(",")] if s.strip() else []


def load_asm(path, sfr):
    """Returns (prog {byte addr: Inst}, pmem bytearray, symbols {name: value})."""
    syms = dict(sfr)
    lines = []
    for raw in open(path):
        code = raw.split(";")[0].rstrip()
        if code.strip():
            lines.append(code)
    equs = []
    prog, pmem = {}, bytearray(0x20000)
    addr = 0
    labels = {}
    pend = []
    for ln in lines:
        s = ln.strip()
        if s.startswith("#") or s.startswith("CONFIG") or s.upper().startswith("PSECT"):
            continue
        m = re.match(r"^([A-Za-z_.$][\w.$]*)\s+equ\s+(.+)$", s)
        if m:
            equs.append((m.group(1), m.group(2).strip()))
            continue
        if re.match(r"^ORG\s", s, re.I):
            addr = int(s.split()[1], 0)
            continue
        m = re.match(r"^([A-Za-z_.$][\w.$]*):\s*(.*)$", s)
        if m:
            labels[m.group(1)] = addr
            s = m.group(2).strip()
            if not s:
                continue
        parts = s.split(None, 1)
        op = parts[0].lower()
        rest = parts[1] if len(parts) > 1 else ""
        if op == "db":
            for b in split_args(rest):
                pend.append((addr, "db", b))
                addr += 1
            continue
        if op == "retlw":
            pend.append((addr, "retlw", rest.strip()))
            addr += 2
            continue
        size = 4 if op in SIZE4 else 2
        args = split_args(rest)
        prog[addr] = Inst(addr, op, args, size, s)
        addr += size
    syms.update(labels)
    # equ values may refer to other symbols; resolve by repeated passes
    todo = list(equs)
    for _ in range(10):
        left = []
        for n, e in todo:
            try:
                syms[n] = evalx(e, syms)
            except KeyError:
                left.append((n, e))
        todo = left
        if not todo:
            break
    assert not todo, todo
    for a, kind, v in pend:
        if kind == "db":
            pmem[a] = evalx(v, syms) & 255
        else:
            pmem[a], pmem[a + 1] = evalx(v, syms) & 255, 0x0C
    for inst in prog.values():
        inst.args = [resolve(a, syms) for a in inst.args]
    return prog, pmem, syms


def evalx(e, syms):
    e = e.strip()
    m = re.match(r"^(low|high)\((.+)\)$", e, re.I)
    if m:
        v = evalx(m.group(2), syms)
        return v & 255 if m.group(1).lower() == "low" else (v >> 8) & 255
    total, sign, i = 0, 1, 0
    for tok in re.findall(r"[+-]|[^+-]+", e):
        tok = tok.strip()
        if tok == "+":
            sign = 1
        elif tok == "-":
            sign = -1
        else:
            if re.match(r"^(0x[0-9A-Fa-f]+|\d+)$", tok):
                v = int(tok, 0)
            elif re.match(r"^0[0-9A-Fa-f]+h$", tok, re.I):
                v = int(tok[:-1], 16)
            else:
                v = syms[tok]
            total += sign * v
            sign = 1
    return total


def resolve(a, syms):
    try:
        return evalx(a, syms)
    except KeyError:
        return a.lower() if a.lower() in ("w", "f", "c", "b", "a", "0", "1", "s", "fast") else a


# ----------------------------------------------------------------------------------------------------------------
# CPU
# ----------------------------------------------------------------------------------------------------------------
class CPU:
    def __init__(self, asm, device_toml, periph_factory=None):
        d = tomllib.load(open(device_toml, "rb"))
        self.sfr = {s["name"]: s["addr"] for s in d["sfr"]}
        self.prog, self.pmem, self.syms = load_asm(asm, self.sfr)
        self.mem = bytearray(0x1000)
        self.pc = 0
        self.cycles = 0
        self.stack = []
        self.icount = 0
        S = self.sfr
        self.A_W, self.A_BSR, self.A_ST = S["WREG"], S["BSR"], S["STATUS"]
        self.fsr = []
        for n in range(3):
            self.fsr.append(dict(L=S[f"FSR{n}L"], H=S[f"FSR{n}H"], INDF=S[f"INDF{n}"], POSTINC=S[f"POSTINC{n}"],
                                 POSTDEC=S[f"POSTDEC{n}"], PREINC=S[f"PREINC{n}"], PLUSW=S[f"PLUSW{n}"]))
        self.ind = {}
        for n, f in enumerate(self.fsr):
            for k in ("INDF", "POSTINC", "POSTDEC", "PREINC", "PLUSW"):
                self.ind[f[k]] = (n, k)
        self.A_PRODL, self.A_PRODH = S["PRODL"], S["PRODH"]
        self.A_TBLL, self.A_TBLH, self.A_TBLU, self.A_TAB = S["TBLPTRL"], S["TBLPTRH"], S["TBLPTRU"], S["TABLAT"]
        self.periph = periph_factory(self) if periph_factory else None
        self.pmap = {}
        if self.periph:
            for a in self.periph.addresses():
                self.pmap[a] = self.periph
        self.halt = self.syms.get("__halt")

    # --- data memory ---------------------------------------------------------------------------------------------
    def fsrv(self, n):
        f = self.fsr[n]
        return self.mem[f["L"]] | (self.mem[f["H"]] & 15) << 8

    def setfsr(self, n, v):
        f = self.fsr[n]
        self.mem[f["L"]] = v & 255
        self.mem[f["H"]] = (v >> 8) & 15

    def read(self, a):
        a &= 0xFFF
        if a in self.ind:
            n, k = self.ind[a]
            v = self.fsrv(n)
            if k == "INDF":
                return self.read(v)
            if k == "POSTINC":
                r = self.read(v)
                self.setfsr(n, v + 1)
                return r
            if k == "POSTDEC":
                r = self.read(v)
                self.setfsr(n, v - 1)
                return r
            if k == "PREINC":
                self.setfsr(n, v + 1)
                return self.read(v + 1)
            return self.read(v + self.mem[self.A_W] - (256 if self.mem[self.A_W] > 127 else 0))
        p = self.pmap.get(a)
        if p:
            return p.read(a)
        return self.mem[a]

    def write(self, a, v):
        a &= 0xFFF
        v &= 255
        if a in self.ind:
            n, k = self.ind[a]
            f = self.fsrv(n)
            if k == "INDF":
                return self.write(f, v)
            if k == "POSTINC":
                self.write(f, v)
                self.setfsr(n, f + 1)
                return
            if k == "POSTDEC":
                self.write(f, v)
                self.setfsr(n, f - 1)
                return
            if k == "PREINC":
                self.setfsr(n, f + 1)
                return self.write(f + 1, v)
            return self.write(f + self.mem[self.A_W] - (256 if self.mem[self.A_W] > 127 else 0), v)
        p = self.pmap.get(a)
        if p:
            return p.write(a, v)
        self.mem[a] = v

    # --- flags ---------------------------------------------------------------------------------------------------
    def flag(self, bit):
        return (self.mem[self.A_ST] >> bit) & 1

    def setflags(self, **kw):
        st = self.mem[self.A_ST]
        for k, bit in (("C", 0), ("DC", 1), ("Z", 2), ("OV", 3), ("N", 4)):
            if k in kw:
                st = (st & ~(1 << bit)) | (kw[k] << bit)
        self.mem[self.A_ST] = st

    def zn(self, r):
        self.setflags(Z=int(r == 0), N=(r >> 7) & 1)

    def add(self, a, b, cin=0):
        r = a + b + cin
        c = (r >> 8) & 1
        dc = ((a & 15) + (b & 15) + cin) >> 4 & 1
        r &= 255
        ov = int(((a ^ r) & (b ^ r) & 0x80) != 0)
        self.setflags(C=c, DC=dc, OV=ov, Z=int(r == 0), N=r >> 7)
        return r

    # --- operand helpers -----------------------------------------------------------------------------------------
    def ea(self, f, a):
        if a == "b":
            return (self.mem[self.A_BSR] << 8) | (f & 255)
        if f >= 0x100:
            return f
        return 0x500 + f if f < 0x60 else 0x400 + f

    @property
    def W(self):
        return self.mem[self.A_W]

    @W.setter
    def W(self, v):
        self.mem[self.A_W] = v & 255

    # --- execution -----------------------------------------------------------------------------------------------
    def step(self):
        inst = self.prog.get(self.pc)
        if inst is None:
            raise RuntimeError(f"no instruction at {self.pc:#x}")
        self.icount += 1
        h = HANDLERS.get(inst.op)
        if h is None:
            raise NotImplementedError(f"{inst.op}  ({inst.line})")
        self.pc += inst.size
        self.cycles += 1
        h(self, inst)
        if self.periph:
            self.periph.tick(self.cycles)

    def skip(self):
        nxt = self.prog.get(self.pc)
        size = nxt.size if nxt else 2
        self.pc += size
        self.cycles += 1 if size == 2 else 2

    def run(self, max_instr=50_000_000):
        while self.icount < max_instr:
            if self.pc == self.halt and self.prog[self.pc].op == "bra":
                return True
            self.step()
        return False


def fd(inst):
    """Parse [f, d, a] / [f, a] operand lists."""
    return inst.args


def get_f_d_a(inst):
    args = inst.args
    f = args[0]
    d = "f"
    a = "c"
    for x in args[1:]:
        if x in ("w", "0"):
            d = "w"
        elif x in ("f", "1"):
            d = "f"
        elif x in ("c", "a"):
            a = "c"
        elif x == "b":
            a = "b"
    return f, d, a


def dest(cpu, d, ea, r):
    if d == "w":
        cpu.W = r
    else:
        cpu.write(ea, r)


def mk_alu_f(fn, flags=True):
    def h(cpu, inst):
        f, d, a = get_f_d_a(inst)
        ea = cpu.ea(f, a)
        r = fn(cpu, cpu.read(ea))
        dest(cpu, d, ea, r)
    return h


def _movf(cpu, v):
    cpu.zn(v)
    return v


def _incf(cpu, v):
    return cpu.add(v, 1)


def _decf(cpu, v):
    return cpu.add(v, 255)


def _comf(cpu, v):
    r = (~v) & 255
    cpu.zn(r)
    return r


def _rrncf(cpu, v):
    r = ((v >> 1) | ((v & 1) << 7)) & 255
    cpu.zn(r)
    return r


def _rlncf(cpu, v):
    r = ((v << 1) | (v >> 7)) & 255
    cpu.zn(r)
    return r


def _swapf(cpu, v):
    return ((v << 4) | (v >> 4)) & 255


def _rlcf(cpu, v):
    r = ((v << 1) | cpu.flag(0)) & 255
    cpu.setflags(C=v >> 7)
    cpu.zn(r)
    return r


def _rrcf(cpu, v):
    r = (v >> 1) | (cpu.flag(0) << 7)
    cpu.setflags(C=v & 1)
    cpu.zn(r)
    return r


def mk_w_f(fn):
    def h(cpu, inst):
        f, d, a = get_f_d_a(inst)
        ea = cpu.ea(f, a)
        v = cpu.read(ea)
        r = fn(cpu, v, cpu.W)
        dest(cpu, d, ea, r)
    return h


def _addwf(cpu, f, w):
    return cpu.add(f, w)


def _addwfc(cpu, f, w):
    return cpu.add(f, w, cpu.flag(0))


def _subwf(cpu, f, w):
    return cpu.add(f, (~w) & 255, 1)


def _subwfb(cpu, f, w):
    return cpu.add(f, (~w) & 255, cpu.flag(0))


def _andwf(cpu, f, w):
    r = f & w
    cpu.zn(r)
    return r


def _iorwf(cpu, f, w):
    r = f | w
    cpu.zn(r)
    return r


def _xorwf(cpu, f, w):
    r = f ^ w
    cpu.zn(r)
    return r


def h_movwf(cpu, inst):
    f, d, a = get_f_d_a(inst)
    cpu.write(cpu.ea(f, a), cpu.W)


def h_clrf(cpu, inst):
    f, d, a = get_f_d_a(inst)
    cpu.write(cpu.ea(f, a), 0)
    cpu.setflags(Z=1, N=0)


def h_setf(cpu, inst):
    f, d, a = get_f_d_a(inst)
    cpu.write(cpu.ea(f, a), 255)


def h_movlw(cpu, inst):
    cpu.W = inst.args[0]


def h_movlb(cpu, inst):
    cpu.mem[cpu.A_BSR] = inst.args[0] & 15


def h_addlw(cpu, inst):
    cpu.W = cpu.add(cpu.W, inst.args[0] & 255)


def h_sublw(cpu, inst):
    cpu.W = cpu.add(inst.args[0] & 255, (~cpu.W) & 255, 1)


def h_andlw(cpu, inst):
    cpu.W = cpu.W & inst.args[0]
    cpu.zn(cpu.W)


def h_iorlw(cpu, inst):
    cpu.W = cpu.W | inst.args[0]
    cpu.zn(cpu.W)


def h_xorlw(cpu, inst):
    cpu.W = cpu.W ^ inst.args[0]
    cpu.zn(cpu.W)


def h_mullw(cpu, inst):
    p = cpu.W * (inst.args[0] & 255)
    cpu.mem[cpu.A_PRODL], cpu.mem[cpu.A_PRODH] = p & 255, p >> 8


def h_nop(cpu, inst):
    pass


def bitop(kind):
    def h(cpu, inst):
        f, bit, a = inst.args[0], inst.args[1], "c"
        if len(inst.args) > 2:
            a = inst.args[2] if inst.args[2] in ("b", "c") else "c"
        ea = cpu.ea(f, a)
        v = cpu.read(ea)
        if kind == "bcf":
            cpu.write(ea, v & ~(1 << bit))
        elif kind == "bsf":
            cpu.write(ea, v | (1 << bit))
        elif kind == "btfss":
            if (v >> bit) & 1:
                cpu.skip()
        elif kind == "btfsc":
            if not (v >> bit) & 1:
                cpu.skip()
        elif kind == "btg":
            cpu.write(ea, v ^ (1 << bit))
    return h


def h_decfsz(cpu, inst):
    f, d, a = get_f_d_a(inst)
    ea = cpu.ea(f, a)
    r = (cpu.read(ea) - 1) & 255
    dest(cpu, d, ea, r)
    if r == 0:
        cpu.skip()


def h_infsnz(cpu, inst):
    f, d, a = get_f_d_a(inst)
    ea = cpu.ea(f, a)
    r = (cpu.read(ea) + 1) & 255
    dest(cpu, d, ea, r)
    if r != 0:
        cpu.skip()


def h_incfsz(cpu, inst):
    f, d, a = get_f_d_a(inst)
    ea = cpu.ea(f, a)
    r = (cpu.read(ea) + 1) & 255
    dest(cpu, d, ea, r)
    if r == 0:
        cpu.skip()


def h_dcfsnz(cpu, inst):
    f, d, a = get_f_d_a(inst)
    ea = cpu.ea(f, a)
    r = (cpu.read(ea) - 1) & 255
    dest(cpu, d, ea, r)
    if r != 0:
        cpu.skip()


def branch(cond):
    def h(cpu, inst):
        if cond(cpu):
            cpu.pc = inst.args[0]
            cpu.cycles += 1
    return h


def h_bra(cpu, inst):
    cpu.pc = inst.args[0]
    cpu.cycles += 1


def h_goto(cpu, inst):
    cpu.pc = inst.args[0]
    cpu.cycles += 1


def h_call(cpu, inst):
    cpu.stack.append(cpu.pc)
    cpu.pc = inst.args[0]
    cpu.cycles += 1


def h_return(cpu, inst):
    cpu.pc = cpu.stack.pop()
    cpu.cycles += 1


def h_movff(cpu, inst):
    cpu.write(inst.args[1], cpu.read(inst.args[0]))
    cpu.cycles += 1


def h_lfsr(cpu, inst):
    cpu.setfsr(inst.args[0], inst.args[1])
    cpu.cycles += 1


def h_tblrd(cpu, inst):
    p = cpu.mem[cpu.A_TBLL] | cpu.mem[cpu.A_TBLH] << 8 | cpu.mem[cpu.A_TBLU] << 16
    cpu.mem[cpu.A_TAB] = cpu.pmem[p]
    if "+" in inst.op:
        p += 1
        cpu.mem[cpu.A_TBLL], cpu.mem[cpu.A_TBLH], cpu.mem[cpu.A_TBLU] = p & 255, (p >> 8) & 255, (p >> 16) & 255
    cpu.cycles += 1


HANDLERS = {
    "movlw": h_movlw, "movwf": h_movwf, "clrf": h_clrf, "setf": h_setf, "movlb": h_movlb, "nop": h_nop,
    "movf": mk_alu_f(_movf), "incf": mk_alu_f(_incf), "decf": mk_alu_f(_decf), "comf": mk_alu_f(_comf),
    "rrncf": mk_alu_f(_rrncf), "rlncf": mk_alu_f(_rlncf), "swapf": mk_alu_f(_swapf), "rlcf": mk_alu_f(_rlcf),
    "rrcf": mk_alu_f(_rrcf),
    "addwf": mk_w_f(_addwf), "addwfc": mk_w_f(_addwfc), "subwf": mk_w_f(_subwf), "subwfb": mk_w_f(_subwfb),
    "andwf": mk_w_f(_andwf), "iorwf": mk_w_f(_iorwf), "xorwf": mk_w_f(_xorwf),
    "addlw": h_addlw, "sublw": h_sublw, "andlw": h_andlw, "iorlw": h_iorlw, "xorlw": h_xorlw, "mullw": h_mullw,
    "bcf": bitop("bcf"), "bsf": bitop("bsf"), "btfss": bitop("btfss"), "btfsc": bitop("btfsc"), "btg": bitop("btg"),
    "decfsz": h_decfsz, "infsnz": h_infsnz, "incfsz": h_incfsz, "dcfsnz": h_dcfsnz,
    "bra": h_bra, "goto": h_goto, "rcall": h_call, "call": h_call, "return": h_return,
    "bz": branch(lambda c: c.flag(2)), "bnz": branch(lambda c: not c.flag(2)),
    "bc": branch(lambda c: c.flag(0)), "bnc": branch(lambda c: not c.flag(0)),
    "bn": branch(lambda c: c.flag(4)), "bnn": branch(lambda c: not c.flag(4)),
    "bov": branch(lambda c: c.flag(3)), "bnov": branch(lambda c: not c.flag(3)),
    "movff": h_movff, "lfsr": h_lfsr, "tblrd*+": h_tblrd, "tblrd*": h_tblrd,
}


# ----------------------------------------------------------------------------------------------------------------
# I2C client(s) on the bus, with a transcript and fault injection
# ----------------------------------------------------------------------------------------------------------------
class Bus:
    """A bus with one MCP7940N-like client at 7-bit address 0x6F: 96 registers, pointer set by the first byte after
    the address+W, auto-increment on reads and writes. Anything else is not acknowledged.

    faults: list of dicts {txn, byte, kind}; txn counts Starts from 1, byte counts bytes the master sent in that
    transaction from 0 (the address); kind is 'nack', 'collision' or 'stick' (the client holds SCL low from then on)."""

    def __init__(self):
        self.regs = bytearray((i * 7 + 3) & 255 for i in range(96))
        self.ptr = 0
        self.log = []
        self.scl_stuck = False
        self.faults = []
        self.txn = 0
        self.byte_no = 0
        self.mode = None

    def start(self):
        self.txn += 1
        self.log.append("S")
        self.byte_no = 0
        self.mode = "addr"

    def restart(self):
        self.log.append("Sr")
        self.mode = "addr"

    def stop(self):
        self.log.append("P")
        self.mode = None

    def fault(self, n):
        for f in self.faults:
            if f["txn"] == self.txn and f["byte"] == n and not f.get("done"):
                f["done"] = True
                return f["kind"]
        return None

    def byte_out(self, b):
        """Master sends b. Returns 'ack', 'nack' or 'collision'."""
        n = self.byte_no
        self.byte_no += 1
        k = self.fault(n)
        if k == "collision":
            self.log.append(f"W{b:02X}!")
            return "collision"
        if k == "stick":
            self.scl_stuck = True
            self.log.append(f"W{b:02X}~")
        ack = True
        if self.mode == "addr":
            if (b >> 1) != 0x6F:
                ack = False
            else:
                self.mode = "rd" if b & 1 else "wr-ptr"
        elif self.mode == "wr-ptr":
            self.ptr = b
            self.mode = "wr-data"
        elif self.mode == "wr-data":
            if self.ptr < 96:
                self.regs[self.ptr] = b
            self.ptr += 1
        else:
            ack = False
        if k == "nack":
            ack = False
        if k != "stick":
            self.log.append(f"W{b:02X}{'+' if ack else '-'}")
        return "ack" if ack else "nack"

    def byte_in(self):
        k = self.fault(self.byte_no)
        self.byte_no += 1
        if k == "stick":
            self.scl_stuck = True
        v = self.regs[self.ptr] if self.ptr < 96 else 0xFF
        self.ptr += 1
        self.log.append(f"R{v:02X}")
        return v

    def master_ack(self, ack):
        self.log.append("+" if ack else "-")


# ----------------------------------------------------------------------------------------------------------------
# I2C1 host peripheral (DS40002214G chapter 36), host mode, 7-bit addressing
# ----------------------------------------------------------------------------------------------------------------
ASSUMPTIONS = {
    "A1": "Writing I2C1TXB when TXBE = 1 clears TXBE at once (TXBE = 0 on the next instruction).",
    "A2": "Start with ABD = 1: the first TXB write starts the transfer after the bus-free time (BFRE); the address moves "
          "into the shift register one SCL period after the Start, which sets TXBE again and MMA = 1.",
    "A3": "At the 8th falling edge of a transmitted byte, if TXBE = 1 and I2C1CNT != 0 the host sets MDR and stretches "
          "SCL until TXB is written; otherwise it goes on to the 9th clock [36.4.2.7.1 steps 4, 8; CON0 MDR].",
    "A4": "At the 9th falling edge after a good ACK a pending TXB byte moves into the shift register and I2C1CNT "
          "decrements; with nothing pending and CNT = 0 the host sends the Stop, or (RSEN = 1) sets MDR and waits "
          "[36.4.2.7.1 steps 5-6, 8; CON0 RSEN; Figure 36-37].",
    "A5": "On a NACK from the client: RSEN = 0 sends the Stop by itself; RSEN = 1 sets MDR (CNT = 0 or ACKSTAT = 1) and "
          "waits. NACKIF is set [CON0 RSEN; ERR NACKIF; 36.4.2.7.1 step 5].",
    "A6": "At the MDR pause for a Restart, I2C1CNT may be written, and a write to TXB issues the Restart and sends TXB "
          "as the next address [CON0 S/MDR; 36.3.12; 36.4.2.5].",
    "A7": "The read address written at the MDR pause has left TXB (TXBE = 1) when the Restart is done: the shift "
          "register is loaded from TXB after the Restart, as after a Start [36.4.2.3, 36.4.2.5].",
    "A8": "RSEN may be cleared once the Restart is done; the module then Stops by itself after the last byte, and if it is "
          "not cleared the module pauses (MDR) after the last byte and P ends the transfer [CON0 RSEN; 36.3.12].",
    "A9": "Host receive: byte -> RXB, RXBF = 1 and CNT decrements at the 8th edge; if RXBF is still 1 at the 7th edge of the "
          "next byte the host sets MDR and stretches until RXB is read; the 9th clock sends ACKDT while CNT != 0 and "
          "ACKCNT when CNT = 0, and then the Stop (RSEN = 0) [36.4.2.7.2 steps 6-8].",
    "A10": "Whether the host's own not-acknowledge of the last byte sets NACKIF is not stated: the model sets it "
           "(worst case for the driver, which ignores NACKIF after the first received byte).",
    "A11": "P = 1 while MMA = 1 ends the transfer with a Stop within about one SCL period and clears MDR "
           "[CON1 P; Errata 1.3.3].",
    "A12": "EN = 0 resets the state machine (MMA = 0, MDR = 0, TXBE = 1, RXBF = 0); on EN = 1 the start/stop flags may "
           "be set (errata 1.3.2) within 250 ns + 6 cycles, modelled as set 3 cycles after enable.",
    "A13": "CLRBF empties both buffers (TXBE = 1, RXBF = 0) and also cancels a start that is waiting for BFRE.",
    "A15": "RSEN must stay 1 until the Restart has been issued (a Restart needs RSEN = 1 [36.4.2.5]); the model flags a "
           "clear before then.",
    "A14": "BFRE becomes 1 BFRET pulses (8 prescaled clocks for BFRET = 00) after the module is enabled or a Stop, "
           "unless a client holds a line low.",
}


class I2C1:
    NAMES = ["I2C1CON0", "I2C1CON1", "I2C1CON2", "I2C1STAT0", "I2C1STAT1", "I2C1PIR", "I2C1ERR", "I2C1CNTL", "I2C1CNTH",
             "I2C1TXB", "I2C1RXB", "I2C1BAUD", "I2C1CLK", "I2C1PIE", "I2C1BTO", "I2C1BTOC", "I2C1ADB1", "I2C1ADB0"]

    def __init__(self, cpu, bus):
        self.cpu, self.bus = cpu, bus
        self.a = {n: cpu.sfr[n] for n in self.NAMES if n in cpu.sfr}
        self.by_addr = {v: k for k, v in self.a.items()}
        self.reset_all()
        self.heap, self.seq, self.epoch = [], 0, 0
        self.violations = []
        self.events = []
        self.max_txbe_wait = 0

    def addresses(self):
        return list(self.by_addr)

    def reset_all(self):
        self.en = self.rsen = self.s = 0
        self.mode = 0
        self.ackcnt = self.ackdt = self.ackstat = self.p = 0
        self.con2 = 0
        self.baud = self.clk = 0
        self.cnt = 0
        self.txb = self.rxb = 0
        self.txbe, self.rxbf, self.txwe, self.rxre = 1, 0, 0, 0
        self.mdr = self.mma = 0
        self.pir = dict(cntif=0, pcif=0, rscif=0, scif=0)
        self.err = dict(nackif=0, bclif=0, btoif=0)
        self.pie = 0
        self.state = "idle"
        self.bfre_at = None
        self.shift = 0
        self.is_addr = False
        self.rw = 0
        self.stalled_since = None

    # --- timing ---------------------------------------------------------------------------------------------------
    @property
    def now(self):
        return self.cpu.cycles

    @property
    def T(self):
        """One SCL period in instruction cycles: I2CxCLK = FOSC/4 is one tick per cycle; FME = 0 divides the
        prescaled clock (BAUD + 1) by 5, FME = 1 by 4 [36.4.2.2]."""
        assert self.clk == 0, "model supports I2CxCLK = FOSC/4 only"
        return (4 if self.con2 & 0x20 else 5) * (self.baud + 1)

    @property
    def pre(self):
        return self.baud + 1

    def sched(self, t, fn):
        self.seq += 1
        heapq.heappush(self.heap, (t, self.seq, self.epoch, fn))

    def tick(self, now):
        while self.heap and self.heap[0][0] <= now:
            t, _, ep, fn = heapq.heappop(self.heap)
            if ep == self.epoch:
                fn(t)

    def abort(self):
        self.epoch += 1

    def bfre(self):
        return int(self.en == 1 and self.bfre_at is not None and self.now >= self.bfre_at and not self.bus.scl_stuck
                   and self.mma == 0)

    # --- register file --------------------------------------------------------------------------------------------
    def read(self, addr):
        n = self.by_addr[addr]
        if n == "I2C1CON0":
            return self.en << 7 | self.rsen << 6 | self.s << 5 | self.mdr << 3 | self.mode
        if n == "I2C1CON1":
            return self.ackcnt << 7 | self.ackdt << 6 | self.ackstat << 5 | self.p << 3
        if n == "I2C1CON2":
            return self.con2
        if n == "I2C1STAT0":
            return self.bfre() << 7 | self.mma << 5
        if n == "I2C1STAT1":
            return self.txwe << 7 | self.txbe << 5 | self.rxre << 3 | self.rxbf
        if n == "I2C1PIR":
            q = self.pir
            return q["cntif"] << 7 | q["pcif"] << 2 | q["rscif"] << 1 | q["scif"]
        if n == "I2C1ERR":
            e = self.err
            return e["btoif"] << 6 | e["bclif"] << 5 | e["nackif"] << 4
        if n == "I2C1CNTL":
            return self.cnt & 255
        if n == "I2C1CNTH":
            return self.cnt >> 8
        if n == "I2C1TXB":
            return self.txb
        if n == "I2C1RXB":
            if self.rxbf:
                v = self.rxb
                self.rxbf = 0
                if self.state == "stall_rx":
                    self.mdr = 0
                    self.state = "rx"
                    self.sched(self.now + self.T, self.rx_edge8)
                return v
            self.rxre = 1
            self.err["nackif"] = 1
            self.violations.append("read of I2C1RXB when empty (RXRE)")
            return self.rxb
        if n == "I2C1BAUD":
            return self.baud
        if n == "I2C1CLK":
            return self.clk
        return 0

    def write(self, addr, v):
        n = self.by_addr[addr]
        if n == "I2C1CON0":
            en = v >> 7 & 1
            if self.state == "restarting" and not (v >> 6 & 1):
                self.violations.append("RSEN cleared before the Restart was done")  # [A15]
            self.rsen = v >> 6 & 1
            self.mode = v & 7
            if en and not self.en:
                self.en = 1
                self.bfre_at = self.now + 8 * self.pre  # [A14]
                self.sched(self.now + 3, self.spurious_flags)  # [A12]
            elif self.en and not en:
                self.en = 0
                self.abort()
                self.state = "idle"
                self.mma = self.mdr = 0
                self.txbe, self.rxbf = 1, 0
                self.bfre_at = None
            if v >> 5 & 1 and self.mma and self.state == "pause_restart":
                self.do_restart()
        elif n == "I2C1CON1":
            self.ackcnt = v >> 7 & 1
            self.ackdt = v >> 6 & 1
            if v >> 3 & 1 and self.mma:
                self.p = 1
                self.abort()
                self.mdr = 0
                self.state = "stopping"
                self.sched(self.now + self.T, self.stop_done)  # [A11]
        elif n == "I2C1CON2":
            self.con2 = v
        elif n == "I2C1STAT1":
            if v & 0x80 == 0:
                self.txwe = 0
            if v & 0x08 == 0:
                self.rxre = 0
            if v & 4:  # CLRBF [A13]
                self.txbe, self.rxbf = 1, 0
                if self.state == "start_pending":
                    self.abort()
                    self.state = "idle"
        elif n == "I2C1PIR":
            self.pir = dict(cntif=v >> 7 & 1, pcif=v >> 2 & 1, rscif=v >> 1 & 1, scif=v & 1)
        elif n == "I2C1ERR":
            self.err = dict(btoif=v >> 6 & 1, bclif=v >> 5 & 1, nackif=v >> 4 & 1)
        elif n == "I2C1CNTL":
            self.check_cnt_write()
            self.cnt = (self.cnt & 0xFF00) | v
        elif n == "I2C1CNTH":
            self.check_cnt_write()
            self.cnt = (self.cnt & 0xFF) | v << 8
        elif n == "I2C1BAUD":
            if self.mma and not self.mdr:
                self.violations.append("I2C1BAUD written while the host is active")
            self.baud = v
        elif n == "I2C1CLK":
            self.clk = v
        elif n == "I2C1TXB":
            self.write_txb(v)

    def check_cnt_write(self):
        # 36.5.11: write only when idle (MMA = 0) or paused (CSTR or MDR = 1)
        if self.mma and not self.mdr:
            self.violations.append("I2C1CNT written while the host is active and not paused")

    def spurious_flags(self, t):
        self.pir["scif"] = 1
        self.pir["pcif"] = 1

    # --- transmit side ---------------------------------------------------------------------------------------------
    def write_txb(self, v):
        if not self.txbe:
            self.txwe = 1
            self.err["nackif"] = 1
            self.violations.append("I2C1TXB written while full (TXWE)")  # driver must never do this
            return
        self.txb = v
        self.txbe = 0  # [A1]
        if not self.en or self.mode != 4:
            return
        if self.state == "idle" and self.mma == 0:
            self.state = "start_pending"
            t = self.now
            if self.bfre_at is not None and self.bfre_at > t:
                t = self.bfre_at
            self.sched(t, self.try_start)
        elif self.state == "stall_tx":
            self.mdr = 0
            self.stalled_since = None
            self.state = "tx"
            self.sched(self.now + self.T, self.tx_edge9)
        elif self.state == "pause_restart":
            self.do_restart()
        # otherwise the byte waits in TXB until the shift register is free

    def try_start(self, t):
        if self.state != "start_pending":
            return
        if self.bus.scl_stuck:
            self.sched(t + 64, self.try_start)  # a stuck line keeps the bus busy (BFRE stays 0)
            return
        self.mma = 1  # [A2]
        self.pir["scif"] = 1
        self.bus.start()
        self.state = "starting"
        self.is_addr = True
        self.sched(t + self.T, self.load_shift)

    def do_restart(self):
        t = self.now
        self.mdr = 0
        self.s = 1
        self.state = "restarting"
        self.is_addr = True
        self.bus.restart()
        self.sched(t + self.T, lambda tt: self.pir.__setitem__("rscif", 1))  # [A7]
        self.sched(t + 2 * self.T, self.load_shift)

    def load_shift(self, t):
        if self.bus.scl_stuck:
            self.sched(t + 64, self.load_shift)
            return
        self.s = 0
        self.shift = self.txb
        self.txbe = 1
        self.rw = self.shift & 1 if self.is_addr else self.rw
        self.state = "tx"
        self.sched(t + 8 * self.T, self.tx_edge8)

    def tx_edge8(self, t):
        if self.bus.scl_stuck:
            self.sched(t + 64, self.tx_edge8)
            return
        # [A3] the TX data request is for host transmission; after a read address the host receives instead
        if self.txbe and self.cnt != 0 and not (self.is_addr and self.rw):
            self.mdr = 1
            self.state = "stall_tx"
            self.stalled_since = t
            return
        self.sched(t + self.T, self.tx_edge9)

    def tx_edge9(self, t):
        if self.bus.scl_stuck:
            self.sched(t + 64, self.tx_edge9)
            return
        res = self.bus.byte_out(self.shift)
        if res == "collision":
            self.collision()
            return
        ack = res == "ack"
        self.ackstat = 0 if ack else 1
        if not ack:
            self.err["nackif"] = 1
            if self.rsen:  # [A5]
                self.mdr = 1
                self.state = "pause_restart"
            else:
                self.begin_stop(t)
            return
        was_addr = self.is_addr
        self.is_addr = False
        if was_addr and self.rw:  # read: switch to receive
            self.state = "rx"
            self.sched(t + 7 * self.T, self.rx_edge7)
            return
        if not self.txbe:  # [A4]: pending byte moves, CNT decrements
            self.shift = self.txb
            self.txbe = 1
            if self.cnt:
                self.cnt -= 1
            self.state = "tx"
            self.sched(t + 8 * self.T, self.tx_edge8)
            return
        if self.cnt == 0:
            self.pir["cntif"] = 1
            if self.rsen:
                self.mdr = 1
                self.state = "pause_restart"
            else:
                self.begin_stop(t)
            return
        self.mdr = 1  # CNT != 0 and nothing to send: wait for data (should have stalled at edge 8)
        self.state = "stall_tx"

    def begin_stop(self, t):
        self.state = "stopping"
        self.sched(t + self.T, self.stop_done)

    def stop_done(self, t):
        if self.bus.scl_stuck:
            self.sched(t + 64, self.stop_done)
            return
        self.mma = 0
        self.mdr = 0
        self.p = 0
        self.s = 0
        self.pir["pcif"] = 1
        self.bus.stop()
        self.state = "idle"
        self.bfre_at = t + 8 * self.pre  # [A14]

    def collision(self):
        self.err["bclif"] = 1
        self.mma = 0
        self.mdr = 0
        self.abort()
        self.state = "idle"
        self.bfre_at = self.now + 8 * self.pre

    # --- receive side ----------------------------------------------------------------------------------------------
    def rx_edge7(self, t):
        if self.bus.scl_stuck:
            self.sched(t + 64, self.rx_edge7)
            return
        if self.rxbf:  # [A9]
            self.mdr = 1
            self.state = "stall_rx"
            return
        self.sched(t + self.T, self.rx_edge8)

    def rx_edge8(self, t):
        if self.bus.scl_stuck:
            self.sched(t + 64, self.rx_edge8)
            return
        self.rxb = self.bus.byte_in()
        self.rxbf = 1
        if self.cnt:
            self.cnt -= 1
        self.sched(t + self.T, self.rx_edge9)

    def rx_edge9(self, t):
        if self.bus.scl_stuck:
            self.sched(t + 64, self.rx_edge9)
            return
        nack = self.ackcnt if self.cnt == 0 else self.ackdt  # [A9]
        self.bus.master_ack(not nack)
        if nack:
            self.err["nackif"] = 1  # [A10]
        if self.cnt == 0 or nack:
            self.pir["cntif"] = 1
            # [A9] with the count at 0 RSEN decides: 1 = pause for a Restart (also after the not acknowledge of the last
            # byte, CON0 RSEN), 0 = Stop. A not acknowledge before the count ends is a Stop (36.4.2.7.2 step 8).
            if self.rsen and self.cnt == 0:
                self.mdr = 1
                self.state = "pause_restart"
            else:
                self.begin_stop(t)
            return
        self.state = "rx"
        self.sched(t + 7 * self.T, self.rx_edge7)
