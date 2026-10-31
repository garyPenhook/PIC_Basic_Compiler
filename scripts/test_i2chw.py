"""Regression for the PIC18-Q41 hardware I2C driver (lib/i2c.bas with `#option I2c = Hardware`).

Builds test programs with the real compiler and library, runs the generated assembly on picsim.py (an instruction-level
PIC18 simulator with a model of the I2C1 host peripheral and a simulated MCP7940N-like client) and checks statuses, data,
register setup and the exact bus transcript, for several clock / bus speed combinations, for faults (a not acknowledge on
each byte position, a bus collision, a client holding SCL) and for the Rtcc driver on top.

MDB has no I2C model (SimPeripheralSupport.csv), so this is the only place the transfer routines run. The model is written
from DS40002214G chapter 36; every point where the data sheet is silent or ambiguous is an assumption, listed by
`test_i2chw.py --assumptions`: those are what has to be confirmed on silicon.

Usage: test_i2chw.py [--assumptions]      environment: BASIL (the compiler), BASIL_LIB (the lib folder), BASIL_FLAGS (e.g. -O0)
"""
import atexit, os, shutil, subprocess, sys, tempfile, textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from picsim import Bus, CPU, I2C1, ASSUMPTIONS


def default_basil():
    for kind in ("debug", "release"):
        p = os.path.join(ROOT, "target", kind, "basil")
        if os.path.exists(p):
            return p
    return "basil"


BASIL = os.environ.get("BASIL") or default_basil()
LIB = os.environ.get("BASIL_LIB") or os.path.join(ROOT, "lib")
DEV = os.path.join(ROOT, "devices", "18F16Q41.toml")
WORK = tempfile.mkdtemp(prefix="i2chw-")
atexit.register(shutil.rmtree, WORK, True)
fails = []
checks = 0


def check(name, got, want):
    global checks
    checks += 1
    if got != want:
        fails.append(f"{name}: got {got!r}, want {want!r}")


def build(src, name):
    path = os.path.join(WORK, name + ".bas")
    open(path, "w").write(src)
    r = subprocess.run([BASIL, path, "-L", LIB, "-S", "--keep-vars"] + os.environ.get("BASIL_FLAGS", "").split(), capture_output=True, text=True)
    if r.returncode != 0:
        fails.append(f"{name}: compile failed\n{r.stderr}")
        return None
    return path[:-4] + ".S"


def run(asm, setup=None, max_instr=40_000_000):
    bus = Bus()
    if setup:
        setup(bus)
    holder = {}

    def pf(cpu):
        holder["p"] = I2C1(cpu, bus)
        return holder["p"]

    cpu = CPU(asm, DEV, pf)
    done = cpu.run(max_instr)
    return cpu, bus, holder["p"], done


def var(cpu, sym, size=1):
    a = cpu.syms[sym]
    return sum(cpu.mem[a + i] << (8 * i) for i in range(size))


# --- expected transcripts built from the intended protocol (not from the model's output) -----------------------------
def t_probe(a, ack=True):
    return ["S", f"W{a << 1:02X}{'+' if ack else '-'}", "P"]


def t_write(a, reg, data):
    return ["S", f"W{a << 1:02X}+", f"W{reg:02X}+"] + [f"W{d:02X}+" for d in data] + ["P"]


def t_read(a, reg, vals):
    t = ["S", f"W{a << 1:02X}+", f"W{reg:02X}+", "Sr", f"W{a << 1 | 1:02X}+"]
    for i, v in enumerate(vals):
        t += [f"R{v:02X}", "+" if i < len(vals) - 1 else "-"]
    return t + ["P"]


def reg(i):  # initial client register i
    return (i * 7 + 3) & 255


# ================================================================================================================
# 1. the whole API, at several clock / bus speed combinations
# ================================================================================================================
API = textwrap.dedent("""\
    Program Ih
    Device = 18F16Q41
    Clock = {CLOCK}
    Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
    #option I2c = Hardware
    Include "i2c"
    Dim uninitR As Byte
    Dim uninitW As Byte
    Dim uninitP As Byte
    Dim badA As Byte
    Dim badB As Byte
    Dim badC As Byte
    Dim badD As Byte
    Dim badE As Byte
    Dim okInit As Byte
    Dim probeOk As Byte
    Dim probeNo As Byte
    Dim rd7 As Byte
    Dim d0 As Byte
    Dim d1 As Byte
    Dim d2 As Byte
    Dim d3 As Byte
    Dim d4 As Byte
    Dim d5 As Byte
    Dim d6 As Byte
    Dim wr3 As Byte
    Dim rd3 As Byte
    Dim e0 As Byte
    Dim e1 As Byte
    Dim e2 As Byte
    Dim rd1 As Byte
    Dim f0 As Byte
    Dim rd8 As Byte
    Dim g0 As Byte
    Dim g7 As Byte
    Dim rdN0 As Byte
    Dim rdN9 As Byte
    Dim wrN0 As Byte
    Dim wrN9 As Byte
    Dim rdAbs As Byte
    Dim wrAbs As Byte
    Dim probeAfter As Byte
    Dim wrOne As Byte
    Dim rdOne As Byte
    Dim stAfter As Byte
    Dim offR As Byte
    uninitR = I2cReadRegs(111, 0, 1)
    uninitW = I2cWriteRegs(111, 0, 1)
    uninitP = I2cProbe(111)
    badA = I2cInit({HZ}, 3, 17)
    badB = I2cInit({HZ}, 16, 16)
    badC = I2cInit(0, 16, 17)
    badD = I2cInit(500000, 16, 17)
    badE = I2cInit(100, 16, 17)
    okInit = I2cInit({HZ}, 16, 17)
    probeOk = I2cProbe(111)
    probeNo = I2cProbe(80)
    rd7 = I2cReadRegs(111, 0, 7)
    d0 = I2cBuf(0)
    d1 = I2cBuf(1)
    d2 = I2cBuf(2)
    d3 = I2cBuf(3)
    d4 = I2cBuf(4)
    d5 = I2cBuf(5)
    d6 = I2cBuf(6)
    I2cBuf(0) = 170
    I2cBuf(1) = 187
    I2cBuf(2) = 204
    wr3 = I2cWriteRegs(111, 8, 3)
    rd3 = I2cReadRegs(111, 8, 3)
    e0 = I2cBuf(0)
    e1 = I2cBuf(1)
    e2 = I2cBuf(2)
    rd1 = I2cReadRegs(111, 40, 1)
    f0 = I2cBuf(0)
    rd8 = I2cReadRegs(111, 16, 8)
    g0 = I2cBuf(0)
    g7 = I2cBuf(7)
    rdN0 = I2cReadRegs(111, 0, 0)
    rdN9 = I2cReadRegs(111, 0, 9)
    wrN0 = I2cWriteRegs(111, 0, 0)
    wrN9 = I2cWriteRegs(111, 0, 9)
    rdAbs = I2cReadRegs(80, 0, 2)
    wrAbs = I2cWriteRegs(80, 0, 1)
    probeAfter = I2cProbe(111)
    wrOne = I2cWriteReg(111, 20, 99)
    rdOne = I2cReadReg(111, 20)
    stAfter = I2cStatus()
    I2cOff(16, 17)
    offR = I2cReadRegs(111, 0, 1)
    """)

API_WANT = dict(uninitR=4, uninitW=4, uninitP=4, badA=0, badB=0, badC=0, badD=0, badE=0, okInit=1, probeOk=0, probeNo=3,
                rd7=0, d0=reg(0), d1=reg(1), d2=reg(2), d3=reg(3), d4=reg(4), d5=reg(5), d6=reg(6), wr3=0, rd3=0,
                e0=170, e1=187, e2=204, rd1=0, f0=reg(40), rd8=0, g0=reg(16), g7=reg(23), rdN0=5, rdN9=5, wrN0=5,
                wrN9=5, rdAbs=3, wrAbs=3, probeAfter=0, wrOne=0, rdOne=99, stAfter=0, offR=4)

API_LOG = t_probe(0x6F) + t_probe(0x50, False) + t_read(0x6F, 0, [reg(i) for i in range(7)]) \
    + t_write(0x6F, 8, [170, 187, 204]) + t_read(0x6F, 8, [170, 187, 204]) + t_read(0x6F, 40, [reg(40)]) \
    + t_read(0x6F, 16, [reg(16 + i) for i in range(8)]) + ["S", "WA0-", "P"] + ["S", "WA0-", "P"] \
    + t_probe(0x6F) + t_write(0x6F, 20, [99]) + t_read(0x6F, 20, [99])
# nothing is sent before I2cInit

for clock, hz in ((64, 100000), (64, 400000), (32, 100000), (8, 100000), (8, 400000), (4, 400000), (1, 10000)):
    name = f"api_{clock}_{hz}"
    asm = build(API.replace("{CLOCK}", str(clock)).replace("{HZ}", str(hz)), name)
    if not asm:
        continue
    cpu, bus, p, done = run(asm)
    check(name + " halted", done, True)
    for k, want in API_WANT.items():
        check(f"{name} {k}", var(cpu, "IH_" + k.upper()), want)
    check(name + " transcript", bus.log, API_LOG)
    check(name + " violations", p.violations, [])
    check(name + " client regs", [bus.regs[8], bus.regs[9], bus.regs[10], bus.regs[20]], [170, 187, 204, 99])

# ================================================================================================================
# 2. register setup of I2cInit (bit rate, clock source, pins)
# ================================================================================================================
INIT = textwrap.dedent("""\
    Program Ii
    Device = 18F16Q41
    Clock = {CLOCK}
    Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
    #option I2c = Hardware
    Include "i2c"
    Dim r As Byte
    ANSELB = 255
    ANSELC = 255
    ODCONB = 0
    ODCONC = 0
    r = I2cInit({HZ}, {SCL}, {SDA})
    """)
# (clock MHz, hz, scl, sda, expected BAUD or None when refused)
INITS = [(64, 100000, 16, 17, 31), (64, 400000, 16, 17, 7), (8, 100000, 16, 17, 3), (8, 400000, 16, 17, 0),
         (32, 100000, 16, 17, 15), (4, 100000, 16, 17, 1), (1, 10000, 16, 17, 4), (16, 400000, 16, 17, 1),
         (64, 12500, 16, 17, 255), (64, 12000, 16, 17, None), (64, 100000, 14, 12, 31), (64, 100000, 21, 20, 31),
         (64, 100000, 0, 1, 31), (64, 100000, 8, 17, None), (64, 100000, 3, 17, None)]
for clock, hz, scl, sda, baud in INITS:
    name = f"init_{clock}_{hz}_{scl}_{sda}"
    asm = build(INIT.replace("{CLOCK}", str(clock)).replace("{HZ}", str(hz)).replace("{SCL}", str(scl)).replace("{SDA}", str(sda)), name)
    if not asm:
        continue
    cpu, bus, p, done = run(asm)
    check(name + " halted", done, True)
    S = cpu.sfr
    r = var(cpu, "II_R")
    if baud is None:
        check(name + " refused", r, 0)
        check(name + " module left off", p.en, 0)
        continue
    check(name + " accepted", r, 1)
    check(name + " BAUD", p.baud, baud)
    fclk = clock * 1_000_000 / 4
    real = fclk / (baud + 1) / 5
    check(name + " SCL <= requested", real <= hz + 1e-9, True)
    check(name + " SCL not needlessly slow", baud == 0 or fclk / (baud) / 5 > hz, True)
    check(name + " CLK = FOSC/4", p.clk, 0)
    check(name + " CON2 = ABD", p.con2, 0x10)
    check(name + " host 7-bit", (p.en, p.mode, p.rsen), (1, 4, 0))
    for pin, code, ppsin in ((scl, 0x21, "I2C1SCLPPS"), (sda, 0x22, "I2C1SDAPPS")):
        port, bit = pin >> 3, pin & 7
        out = {0: "RA", 1: "RB", 2: "RC"}[port] + f"{bit}PPS"
        check(f"{name} {out}", cpu.mem[S[out]], code)
        check(f"{name} {ppsin}", cpu.mem[S[ppsin]], pin)
        check(f"{name} ANSEL bit clear {pin}", (cpu.mem[S[{0: 'ANSELA', 1: 'ANSELB', 2: 'ANSELC'}[port]]] >> bit) & 1, 0)
        check(f"{name} ODCON bit set {pin}", (cpu.mem[S[{0: 'ODCONA', 1: 'ODCONB', 2: 'ODCONC'}[port]]] >> bit) & 1, 1)
    check(name + " flags cleared", (p.pir, p.err, p.txwe), (dict(cntif=0, pcif=0, rscif=0, scif=0), dict(nackif=0, bclif=0, btoif=0), 0))

# ---- the pins accepted: the same set as the software host (tests/exec_q41/lib_i2c_pins.bas checks the software side) -------
PINS = textwrap.dedent("""\
    Program Lq
    Device = 18F16Q41
    Clock = 64
    Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
    #option I2c = Hardware
    Include "i2c"
    Dim mskS As LongWord
    Dim mskD As LongWord
    Dim p As Byte
    Dim r As Byte
    mskS = 0
    mskD = 0
    For p = 0 To 31
        r = I2cInit(100000, p, 17)
        If r = 1 Then
            mskS = mskS Or (LongWord(1) << p)
        End If
        r = I2cInit(100000, 16, p)
        If r = 1 Then
            mskD = mskD Or (LongWord(1) << p)
        End If
    Next
    """)
valid = sum(1 << q for q in (0, 1, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23))
asm = build(PINS, "pins")
if asm:
    cpu, bus, p, done = run(asm)
    check("pins halted", done, True)
    check("pins accepted as SCL", var(cpu, "LQ_MSKS", 4), valid & ~(1 << 17))
    check("pins accepted as SDA", var(cpu, "LQ_MSKD", 4), valid & ~(1 << 16))

# ---- I2cOff takes back what I2cInit set, with the pins it remembers (the arguments are not looked at) ----------------------------------------
OFF = textwrap.dedent("""\
    Program Lo
    Device = 18F16Q41
    Clock = 64
    Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
    #option I2c = Hardware
    Include "i2c"
    Dim a As Byte
    Dim b As Byte
    Dim c As Byte
    Dim d As Byte
    Dim fl As Byte
    Dim fh As Byte
    Dim gl As Byte
    Dim gh As Byte
    RA5PPS = 85
    RA4PPS = 86
    ODCONC = 0
    ODCONB = 0
    Asm
        lfsr 2, 0x7A5
    End Asm
    a = I2cInit(100000, 16, 17)
    Asm
        movff FSR2L, LO_FL
        movff FSR2H, LO_FH
    End Asm
    b = I2cProbe(111)
    I2cOff(5, 4)
    c = I2cProbe(111)
    a = I2cInit(100000, 14, 12)
    d = I2cProbe(111)
    Asm
        movff FSR2L, LO_GL
        movff FSR2H, LO_GH
    End Asm
    """)
asm = build(OFF, "off")
if asm:
    cpu, bus, p, done = run(asm)
    S = cpu.sfr
    check("off halted", done, True)
    check("RC0 / RC1 given back (LATxy drives them again)", (cpu.mem[S["RC0PPS"]], cpu.mem[S["RC1PPS"]]), (0, 0))
    check("RC0 / RC1 push-pull again", cpu.mem[S["ODCONC"]] & 3, 0)
    check("I2cOff(5, 4) did not touch the mappings of RA5 / RA4", (cpu.mem[S["RA5PPS"]], cpu.mem[S["RA4PPS"]]), (85, 86))
    check("module now on RB6 (SCL) / RB4 (SDA), open drain", (cpu.mem[S["RB6PPS"]], cpu.mem[S["RB4PPS"]], cpu.mem[S["ODCONB"]] & 0x50), (0x21, 0x22, 0x50))
    check("probe while off answers 4", var(cpu, "LO_C"), 4)
    check("probes work after init and after a new init", (var(cpu, "LO_B"), var(cpu, "LO_D")), (0, 0))
    check("FSR2 (the reentrant stack pointer) survives I2cInit", (var(cpu, "LO_FL"), var(cpu, "LO_FH")), (0xA5, 0x07))
    check("FSR2 survives I2cOff and a second I2cInit", (var(cpu, "LO_GL"), var(cpu, "LO_GH")), (0xA5, 0x07))

# ================================================================================================================
# 3. faults: one transfer is hit, the ones after it must work (or, for a stuck clock, fail without hanging)
# ================================================================================================================
FAULT = textwrap.dedent("""\
    Program Fl
    Device = 18F16Q41
    Clock = {CLOCK}
    Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
    #option I2c = Hardware
    Include "i2c"
    Dim ok As Byte
    Dim r1 As Byte
    Dim r2 As Byte
    Dim r3 As Byte
    Dim r4 As Byte
    Dim r5 As Byte
    ok = I2cInit(100000, 16, 17)
    I2cBuf(0) = 1
    I2cBuf(1) = 2
    r1 = I2cWriteRegs(111, 8, 2)
    r2 = I2cReadRegs(111, 24, 2)
    r3 = I2cProbe(111)
    r4 = I2cReadRegs(111, 0, 2)
    r5 = I2cWriteRegs(111, 12, 1)
    """)
OKW = t_write(0x6F, 8, [1, 2])
OKR = t_read(0x6F, 24, [reg(24), reg(25)])
TAIL = t_probe(0x6F) + t_read(0x6F, 0, [reg(0), reg(1)]) + t_write(0x6F, 12, [reg(0)])
# name, faults, (r1..r5), transcript of the faulted transfer (None: not compared), index of the faulted transfer
FAULTS = [
    ("no fault", [], (0, 0, 0, 0, 0), OKW + OKR + TAIL),
    ("write: NACK of the address", [dict(txn=1, byte=0, kind="nack")], (3, 0, 0, 0, 0), ["S", "WDE-", "P"], 1),
    ("write: NACK of the register byte", [dict(txn=1, byte=1, kind="nack")], (3, 0, 0, 0, 0), ["S", "WDE+", "W08-", "P"], 1),
    ("write: NACK of the first data byte", [dict(txn=1, byte=2, kind="nack")], (3, 0, 0, 0, 0), ["S", "WDE+", "W08+", "W01-", "P"], 1),
    ("write: NACK of the last data byte", [dict(txn=1, byte=3, kind="nack")], (3, 0, 0, 0, 0), ["S", "WDE+", "W08+", "W01+", "W02-", "P"], 1),
    ("read: NACK of the address", [dict(txn=2, byte=0, kind="nack")], (0, 3, 0, 0, 0), ["S", "WDE-", "P"], 2),
    ("read: NACK of the register byte", [dict(txn=2, byte=1, kind="nack")], (0, 3, 0, 0, 0), ["S", "WDE+", "W18-", "P"], 2),
    ("read: NACK of the read address", [dict(txn=2, byte=2, kind="nack")], (0, 3, 0, 0, 0), ["S", "WDE+", "W18+", "Sr", "WDF-", "P"], 2),
    ("probe: NACK", [dict(txn=3, byte=0, kind="nack")], (0, 0, 3, 0, 0), ["S", "WDE-", "P"], 3),
    ("write: collision on the register byte", [dict(txn=1, byte=1, kind="collision")], (2, 0, 0, 0, 0), ["S", "WDE+", "W08!"], 1),
    ("read: collision on the read address", [dict(txn=2, byte=2, kind="collision")], (0, 2, 0, 0, 0), ["S", "WDE+", "W18+", "Sr", "WDF!"], 2),
    ("probe: collision", [dict(txn=3, byte=0, kind="collision")], (0, 0, 2, 0, 0), ["S", "WDE!"], 3),
    ("write: clock held from the register byte", [dict(txn=1, byte=1, kind="stick")], (1, 1, 1, 1, 1), None, 1),
    ("read: clock held from the first data byte", [dict(txn=2, byte=3, kind="stick")], (0, 1, 1, 1, 1), None, 2),
]
for entry in FAULTS:
    name, faults, want, log = entry[:4]
    hit = entry[4] if len(entry) > 4 else None
    asm = build(FAULT.replace("{CLOCK}", "64"), "fault")
    if not asm:
        break

    def setup(bus, faults=faults):
        bus.faults = [dict(f) for f in faults]

    cpu, bus, p, done = run(asm, setup)
    got = tuple(var(cpu, "FL_R" + str(i)) for i in range(1, 6))
    check(f"fault [{name}] halted", done, True)
    check(f"fault [{name}] statuses", got, want)
    check(f"fault [{name}] violations", p.violations, [])
    if log is not None:
        parts = [OKW, OKR, t_probe(0x6F), t_read(0x6F, 0, [reg(0), reg(1)]), t_write(0x6F, 12, [reg(0)])]
        if hit:
            parts[hit - 1] = log
        check(f"fault [{name}] transcript", bus.log, [x for part in parts for x in part])
    else:
        check(f"fault [{name}] bounded run", cpu.icount < 40_000_000, True)

# a client that holds the clock from the very start: every transfer fails, none hangs
asm = build(FAULT.replace("{CLOCK}", "64"), "fault")
cpu, bus, p, done = run(asm, lambda b: setattr(b, "scl_stuck", True))
check("stuck from start halted", done, True)
check("stuck from start statuses", tuple(var(cpu, "FL_R" + str(i)) for i in range(1, 6)), (1, 1, 1, 1, 1))
check("stuck from start sends nothing", bus.log, [])

# ================================================================================================================
# 4. the real Rtcc library over the hardware driver
# ================================================================================================================
RT = textwrap.dedent("""\
    Program Ir
    Device = 18F16Q41
    Clock = 64
    Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
    #option I2c = Hardware
    Include "i2c"
    Include "rtcc"
    Dim ok As Byte
    Dim st As Byte
    Dim yr As Byte
    Dim mo As Byte
    Dim dy As Byte
    Dim hr As Byte
    Dim mi As Byte
    Dim se As Byte
    Dim wd As Byte
    Dim osc As Byte
    Dim ramW As Byte
    Dim ramR As Byte
    Dim ramV As Byte
    Dim eeR As Byte
    ok = I2cInit(100000, 16, 17)
    st = RtccRead()
    yr = RtccYear()
    mo = RtccMonth()
    dy = RtccDay()
    hr = RtccHour()
    mi = RtccMinute()
    se = RtccSecond()
    wd = RtccWeekday()
    If RtccOscRun() Then
        osc = 1
    Else
        osc = 0
    End If
    ramW = RtccRamWrite(5, 77)
    ramR = RtccRamRead(5, ramV)
    eeR = RtccEeRead(3, ramV)
    """)


def rtc_setup(bus):
    for i, b in enumerate((0x56, 0x34, 0x12, 0x23, 0x25, 0x10, 0x26)):  # 12:34:56 weekday 3 OSCRUN, 25 Oct 2026
        bus.regs[i] = b
    bus.regs[0] |= 0x80  # ST bit: the clock runs


asm = build(RT, "rtcc_hw")
if asm:
    cpu, bus, p, done = run(asm, rtc_setup)
    check("rtcc halted", done, True)
    got = {k: var(cpu, "IR_" + k.upper()) for k in ("ok", "st", "yr", "mo", "dy", "hr", "mi", "se", "wd", "osc", "ramW", "ramR", "ramV", "eeR")}
    check("rtcc values", got, dict(ok=1, st=0, yr=26, mo=10, dy=25, hr=12, mi=34, se=56, wd=3, osc=1, ramW=0, ramR=0, ramV=77, eeR=6))
    check("rtcc RAM write/read", (bus.regs[37], got["ramR"]), (77, 0))
    want = t_read(0x6F, 0, [0xD6, 0x34, 0x12, 0x23, 0x25, 0x10, 0x26]) + t_write(0x6F, 37, [77]) + t_read(0x6F, 37, [77])
    check("rtcc transcript start", bus.log[:len(want)], want)
    check("rtcc EEPROM absent: 20 NACKed probes", bus.log[len(want):], (t_probe(0x57, False)) * 20)
    check("rtcc violations", p.violations, [])

print(f"{checks} checks, {len(fails)} failures")
for f in fails:
    print("FAIL", f)
if "--assumptions" in sys.argv:
    print("assumptions the model makes (to confirm on silicon):")
    for k, v in ASSUMPTIONS.items():
        print(f"  {k}: {v}")
sys.exit(1 if fails else 0)
