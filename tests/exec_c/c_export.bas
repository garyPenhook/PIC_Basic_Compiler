' expect: T_R=62 T_TOTAL=105 T_F=1089470464 T_M=101007 T_S=26984 T_A=1061 T_D1=25 T_D2=25
' C calls Basic routines: `Export` routines are reached from inside an `Extern` routine, so their frames
' cannot share storage with the routines that are waiting on the C call.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF
CFile "c_export.c"
Extern Function run(n As Byte) As Word
Extern Function fl(x As Float) As Float
Extern Function mixit() As LongWord
Extern Function strc() As Word
Extern Function addto() As Word
Dim total As Word
Dim r As Word
Dim f As Float
Dim m As LongWord
Dim s As Word
Dim a As Word
Dim d1 As Word
Dim d2 As Word

Export Function Square(x As Byte) As Word
    Result = x * x
End Function

Export Sub Accum(v As Word)
    total = total + v
End Sub

Export Function Half(f As Float) As Float
    Result = f * 0.5
End Function

Export Function Mix(a As Byte, b As Word, c As LongWord) As LongWord
    Result = a + b + c
End Function

Export Sub Fill(ByRef s As String(16))
    s = "hi"
End Sub

Export Sub AddTo(ByRef p As Word, k As Byte)
    p = p + Square(k)
End Sub

' A routine with locals that is only called while C is inside Square's caller chain.
Function Wrap(x As Byte) As Word
    Dim t As Word
    t = Square(x)
    Result = t
End Function

r = run(6)
f = fl(5.0)
m = mixit()
s = strc()
a = addto()
d1 = Square(5)
d2 = Wrap(5)
