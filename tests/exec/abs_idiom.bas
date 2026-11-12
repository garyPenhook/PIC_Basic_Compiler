' expect: T_A1=1234 T_A2=0 T_A3=100 T_A4=70000 T_A5=32768 T_A6=128 T_A7=7 T_A8=5 T_A9=5 T_B1=5 T_B2=-9 T_B3=5
' expect-O0: T_A1=1234 T_A2=0 T_A3=100 T_A4=70000 T_A5=32768 T_A6=128 T_A7=7 T_A8=5 T_A9=5 T_B1=5 T_B2=-9 T_B3=5
' `If v < 0 Then v = 0 - v` (or `v = -v`) is the absolute value; the optimiser may emit it as Abs. An Else branch,
' a different variable in the body, and a compare that is not `< 0` must not be changed.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a1 As Integer
Dim a2 As Integer
Dim a3 As ShortInt
Dim a4 As LongInt
Dim a5 As Integer
Dim a6 As ShortInt
Dim a7 As Integer
Dim a8 As Integer
Dim a9 As Integer
Dim b1 As Integer
Dim b2 As Integer
Dim b3 As Integer

NoInline Function AbsI(ByVal x As Integer) As Integer
    Dim v As Integer
    v = x
    If v < 0 Then
        v = 0 - v
    End If
    Result = v
End Function

NoInline Function AbsS(ByVal x As ShortInt) As ShortInt
    Dim v As ShortInt
    v = x
    If v < 0 Then
        v = -v
    End If
    Result = v
End Function

NoInline Function AbsL(ByVal x As LongInt) As LongInt
    Dim v As LongInt
    v = x
    If v < 0 Then
        v = 0 - v
    End If
    Result = v
End Function

' a different variable is negated: no Abs
NoInline Function Other(ByVal x As Integer, ByVal y As Integer) As Integer
    Dim v As Integer
    v = y
    If x < 0 Then
        v = 0 - x
    End If
    Result = v
End Function

' an Else branch
NoInline Function WithElse(ByVal x As Integer) As Integer
    Dim v As Integer
    v = x
    If v < 0 Then
        v = 0 - v
    Else
        v = 99
    End If
    Result = v
End Function

' other compares: negate when below 5, negate when above 0
NoInline Function Below5(ByVal x As Integer) As Integer
    Dim v As Integer
    v = x
    If v < 5 Then
        v = 0 - v
    End If
    Result = v
End Function

NoInline Function Above0(ByVal x As Integer) As Integer
    Dim v As Integer
    v = x
    If v > 0 Then
        v = 0 - v
    End If
    Result = v
End Function

a1 = AbsI(-1234)
a2 = AbsI(0)
a3 = AbsS(-100)
a4 = AbsL(-70000)
a5 = AbsI(-32768)
a6 = AbsS(-128)
a7 = AbsI(7)
a8 = Other(-5, 9)
a9 = WithElse(-5)
b1 = Below5(-5) - Below5(-5) + Below5(-5)
b2 = Above0(9)
b3 = Above0(-5) + 10
