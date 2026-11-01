' expect: T_R1=10 T_R2=246 T_R3=10 T_R4=1 T_R5=255 T_R6=11 T_R7=245 T_R8=399 T_R9=16 T_R10=5 T_R11=3
' expect: T_DA=31 T_DB1=12 T_DB2=0 T_DB3=0 T_DB4=0 T_DC=7 T_E1=1 T_E2=6 T_S1=0 T_S2=10 T_Z=0
' A loop over constants is run by the compiler (DivA, DivC: one call, constant argument), the same loop runs on the
' target when its input is not constant (DivB). A local written only after an early Exit, a For variable, and a local
' read before any write keep their meaning. `x >= a And x <= b` / `x < a Or x > b` are one range test.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x As Byte
Dim s As ShortInt
Dim w As Word
Dim i As Byte
Dim r1 As Word
Dim r2 As Word
Dim r3 As Word
Dim r4 As Word
Dim r5 As Word
Dim r6 As Word
Dim r7 As Word
Dim r8 As Word
Dim r9 As Word
Dim r10 As Word
Dim r11 As Word
Dim arr(8) As Byte
Dim v As LongWord
Dim dA As Byte
Dim dB1 As Byte
Dim dB2 As Byte
Dim dB3 As Byte
Dim dB4 As Byte
Dim dC As Byte
Dim e1 As Byte
Dim e2 As Byte
Dim s1 As Byte
Dim s2 As Byte
Dim z As Byte

Function DivA(ByVal hz As LongWord) As Byte
    Dim fclk As LongWord
    Dim stp As LongWord
    Dim acc As LongWord
    Dim d As Word
    Result = 0
    If hz = 0 Or hz > 400000 Then
        Exit
    End If
    fclk = LongWord(_Clock * 250000)
    stp = LongWord(5) * hz
    acc = stp
    d = 1
    While acc < fclk And d < 257
        acc = acc + stp
        Inc(d)
    Wend
    If d > 256 Then
        Exit
    End If
    Result = Byte(d - 1)
End Function

Function DivB(ByVal hz As LongWord) As Byte
    Dim fclk As LongWord
    Dim stp As LongWord
    Dim acc As LongWord
    Dim d As Word
    Result = 0
    If hz = 0 Or hz > 400000 Then
        Exit
    End If
    fclk = LongWord(_Clock * 250000)
    stp = LongWord(5) * hz
    acc = stp
    d = 1
    While acc < fclk And d < 257
        acc = acc + stp
        Inc(d)
    Wend
    If d > 256 Then
        Exit
    End If
    Result = Byte(d - 1)
End Function

Function DivC(ByVal hz As LongWord) As Byte
    Dim fclk As LongWord
    Dim stp As LongWord
    Dim acc As LongWord
    Dim d As Word
    Result = 0
    If hz = 0 Or hz > 400000 Then
        Exit
    End If
    fclk = LongWord(_Clock * 250000)
    stp = LongWord(5) * hz
    acc = stp
    d = 1
    While acc < fclk And d < 257
        acc = acc + stp
        Inc(d)
    Wend
    If d > 256 Then
        Exit
    End If
    Result = Byte(d - 1)
End Function

Function Early(ByVal k As Byte) As Byte
    Dim t As Byte
    Result = 1
    If k = 0 Then
        Exit
    End If
    t = k + 1
    Result = t
End Function

Function SumTo(ByVal n As Byte) As Byte
    Dim j As Byte
    Dim t As Byte
    Result = 0
    If n = 0 Then
        Exit
    End If
    t = 0
    For j = 1 To n
        t = t + j
    Next
    Result = t
End Function

Function Dirty() As Byte
    Dim q As Byte
    q = 77
    Result = q
End Function

Function ZeroLocal() As Byte
    Dim q As Byte
    Result = 5
    If Dirty() = 0 Then
        Exit
    End If
    Result = q
End Function

arr(0) = 48
arr(1) = 57
arr(2) = 47
arr(3) = 58
arr(4) = 0
arr(5) = 255
arr(6) = 53
arr(7) = 100
For x = 0 To 255
    If x >= 48 And x <= 57 Then
        Inc(r1)
    End If
    If x < 48 Or x > 57 Then
        Inc(r2)
    End If
    If x > 47 And x < 58 Then
        Inc(r3)
    End If
    If x >= 7 And x <= 7 Then
        Inc(r4)
    End If
    If x < 7 Or x > 7 Then
        Inc(r5)
    End If
    If x <= 9 Or x >= 250 Then
        Inc(r9)
    End If
Next
For s = -128 To 127
    If s >= -5 And s <= 5 Then
        Inc(r6)
    End If
    If s < -5 Or s > 5 Then
        Inc(r7)
    End If
Next
For w = 0 To 1000
    If w > 300 And w < 700 Then
        Inc(r8)
    End If
Next
For i = 0 To 7
    If arr(i) < 48 Or arr(i) > 57 Then
        Inc(r10)
    End If
    If arr(i) >= 48 And arr(i) <= 57 Then
        Inc(r11)
    End If
Next
dA = DivA(100000)
v = 250000
dB1 = DivB(v)
v = 0
dB2 = DivB(v)
v = 1
dB3 = DivB(v)
v = 400001
dB4 = DivB(v)
dC = DivC(400000)
e1 = Early(0)
e2 = Early(5)
s1 = SumTo(0)
s2 = SumTo(4)
z = ZeroLocal()
