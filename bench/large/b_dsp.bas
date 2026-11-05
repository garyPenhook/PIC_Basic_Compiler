' expect: K_SINK=4294933580
Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Const SINT(18) As Integer = (0, 1143, 2275, 3384, 4458, 5486, 6455, 7358, 8182, 8923, 9573, 10126, 10580, 10929, 11172, 11307, 11345, 11245)
Dim samples(32) As Integer
Dim coef(8) As Integer = (3, 11, 25, 41, 41, 25, 11, 3)
Dim hist(8) As Integer
Dim sink As LongInt
Dim pidI, pidPrev As Integer
Dim lcg As Word
Dim i As Byte
Dim f, y, u, plant As Integer

Function Sine(ByVal a As Byte) As Integer
    ' a: 0..255 = full turn; table covers a quarter (0..16 + 1)
    Dim q, idx, frac As Byte
    Dim v, d As Integer
    q = a >> 6
    idx = (a And 63) >> 2
    frac = a And 3
    If (q And 1) <> 0 Then
        idx = 16 - idx
        frac = 4 - frac
        If frac = 4 Then
            frac = 0
            idx = idx - 1
        End If
        frac = 4 - frac
        If frac = 4 Then
            frac = 0
        End If
    End If
    v = SINT(idx)
    d = SINT(idx + 1) - v
    v = v + (d * frac) / 4
    If q >= 2 Then
        v = 0 - v
    End If
    Result = v
End Function

Sub Gen()
        Dim s As Integer
    For i = 0 To 31
        lcg = lcg * 5 + 1
        s = Sine(i * 8) + Integer(lcg >> 12) - 8
        samples(i) = s
    Next
End Sub

Function Fir(ByVal x As Integer) As Integer
    Dim i As Byte
    Dim acc As LongInt
    For i = 7 To 1 Step -1
        hist(i) = hist(i - 1)
    Next
    hist(0) = x
    acc = 0
    For i = 0 To 7
        acc = acc + hist(i) * coef(i)
    Next
    Result = acc / 160
End Function

Function Pid(ByVal sp As Integer, ByVal pv As Integer) As Integer
    Dim e, p, d, out As Integer
    e = sp - pv
    pidI = pidI + e / 8
    If pidI > 2000 Then
        pidI = 2000
    End If
    If pidI < -2000 Then
        pidI = -2000
    End If
    p = e * 3
    d = (e - pidPrev) * 2
    pidPrev = e
    out = p + pidI + d
    If out > 4095 Then
        out = 4095
    End If
    If out < -4095 Then
        out = -4095
    End If
    Result = out
End Function

Function Mean() As Integer
    Dim i As Byte
    Dim acc As LongInt
    acc = 0
    For i = 0 To 31
        acc = acc + samples(i)
    Next
    Result = acc / 32
End Function

Function Rms() As Word
    Dim i As Byte
    Dim acc As LongInt
    Dim v As Integer
    Dim r, b As LongInt
    acc = 0
    For i = 0 To 31
        v = samples(i)
        If v < 0 Then
            v = 0 - v
        End If
        acc = acc + v * v
    Next
    acc = acc / 32
    r = 0
    b = $40000000
    While b > acc
        b = b >> 2
    Wend
    While b <> 0
        If acc >= r + b Then
            acc = acc - (r + b)
            r = (r >> 1) + b
        Else
            r = r >> 1
        End If
        b = b >> 2
    Wend
    Result = Word(r)
End Function

Function MinMax() As Integer
    Dim i As Byte
    Dim lo, hi As Integer
    lo = samples(0)
    hi = samples(0)
    For i = 1 To 31
        If samples(i) < lo Then
            lo = samples(i)
        End If
        If samples(i) > hi Then
            hi = samples(i)
        End If
    Next
    Result = hi - lo
End Function

Function MulQ15(ByVal a As Integer, ByVal b As Integer) As Integer
    Dim p As LongInt
    p = a
    p = p * b
    Result = p >> 15
End Function

Function Scale(ByVal v As Word, ByVal num As Word, ByVal den As Word) As Word
    Dim t As LongWord
    t = v
    t = t * num
    Result = t / den
End Function

Function Lowpass(ByVal x As Integer, ByVal y As Integer) As Integer
    Result = y + (x - y) / 8
End Function

lcg = 77
Gen()
sink = 0
For i = 0 To 31
    f = Fir(samples(i))
    y = Lowpass(samples(i), y)
    u = Pid(1000, plant)
    plant = plant + (u - plant) / 16
    sink = sink + f + y + plant
Next
sink = sink Xor Mean()
sink = sink + LongInt(Rms())
sink = sink + MinMax()
sink = sink + MulQ15(12345, -9876) + LongInt(Scale(1000, 3, 7)) + LongInt(Scale(65000, 255, 1000))
