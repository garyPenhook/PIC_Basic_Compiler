' expect: T_A=14464 T_B=44 T_C=-2 T_D=20 T_E=7 T_F=14464 T_G=1000
' `Result = r` with `r` a wider local: the callers read the low bytes of `r`. The high bytes must not leak into the result.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a As Word
Dim b As Byte
Dim c As Integer
Dim d As Byte
Dim e As Word
Dim f As Word
Dim g As Word

NoInline Function Sq(ByVal n As LongWord) As Word
    Dim r As LongWord
    r = n * 4
    Result = r
End Function

NoInline Function LoB(ByVal n As Word) As Byte
    Dim r As Word
    r = n + 300
    Result = r
End Function

NoInline Function Sgn(ByVal n As LongInt) As Integer
    Dim r As LongInt
    r = n - 70000
    Result = r
End Function

' a call inside: not narrowed, still right
NoInline Function WithCall(ByVal n As Word) As Byte
    Dim r As Word
    r = LoB(n) + 1000
    Result = r
End Function

NoInline Function Twice(ByVal n As LongWord) As Word
    Dim r As LongWord
    r = n + n
    Result = r
End Function

a = Sq(20000)
b = LoB(0)
c = Sgn(69998)
d = WithCall(0)
e = Twice(3) + 1
f = Twice(40000)
g = Sq(100) + Sq(150)
