' expect: T_FS=1090519040 T_FH=1069547520 T_A=22 T_B=11 T_N=8 T_F4=1086324736 T_SUM1=60 T_W2=2000 T_L=5 T_U=1 T_PX=1235 T_PY=9 T_PZ=300000 T_SP=301244 T_SA=70126 T_A2Y=41 T_A2Z=2042
' Float by value and every ByRef form crossing to C: a scalar, an array, a String and a structure.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF
CFile "c_args.c"
Structure Pt
    X As Word
    Y As Byte
    Z As LongWord
End Structure
Extern Function scale(v As Float, k As Byte) As Float
Extern Function half(v As Float) As Float
Extern Sub swap16(ByRef a As Word, ByRef b As Word)
Extern Sub incr(ByRef p As Byte)
Extern Sub getf(ByRef out As Float, v As Float)
Extern Function sum(ByRef a() As Byte, n As Byte) As Word
Extern Sub fillw(ByRef a() As Word, n As Byte)
Extern Function slen(ByRef s As String(16)) As Byte
Extern Sub upper(ByRef s As String(16))
Extern Sub bump_pt(ByRef p As Pt)
Extern Function sumpt(ByRef p As Pt) As LongWord
Extern Function sumarr(ByRef a() As Pt, n As Byte) As LongWord
Extern Sub fillarr(ByRef a() As Pt, n As Byte)
Dim fs As Float
Dim fh As Float
Dim a As Word = 11
Dim b As Word = 22
Dim n As Byte = 7
Dim f4 As Float
Dim x As Float = 1.5
Dim bytes(4) As Byte
Dim sum1 As Word
Dim ww(4) As Word
Dim w2 As Word
Dim s As String(16)
Dim l As Byte
Dim u As Byte
Dim p As Pt
Dim px As Word
Dim py As Byte
Dim pz As LongWord
Dim sp As LongWord
Dim pa(3) As Pt
Dim sa As LongWord
Dim a2y As Byte
Dim a2z As LongWord
fs = scale(2.5, 3)
fh = half(3.0)
swap16(a, b)
incr(n)
getf(f4, x)
bytes(0) = 10
bytes(1) = 20
bytes(2) = 30
sum1 = sum(bytes, 3)
fillw(ww, 4)
w2 = ww(2)
s = "hello"
l = slen(s)
upper(s)
If s = "HELLO" Then
    u = 1
End If
p.X = 1234
p.Y = 7
p.Z = 200000
bump_pt(p)
px = p.X
py = p.Y
pz = p.Z
sp = sumpt(p)
pa(0).X = 1
pa(0).Y = 2
pa(0).Z = 3
pa(2).X = 100
pa(2).Y = 20
pa(2).Z = 70000
sa = sumarr(pa, 3)
fillarr(pa, 3)
a2y = pa(1).Y
a2z = pa(2).Z
