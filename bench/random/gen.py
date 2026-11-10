#!/usr/bin/env python3
"""Random BASIC/C program pairs over the adc, serial, eeprom, bits and delay modules.

Each operation has a BASIC form (library calls) and a C form (calls into a C port of the same
library routines, with the same logic and register writes; compile-time constants as #defines,
as the library's Const values are folded by basil).  Run-time inputs come from PORTA/B/C so
nothing folds.  Usage: gen.py OUTDIR SEED NOPS
"""
import os, random, sys

out, seed, nops = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rng = random.Random(seed)

def k8(lo=1, hi=200): return rng.randint(lo, hi)

WORDS = ["OK", "ADC=", "EE ", "T:", "hello", "sum", "err", "v"]

KINDS = {"adc": ["adc", "adcavg", "mv"], "serial": ["sword", "shex", "sstr", "secho"], "eeprom": ["eew", "eer", "eerw"],
         "bits": ["rol", "setbit", "getbit"], "delay": ["delay"]}
CORE = ["arith", "div", "acc", "loop", "csum", "out"]
# Each program uses its own 2 or 3 of the library modules, plus core statements.
CHOSEN = rng.sample(sorted(KINDS), rng.choice([2, 3]))
POOL = CORE + [k for m in CHOSEN for k in KINDS[m]] * 2

def op():
    """(module set, basic lines, c lines)"""
    kind = rng.choice(POOL)
    k = k8()
    if kind == "adc":
        return {"adc"}, [f"a = AdcRead(PORTA And 7)"], [f"a = AdcRead(PORTA & 7);"]
    if kind == "adcavg":
        n = rng.choice([2, 4, 8])
        return {"adc"}, [f"a = AdcReadAvg({k % 8}, {n})"], [f"a = AdcReadAvg({k % 8}, {n});"]
    if kind == "mv":
        return {"adc"}, ["b = AdcMillivolts(a, 3300)"], ["b = AdcMillivolts(a, 3300);"]
    if kind == "sword":
        v = rng.choice(["a", "b"])
        return {"serial"}, [f"SerialWriteWord({v})", "SerialNewLine()"], [f"SerialWriteWord({v});", "SerialNewLine();"]
    if kind == "shex":
        v = rng.choice(["x", "y"])
        return {"serial"}, [f"SerialWriteHex({v})"], [f"SerialWriteHex({v});"]
    if kind == "sstr":
        w = rng.choice(WORDS)
        return {"serial"}, [f'SerialWrite("{w}")'], [f'SerialWrite("{w}");']
    if kind == "secho":
        c1, c2 = rng.choice([(65, 66), (43, 45), (49, 48)])
        return {"serial"}, ["x = SerialRead()", "Select x", f"    Case {c1}", "        y = y + 1", f"    Case {c2}",
                            "        y = y - 1", "    Case Else", "        buf(y And 15) = x", "End Select", "SerialWriteByte(x)"], \
               ["x = SerialRead();", "switch (x) {", f"    case {c1}: y = (uint8_t)(y + 1); break;", f"    case {c2}: y = (uint8_t)(y - 1); break;",
                "    default: buf[y & 15] = x; break;", "}", "SerialWriteByte(x);"]
    if kind == "eew":
        return {"eeprom"}, [f"x = EepromWrite({k} + (PORTB And 15), y)"], [f"x = EepromWrite({k} + (PORTB & 15), y);"]
    if kind == "eer":
        return {"eeprom"}, [f"y = EepromRead({k})"], [f"y = EepromRead({k});"]
    if kind == "eerw":
        return {"eeprom"}, [f"a = EepromReadWord({k * 2})"], [f"a = EepromReadWord({k * 2});"]
    if kind == "rol":
        return {"bits"}, ["x = Rol(x)"], ["x = Rol(x);"]
    if kind == "setbit":
        return {"bits"}, ["y = SetBit(y, PORTB And 7)"], ["y = SetBit(y, PORTB & 7);"]
    if kind == "getbit":
        return {"bits"}, [f"If GetBit(acc, PORTC And 31) Then", f"    x = x Xor {k}", "End If"], \
               [f"if (GetBit(acc, PORTC & 31)) x ^= {k};"]
    if kind == "delay":
        if rng.random() < 0.5:
            return {"delay"}, [f"DelayMS({k})"], [f"__delay_ms({k});"]
        return {"delay"}, [f"DelayUS({k})"], [f"__delay_us({k});"]
    if kind == "arith":
        return set(), [f"a = a * {k} + PORTC"], [f"a = (uint16_t)(a * {k}u + PORTC);"]
    if kind == "div":
        return set(), ["b = a / (x Or 1)"], ["b = a / (uint8_t)(x | 1);"]
    if kind == "acc":
        return set(), ["acc = acc + LongWord(a) * b"], ["acc += (uint32_t)a * b;"]
    if kind == "loop":
        return set(), ["For i = 0 To 15", "    buf(i) = buf(i) + i * x", "Next"], \
               ["for (i = 0; i <= 15; i++) buf[i] = (uint8_t)(buf[i] + i * x);"]
    if kind == "csum":
        return set(), ["y = 0", "For i = 0 To 15", "    y = y Xor buf(i)", "Next"], \
               ["y = 0;", "for (i = 0; i <= 15; i++) y ^= buf[i];"]
    return set(), ["PORTB = x", "LATC = Byte(a)"], ["PORTB = x;", "LATC = (uint8_t)a;"]

mods, bas, cc = set(), [], []
for _ in range(nops):
    m, b, c = op()
    mods |= m
    bas += b
    cc += c

DEV = {
    "18F27Q10": ("64", "HFINTOSC_64MHZ", "64000000"),
    "16F18346": ("32", "HFINT32", "32000000"),
}
name = f"r{seed:02d}"
for dev, (mhz, osc, hz) in DEV.items():
    d = os.path.join(out, dev)
    os.makedirs(d, exist_ok=True)
    # ---- BASIC
    L = ["Program R", f"Device = {dev}", f"Clock = {mhz}", f"Config FEXTOSC = OFF, RSTOSC = {osc}, WDTE = OFF, LVP = ON"]
    for m in ("adc", "serial", "eeprom", "bits"):
        if m in mods:
            L.append(f'Include "{m}"')
    L += ["Dim a As Word", "Dim b As Word", "Dim x As Byte", "Dim y As Byte", "Dim i As Byte", "Dim acc As LongWord",
          "Dim buf(16) As Byte"]
    if "adc" in mods:
        L.append("AdcInit()")
    if "serial" in mods:
        L.append("SerialInit(115200)")
    L.append("While True")
    L += ["    " + s for s in bas]
    L.append("Wend")
    open(os.path.join(d, name + ".bas"), "w").write("\n".join(L) + "\n")
    # ---- C
    C = ["#include <xc.h>", "#include <stdint.h>", f"#define _XTAL_FREQ {hz}UL",
         f"#pragma config FEXTOSC = OFF, RSTOSC = {osc}, WDTE = OFF, LVP = ON",
         "uint16_t a, b; uint8_t x, y, i; uint32_t acc; uint8_t buf[16];"]
    C.append('#include "lib.h"')
    C.append("void main(void) {")
    if "adc" in mods:
        C.append("    AdcInit();")
    if "serial" in mods:
        C.append("    SerialInit();")
    C.append("    for (;;) {")
    C += ["        " + s for s in cc]
    C += ["    }", "}"]
    open(os.path.join(d, name + ".c"), "w").write("\n".join(C) + "\n")
print(name, sorted(mods))
