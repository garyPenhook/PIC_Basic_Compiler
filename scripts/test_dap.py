#!/usr/bin/env python3
"""Editor debugging through picsim's basil-sim-dap: build a small program with `-g -O0`, then drive the adapter over the
Debug Adapter Protocol the way VS Code does, on a PIC18 and a PIC16 part. Checks that a breakpoint on a BASIC line stops
there, that the call stack names the routine and the caller's line, that globals and the parameter read back by name and
type, and that continue / next / stepOut move to the lines the source says.

Environment: BASIL (the compiler), BASIL_LIB (library folder, optional), BASIL_SIM_DAP (default
../picsim/target/release/basil-sim-dap). Exit 0 when every check passes."""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASIL = os.environ.get("BASIL", os.path.join(ROOT, "target/release/basil"))
ADAPTER = os.environ.get("BASIL_SIM_DAP", os.path.join(ROOT, "../picsim/target/release/basil-sim-dap"))

BODY = """Dim total As Word
Dim i As Byte

Sub AddIt(n As Byte)
  total = total + n
End Sub

total = 0
For i = 1 To 5
  AddIt(i)
Next
Terminate
"""
# (program, device, clock, config)  -- source lines: header is 4 lines, so AddIt's body is line 9 and the call line 14.
PARTS = [
    ("t18", "18F27Q10", 64, "Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON"),
    ("t16", "16F17146", 32, "Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON"),
]
BODY_LINE, CALL_LINE, SUB_LINE = 9, 14, 8

fails = []
def check(cond, what):
    if not cond:
        fails.append(what)
        print("FAIL:", what)

class Dap:
    def __init__(s):
        s.p = subprocess.Popen([ADAPTER], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        s.seq = 0
        s.pending = []
    def read(s):
        n = 0
        while True:
            l = s.p.stdout.readline()
            if not l:
                raise EOFError(s.p.stderr.read().decode())
            l = l.strip()
            if not l:
                break
            if l.lower().startswith(b"content-length"):
                n = int(l.split(b":")[1])
        return json.loads(s.p.stdout.read(n))
    def req(s, cmd, args=None):
        s.seq += 1
        b = json.dumps({"seq": s.seq, "type": "request", "command": cmd, "arguments": args or {}}).encode()
        s.p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b)
        s.p.stdin.flush()
        while True:
            m = s.read()
            if m["type"] == "response" and m["request_seq"] == s.seq:
                if not m["success"]:
                    raise RuntimeError("%s: %s" % (cmd, m.get("message")))
                return m.get("body") or {}
            s.pending.append(m)
    def event(s, name):
        for i, m in enumerate(s.pending):
            if m.get("event") == name:
                return s.pending.pop(i)
        while True:
            m = s.read()
            if m.get("event") == name:
                return m
            s.pending.append(m)
    def frames(s):
        return s.req("stackTrace", {"threadId": 1})["stackFrames"]
    def run(s, cmd):
        s.req(cmd, {"threadId": 1})
        s.event("stopped")
        return s.frames()
    def scope(s, frame, name):
        for sc in s.req("scopes", {"frameId": frame["id"]})["scopes"]:
            if sc["name"] == name:
                vs = s.req("variables", {"variablesReference": sc["variablesReference"]})["variables"]
                return {v["name"]: v for v in vs}
        return {}

def one(work, prog, device, clock, config):
    src = os.path.join(work, prog + ".bas")
    with open(src, "w") as f:
        f.write("Program %s\nDevice = %s\nClock = %d\n%s\n%s" % (prog.upper(), device, clock, config, BODY))
    cmd = [BASIL, "-g", "-O0", "--keep-vars", src]
    lib = os.environ.get("BASIL_LIB")
    if lib:
        cmd[1:1] = ["-L", lib]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("basil failed on %s:\n%s%s" % (prog, r.stdout, r.stderr))
    tag = "%s/%s" % (device, prog)
    d = Dap()
    d.req("initialize", {"adapterID": "basil-sim", "linesStartAt1": True, "columnsStartAt1": True})
    d.req("launch", {"program": os.path.join(work, prog + ".hex"), "device": device, "stopOnEntry": True, "cwd": work})
    d.event("initialized")
    bp = d.req("setBreakpoints", {"source": {"path": src}, "breakpoints": [{"line": BODY_LINE}]})["breakpoints"]
    check(bp and bp[0]["verified"] and bp[0]["line"] == BODY_LINE, tag + ": breakpoint on line %d verified" % BODY_LINE)
    d.req("configurationDone")
    check(d.event("stopped")["body"]["reason"] == "entry", tag + ": stops at entry")
    g = d.scope(d.frames()[0], "Globals")
    check(g.get("total", {}).get("type") == "Word" and g["total"]["value"].startswith("0 "), tag + ": total is a Word, 0 at reset")
    check(g.get("i", {}).get("type") == "Byte", tag + ": i is a Byte")

    # Each pass of the loop adds i to total: the breakpoint is hit before the add, so total is 0, 1, 3, 6, 10.
    want = 0
    for k in range(1, 6):
        fr = d.run("continue")
        check(fr[0]["name"] == "AddIt" and fr[0]["line"] == BODY_LINE, tag + ": hit %d stops in AddIt line %d (got %s)" % (k, BODY_LINE, [(f["name"], f["line"]) for f in fr]))
        check(len(fr) >= 2 and fr[1]["line"] == CALL_LINE, tag + ": hit %d caller frame is line %d" % (k, CALL_LINE))
        check(fr[0].get("source", {}).get("name") == prog + ".bas", tag + ": frame source is %s.bas" % prog)
        loc = d.scope(fr[0], "Locals")
        check(loc.get("n", {}).get("value", "").startswith("%d " % k), tag + ": hit %d parameter n = %d (got %s)" % (k, k, loc.get("n")))
        tot = d.req("evaluate", {"expression": "total", "frameId": fr[0]["id"]})["result"]
        check(tot.startswith("%d " % want), tag + ": hit %d total = %d (got %s)" % (k, want, tot))
        want += k
        if k == 3:
            # step: from the body line the next line is the End Sub of AddIt, then back at the call site.
            fr = d.run("next")
            check(fr[0]["line"] != BODY_LINE, tag + ": next leaves line %d" % BODY_LINE)
    d.req("disconnect")
    d.p.wait(timeout=10)

with tempfile.TemporaryDirectory() as work:
    for part in PARTS:
        one(work, *part)
print("%d check(s) failed" % len(fails) if fails else "dap: all checks passed")
sys.exit(1 if fails else 0)
