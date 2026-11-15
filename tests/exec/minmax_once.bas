' expect: T_A1=5 T_A2=9 T_A3=3 T_A4=3 T_A5=1000 T_A6=1234 T_A7=-3 T_A8=4 T_A9=-300 T_B1=7 T_B2=7 T_B3=-7 T_B4=200 T_B5=-200
' expect-O0: T_A1=5 T_A2=9 T_A3=3 T_A4=3 T_A5=1000 T_A6=1234 T_A7=-3 T_A8=4 T_A9=-300 T_B1=7 T_B2=7 T_B3=-7 T_B4=200 T_B5=-200
' `Min` / `Max` with a Volatile operand (read once by the back ends): Byte and Word, signed and unsigned, against a
' constant and against a variable, and with the Volatile one second.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a1 As Byte
Dim a2 As Byte
Dim a3 As Byte
Dim a4 As Byte
Dim a5 As Word
Dim a6 As Word
Dim a7 As ShortInt
Dim a8 As ShortInt
Dim a9 As Integer
Dim b1 As Byte
Dim b2 As Byte
Dim b3 As ShortInt
Dim b4 As Integer
Dim b5 As Integer
Volatile Dim vb As Byte
Volatile Dim vw As Word
Volatile Dim vs As ShortInt
Volatile Dim vi As Integer
Dim pb As Byte
Dim pw As Word
Dim ps As ShortInt
Dim pi As Integer

vb = 9
pb = 3
a1 = Min(vb, 5)
a2 = Max(vb, 5)
a3 = Min(vb, pb)
a4 = Min(pb, vb)
vw = 1234
pw = 1000
a5 = Min(vw, pw)
a6 = Max(pw, vw)
vs = -3
ps = 4
a7 = Min(vs, 4)
a8 = Max(vs, ps)
vi = -300
pi = 200
a9 = Min(vi, pi)
vb = 7
b1 = Min(vb, 200)
b2 = Max(vb, 0)
vs = -7
b3 = Min(ps, vs)
b4 = Max(vi, pi)
b5 = Min(pi, -200)
End
