' expect: K_SINK=46179
Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Const MSG(40) As Byte = (72, 101, 108, 108, 111, 32, 80, 73, 67, 49, 56, 44, 32, 116, 104, 105, 115, 32, 105, 115, 32, 97, 32, 116, 101, 115, 116, 32, 111, 102, 32, 116, 101, 120, 116, 32, 119, 111, 114, 107)
Const NUMS(24) As Byte = (49, 50, 51, 52, 53, 32, 45, 54, 55, 56, 32, 54, 53, 53, 51, 53, 32, 48, 32, 52, 50, 32, 55, 55)
Dim buf(24) As Byte
Dim line(40) As Byte
Dim sink As LongWord

Sub PutC(ByVal c As Byte)
    LATC = c
    sink = sink + c
End Sub

Sub PutBuf(ByVal n As Byte)
    Dim i As Byte
    For i = 0 To n - 1
        PutC(buf(i))
    Next
End Sub

Function ToDec(ByVal v As LongWord) As Byte
    Dim tmp(12) As Byte
    Dim n, i As Byte
    n = 0
    If v = 0 Then
        tmp(0) = 48
        n = 1
    End If
    While v > 0
        tmp(n) = 48 + v Mod 10
        v = v / 10
        n = n + 1
    Wend
    For i = 0 To n - 1
        buf(i) = tmp(n - 1 - i)
    Next
    Result = n
End Function

Function ToHex(ByVal v As Word) As Byte
    Dim i, d As Byte
    For i = 0 To 3
        d = (v >> ((3 - i) * 4)) And 15
        If d < 10 Then
            buf(i) = 48 + d
        Else
            buf(i) = 55 + d
        End If
    Next
    Result = 4
End Function

Function ToBin(ByVal v As Byte) As Byte
    Dim i As Byte
    For i = 0 To 7
        If (v And $80) <> 0 Then
            buf(i) = 49
        Else
            buf(i) = 48
        End If
        v = v << 1
    Next
    Result = 8
End Function

Function ToSigned(ByVal v As Integer) As Byte
    Dim n As Byte
    If v < 0 Then
        buf(0) = 45
        n = ToDec(LongWord(0 - v))
    Else
        n = ToDec(LongWord(v))
    End If
    Result = n
End Function

Function PadLeft(ByVal n As Byte, ByVal w As Byte) As Byte
    Dim i As Byte
    If n >= w Then
        Result = n
    Else
        For i = 1 To n
            buf(w - i) = buf(n - i)
        Next
        For i = 0 To w - n - 1
            buf(i) = 32
        Next
        Result = w
    End If
End Function

Function Upper(ByVal c As Byte) As Byte
    If c >= 97 Then
        If c <= 122 Then
            c = c - 32
        End If
    End If
    Result = c
End Function

Function IsDigit(ByVal c As Byte) As Boolean
    Result = (c >= 48) And (c <= 57)
End Function

Sub LoadMsg()
    Dim i As Byte
    For i = 0 To 39
        line(i) = MSG(i)
    Next
End Sub

Sub Reverse(ByVal n As Byte)
    Dim i, t As Byte
    For i = 0 To (n >> 1) - 1
        t = line(i)
        line(i) = line(n - 1 - i)
        line(n - 1 - i) = t
    Next
End Sub

Function CountWords(ByVal n As Byte) As Byte
    Dim i, w As Byte
    Dim inw As Boolean
    w = 0
    inw = False
    For i = 0 To n - 1
        If line(i) = 32 Then
            inw = False
        Else
            If Not inw Then
                w = w + 1
                inw = True
            End If
        End If
    Next
    Result = w
End Function

Function Checksum(ByVal n As Byte) As Word
    Dim i As Byte
    Dim a, b As Word
    a = 1
    b = 0
    For i = 0 To n - 1
        a = (a + line(i)) Mod 251
        b = (b + a) Mod 251
    Next
    Result = (b << 8) Or a
End Function

Function Parse(ByVal pos As Byte, ByRef val As Integer) As Byte
    Dim neg As Boolean
    Dim c As Byte
    Dim v As Integer
    neg = False
    v = 0
    c = NUMS(pos)
    If c = 45 Then
        neg = True
        pos = pos + 1
    End If
    c = NUMS(pos)
    While IsDigit(c)
        v = v * 10 + (c - 48)
        pos = pos + 1
        If pos >= 24 Then
            Break
        End If
        c = NUMS(pos)
    Wend
    If neg Then
        v = 0 - v
    End If
    val = v
    Result = pos + 1
End Function

Function Find(ByVal c As Byte, ByVal n As Byte) As Byte
    Dim i As Byte
    Result = 255
    For i = 0 To n - 1
        If line(i) = c Then
            Result = i
            Break
        End If
    Next
End Function

Dim i, n, p As Byte
Dim v, tot As Integer
Dim ck As Word

LoadMsg()
For i = 0 To 39
    line(i) = Upper(line(i))
Next
For i = 0 To 39
    PutC(line(i))
Next
sink = sink + CountWords(40)
Reverse(40)
ck = Checksum(40)
sink = sink + ck
n = ToHex(ck)
PutBuf(n)
n = ToBin(ck And 255)
PutBuf(n)
n = ToDec(sink)
n = PadLeft(n, 12)
PutBuf(n)
p = 0
tot = 0
For i = 1 To 6
    p = Parse(p, v)
    tot = tot + v
    n = ToSigned(v)
    n = PadLeft(n, 8)
    PutBuf(n)
    If p >= 23 Then
        Break
    End If
Next
n = ToSigned(tot)
PutBuf(n)
sink = sink + Find(82, 40) + Find(81, 40)
