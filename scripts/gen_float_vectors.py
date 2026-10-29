#!/usr/bin/env python3
"""Writes tests/exec_p16/float_random.bas: random and special operand pairs for the FloatLib routines with the
results an exact reference gives. The reference follows the library's rules, not the full IEEE ones: round to
nearest even on the exact result, a canonical quiet NaN (7FC00000), denormal operands read as zero, a result whose
exponent field is zero before rounding (or after it) is a signed zero, and one that is 255 or more is an infinity.

Usage: gen_float_vectors.py [N] > tests/exec_p16/float_random.bas   (N operand pairs, default 48)
"""
import random, sys
from fractions import Fraction

NAN = 0x7FC00000
INF = 0x7F800000
SIGN = 0x80000000


def fields(x):
    return (x >> 31) & 1, (x >> 23) & 255, x & 0x7FFFFF


def is_nan(x):
    s, e, f = fields(x)
    return e == 255 and f != 0


def value(x):
    """Exact value of a finite float with a non-zero exponent field; zero for exponent 0 (denormals read as zero)."""
    s, e, f = fields(x)
    if e == 0:
        return Fraction(0)
    v = Fraction(f | 0x800000, 1 << 23) * (Fraction(2) ** (e - 127))
    return -v if s else v


def make(sign, exact):
    """The float for a non-zero exact value `exact` (sign given) by the library's rounding rules."""
    sg = SIGN if sign else 0
    a = abs(exact)
    # exponent E with 2^E <= a < 2^(E+1)
    E = a.numerator.bit_length() - a.denominator.bit_length()
    if Fraction(2) ** E > a:
        E -= 1
    e = E + 127
    if e < 0:
        return sg
    m = a / (Fraction(2) ** E)  # 1 <= m < 2
    q = m * (1 << 23)
    f = q.numerator // q.denominator
    r = q - f
    if r > Fraction(1, 2) or (r == Fraction(1, 2) and f & 1):
        f += 1
    if f >= 1 << 24:
        f = 1 << 23
        e += 1
    if e >= 255:
        return sg | INF
    if e == 0:
        return sg
    return sg | (e << 23) | (f & 0x7FFFFF)


def fadd(a, b):
    if is_nan(a) or is_nan(b):
        return NAN
    sa, ea, _ = fields(a)
    sb, eb, _ = fields(b)
    if ea == 255 or eb == 255:
        if ea == 255 and eb == 255:
            return a if sa == sb else NAN
        return a if ea == 255 else b
    if ea == 0 and eb == 0:
        return SIGN if (sa and sb) else 0
    if ea == 0:
        return b
    if eb == 0:
        return a
    s = value(a) + value(b)
    if s == 0:
        return 0
    return make(s < 0, s)


def fmul(a, b):
    sa, ea, _ = fields(a)
    sb, eb, _ = fields(b)
    sg = SIGN if sa ^ sb else 0
    if is_nan(a) or is_nan(b):
        return NAN
    if ea == 255 or eb == 255:
        other = eb if ea == 255 else ea
        return NAN if other == 0 else sg | INF
    if ea == 0 or eb == 0:
        return sg
    p = value(a) * value(b)
    return make(sa ^ sb, p)


def fdiv(a, b):
    sa, ea, _ = fields(a)
    sb, eb, _ = fields(b)
    sg = SIGN if sa ^ sb else 0
    if is_nan(a) or is_nan(b):
        return NAN
    if ea == 255:
        return NAN if eb == 255 else sg | INF
    if eb == 255:
        return sg
    if eb == 0:
        return NAN if ea == 0 else sg | INF
    if ea == 0:
        return sg
    return make(sa ^ sb, value(a) / value(b))


def cmp(a, b):
    if is_nan(a) or is_nan(b):
        return 2
    ma, mb = a & 0x7FFFFFFF, b & 0x7FFFFFFF
    if ma == 0 and mb == 0:
        return 0
    if (a ^ b) & SIGN:
        return -1 if a & SIGN else 1
    if ma == mb:
        return 0
    gt = ma > mb
    return (1 if gt else -1) * (-1 if a & SIGN else 1)


def from_long(v, signed):
    if v == 0:
        return 0
    sg = 0
    if signed and v < 0:
        sg, v = SIGN, -v
    return make(bool(sg), Fraction(v))


def to_long(a):
    s, e, f = fields(a)
    if e < 127:
        return 0
    if e >= 158:
        if e == 255 and f:
            return 0
        return -(1 << 31) if s else (1 << 31) - 1
    m = f | 0x800000
    m = m << (e - 150) if e >= 150 else m >> (150 - e)
    return -m if s else m


def u32(x):
    return x & 0xFFFFFFFF


specials = [0, SIGN, INF, SIGN | INF, NAN, NAN | SIGN | 1, 0x00400000, SIGN | 0x00000001, 0x00800000, 0x7F7FFFFF, SIGN | 0x7F7FFFFF,
            0x3F800000, 0xBF800000, 0x40000000, 0x3F000000, 0x3F800001, 0x3F7FFFFF, 0x4B000000, 0x4B7FFFFF, 0x4EFFFFFF, 0x4F000000, 0xCF000000, 0x00800001]
rnd = random.Random(20261028)


def rand_float(expspread=None):
    e = rnd.choice([1, 2, 126, 127, 128, 150, 254, rnd.randrange(1, 255), rnd.randrange(1, 255)]) if expspread is None else expspread
    e = max(1, min(254, e))
    return (rnd.getrandbits(1) << 31) | (e << 23) | rnd.getrandbits(23)


# Products whose exponent field is 0 before rounding and whose rounding carries into 2^-126 (so the result is the smallest normal
# number, not zero), found by search; and sums that cancel to a tiny value (a zero), and sums just above the smallest normal number.
edge = [(0x1E7FFFFE, 0x21800001), (0x1E7FFFFA, 0x21800003), (0x1E7FFFF6, 0x21800005), (0x21800001, 0x1E7FFFFE),
        (0x00800001, 0x80800000), (0x00800003, 0x80800000), (0x01000000, 0x80800000), (0x00800000, 0x00800000), (0x7F7FFFFF, 0x7F7FFFFF),
        (0x7F7FFFFF, 0x34000000), (0x3F800000, 0x33800000), (0x3F800000, 0x33000000)]


def pairs(n):
    out = list(edge)
    for i, x in enumerate(specials):
        out.append((x, specials[(i * 7 + 3) % len(specials)]))
    while len(out) < n:
        kind = rnd.randrange(5)
        a = rand_float()
        if kind == 0:
            b = rand_float()
        elif kind == 1:  # near exponents: cancellation, alignment
            e = (a >> 23 & 255) + rnd.randrange(-3, 4)
            b = rand_float(e)
        elif kind == 2:  # same magnitude, other sign or a neighbour
            b = (a ^ SIGN) if rnd.getrandbits(1) else ((a & 0xFF800000) | ((a + rnd.randrange(-2, 3)) & 0x7FFFFF))
        elif kind == 3:  # products near the overflow / underflow edge
            b = rand_float(rnd.choice([2, 3, 252, 253, 254, 120, 135]))
            a = rand_float(rnd.choice([2, 3, 252, 253, 254, 127, 128]))
        else:
            b = rand_float(rnd.randrange(1, 255))
        out.append((a, b))
    return out[:n]


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 48
    ps = pairs(n)
    A = [p[0] for p in ps]
    B = [p[1] for p in ps]
    ops = [("FAdd", [fadd(a, b) for a, b in ps]), ("FMul", [fmul(a, b) for a, b in ps]), ("FDiv", [fdiv(a, b) for a, b in ps])]
    cm = [cmp(a, b) & 255 for a, b in ps]
    vs = [u32(rnd.getrandbits(32) >> rnd.randrange(0, 32)) for _ in range(n)] + [0, 1, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF, 0x01000001, 0x00FFFFFF, 0x00800001][:0]
    vs = vs[:n]
    vs[0:8] = [0, 1, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF, 0x01000001, 0x00FFFFFF, 0x1000000]
    fl = [from_long(v - (1 << 32) if v >= 1 << 31 else v, True) for v in vs]
    fu = [from_long(v, False) for v in vs]
    tl = [u32(to_long(a)) for a in A]

    def arr(name, vals, ty="LongWord"):
        body = ", ".join(str(v) for v in vals)
        return f"Const {name}({len(vals)}) As {ty} = ({body})"

    print(f"""' expect: FR_BAD=0 FR_FIRST=0
' FloatLib against an exact reference ({n} operand pairs: specials, near exponents, cancellation, overflow and underflow edges).
' Generated by scripts/gen_float_vectors.py; FR_FIRST is 0, or the op (1 add, 2 mul, 3 div, 4 compare, 5 FromLong, 6 FromULong, 7 ToLong) * 256 + index + 1 of the first mismatch.
Program Fr
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "floatlib"
{arr("A", A)}
{arr("B", B)}
{arr("RA", ops[0][1])}
{arr("RM", ops[1][1])}
{arr("RD", ops[2][1])}
{arr("RC", cm, "Byte")}
{arr("V", vs)}
{arr("RL", fl)}
{arr("RU", fu)}
{arr("RT", tl)}
Dim bad As Word
Dim first As Word
Dim i As Byte
Dim c As ShortInt
Sub Miss(ByVal op As Byte, ByVal idx As Byte)
    Inc(bad)
    If first = 0 Then
        first = Word(op) * 256 + idx + 1
    End If
End Sub
For i = 0 To {n - 1}
    If FloatLib.FAdd(A(i), B(i)) <> RA(i) Then
        Miss(1, i)
    End If
    If FloatLib.FMul(A(i), B(i)) <> RM(i) Then
        Miss(2, i)
    End If
    If FloatLib.FDiv(A(i), B(i)) <> RD(i) Then
        Miss(3, i)
    End If
    If FloatLib.FEq(A(i), B(i)) <> (RC(i) = 0) Then
        Miss(4, i)
    End If
    If FloatLib.FLt(A(i), B(i)) <> (RC(i) = 255) Then
        Miss(4, i)
    End If
    If FloatLib.FGt(A(i), B(i)) <> (RC(i) = 1) Then
        Miss(4, i)
    End If
    If FloatLib.FFromLong(LongInt(V(i))) <> RL(i) Then
        Miss(5, i)
    End If
    If FloatLib.FFromULong(V(i)) <> RU(i) Then
        Miss(6, i)
    End If
    If LongWord(FloatLib.FToLong(A(i))) <> RT(i) Then
        Miss(7, i)
    End If
Next""")


main()
