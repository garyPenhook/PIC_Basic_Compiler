' expect: NSH_BAD=0 NSH_DONE=1
' The low byte of a 16-bit shift by a constant is built from byte operations (Byte(x >> k), Byte(x << k), Integer too), and a Word
' compared with a constant of a wider type is compared as a Word. Every result is checked against the same value computed
' the long way: through a Word or LongWord variable.
Program Nsh
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Const C16 As LongWord = 16384
Const CBIG As LongWord = 70000
Const CMAX As LongWord = 65535
Const CZ As LongWord = 0
Dim x As Word
Dim xi As Integer
Dim t As Word
Dim ti As Integer
Dim l As LongWord
Dim r As Byte
Dim i As Word
Dim bad As Word
Dim done As Byte
For i = 0 To 600
    x = i * 109 + 7
    xi = x
    If i < 4 Then
        x = 0
        xi = 0
    End If
    If i = 4 Then
        x = 65535
        xi = -1
    End If
    If i = 5 Then
        x = 32768
        xi = -32768
    End If
    l = x
    t = x >> 1
    r = Byte(x >> 1)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 1
    r = Byte(xi >> 1)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 2
    r = Byte(x >> 2)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 2
    r = Byte(xi >> 2)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 3
    r = Byte(x >> 3)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 3
    r = Byte(xi >> 3)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 4
    r = Byte(x >> 4)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 4
    r = Byte(xi >> 4)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 5
    r = Byte(x >> 5)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 5
    r = Byte(xi >> 5)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 6
    r = Byte(x >> 6)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 6
    r = Byte(xi >> 6)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 7
    r = Byte(x >> 7)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 7
    r = Byte(xi >> 7)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 8
    r = Byte(x >> 8)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 8
    r = Byte(xi >> 8)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 9
    r = Byte(x >> 9)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 9
    r = Byte(xi >> 9)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 10
    r = Byte(x >> 10)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 10
    r = Byte(xi >> 10)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 11
    r = Byte(x >> 11)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 11
    r = Byte(xi >> 11)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 12
    r = Byte(x >> 12)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 12
    r = Byte(xi >> 12)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 13
    r = Byte(x >> 13)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 13
    r = Byte(xi >> 13)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 14
    r = Byte(x >> 14)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 14
    r = Byte(xi >> 14)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x >> 15
    r = Byte(x >> 15)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    ti = xi >> 15
    r = Byte(xi >> 15)
    If r <> Byte(ti) Then
        bad = bad + 1
    End If
    t = x << 1
    r = Byte(x << 1)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    t = x << 2
    r = Byte(x << 2)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    t = x << 3
    r = Byte(x << 3)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    t = x << 4
    r = Byte(x << 4)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    t = x << 5
    r = Byte(x << 5)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    t = x << 6
    r = Byte(x << 6)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    t = x << 7
    r = Byte(x << 7)
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    t = x >> 7
    r = x >> 7
    If r <> Byte(t) Then
        bad = bad + 1
    End If
    If (x < C16) <> (l < C16) Then
        bad = bad + 1
    End If
    If (C16 < x) <> (C16 < l) Then
        bad = bad + 1
    End If
    If (x <= C16) <> (l <= C16) Then
        bad = bad + 1
    End If
    If (C16 <= x) <> (C16 <= l) Then
        bad = bad + 1
    End If
    If (x > C16) <> (l > C16) Then
        bad = bad + 1
    End If
    If (C16 > x) <> (C16 > l) Then
        bad = bad + 1
    End If
    If (x >= C16) <> (l >= C16) Then
        bad = bad + 1
    End If
    If (C16 >= x) <> (C16 >= l) Then
        bad = bad + 1
    End If
    If (x = C16) <> (l = C16) Then
        bad = bad + 1
    End If
    If (C16 = x) <> (C16 = l) Then
        bad = bad + 1
    End If
    If (x <> C16) <> (l <> C16) Then
        bad = bad + 1
    End If
    If (C16 <> x) <> (C16 <> l) Then
        bad = bad + 1
    End If
    If (x < CBIG) <> (l < CBIG) Then
        bad = bad + 1
    End If
    If (CBIG < x) <> (CBIG < l) Then
        bad = bad + 1
    End If
    If (x <= CBIG) <> (l <= CBIG) Then
        bad = bad + 1
    End If
    If (CBIG <= x) <> (CBIG <= l) Then
        bad = bad + 1
    End If
    If (x > CBIG) <> (l > CBIG) Then
        bad = bad + 1
    End If
    If (CBIG > x) <> (CBIG > l) Then
        bad = bad + 1
    End If
    If (x >= CBIG) <> (l >= CBIG) Then
        bad = bad + 1
    End If
    If (CBIG >= x) <> (CBIG >= l) Then
        bad = bad + 1
    End If
    If (x = CBIG) <> (l = CBIG) Then
        bad = bad + 1
    End If
    If (CBIG = x) <> (CBIG = l) Then
        bad = bad + 1
    End If
    If (x <> CBIG) <> (l <> CBIG) Then
        bad = bad + 1
    End If
    If (CBIG <> x) <> (CBIG <> l) Then
        bad = bad + 1
    End If
    If (x < CMAX) <> (l < CMAX) Then
        bad = bad + 1
    End If
    If (CMAX < x) <> (CMAX < l) Then
        bad = bad + 1
    End If
    If (x <= CMAX) <> (l <= CMAX) Then
        bad = bad + 1
    End If
    If (CMAX <= x) <> (CMAX <= l) Then
        bad = bad + 1
    End If
    If (x > CMAX) <> (l > CMAX) Then
        bad = bad + 1
    End If
    If (CMAX > x) <> (CMAX > l) Then
        bad = bad + 1
    End If
    If (x >= CMAX) <> (l >= CMAX) Then
        bad = bad + 1
    End If
    If (CMAX >= x) <> (CMAX >= l) Then
        bad = bad + 1
    End If
    If (x = CMAX) <> (l = CMAX) Then
        bad = bad + 1
    End If
    If (CMAX = x) <> (CMAX = l) Then
        bad = bad + 1
    End If
    If (x <> CMAX) <> (l <> CMAX) Then
        bad = bad + 1
    End If
    If (CMAX <> x) <> (CMAX <> l) Then
        bad = bad + 1
    End If
    If (x < CZ) <> (l < CZ) Then
        bad = bad + 1
    End If
    If (CZ < x) <> (CZ < l) Then
        bad = bad + 1
    End If
    If (x <= CZ) <> (l <= CZ) Then
        bad = bad + 1
    End If
    If (CZ <= x) <> (CZ <= l) Then
        bad = bad + 1
    End If
    If (x > CZ) <> (l > CZ) Then
        bad = bad + 1
    End If
    If (CZ > x) <> (CZ > l) Then
        bad = bad + 1
    End If
    If (x >= CZ) <> (l >= CZ) Then
        bad = bad + 1
    End If
    If (CZ >= x) <> (CZ >= l) Then
        bad = bad + 1
    End If
    If (x = CZ) <> (l = CZ) Then
        bad = bad + 1
    End If
    If (CZ = x) <> (CZ = l) Then
        bad = bad + 1
    End If
    If (x <> CZ) <> (l <> CZ) Then
        bad = bad + 1
    End If
    If (CZ <> x) <> (CZ <> l) Then
        bad = bad + 1
    End If
Next
done = 1
