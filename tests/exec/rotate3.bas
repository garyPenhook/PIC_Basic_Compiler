' expect: T_LF=102334155 T_WF=45608 T_WG=6765 T_UA=55 T_UT=89
' Three-variable rotate (t = a + b: a = b: b = t) built in one pass per byte on the PIC18: the carry runs through
' the whole sum, the operands may come in either order, and a temporary read afterwards keeps its own copy.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim lf As LongWord
Dim wf As Word
Dim wg As Word
Dim ua As Word
Dim ut As Word
Dim a, b, t As Word
Dim i As Byte

NoInline Function FibL(ByVal n As Byte) As LongWord
    Dim a, b, t As LongWord
    Dim i As Byte
    a = 0
    b = 1
    For i = 1 To n
        t = a + b
        a = b
        b = t
    Next
    Result = a
End Function

NoInline Function FibW(ByVal n As Byte) As Word
    Dim a, b, t As Word
    Dim i As Byte
    a = 0
    b = 1
    For i = 1 To n
        t = a + b
        a = b
        b = t
    Next
    Result = a
End Function

NoInline Function FibS(ByVal n As Byte) As Word
    Dim a, b, t As Word
    Dim i As Byte
    a = 0
    b = 1
    For i = 1 To n
        t = b + a
        b = a
        a = t
    Next
    Result = a
End Function

lf = FibL(40)
wf = FibW(30)
wg = FibS(20)

a = 0
b = 1
For i = 1 To 10
    t = a + b
    a = b
    b = t
Next
ua = a
ut = t
