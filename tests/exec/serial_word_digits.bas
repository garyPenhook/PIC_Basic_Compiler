' expect: T_N=14 T_S=36 T_FIRST=48 T_LAST=53
' Same digit extraction as SerialWriteWord in lib/serial.bas, with the bytes stored instead of sent: 0, 7, 10, 40000, 65535 give 14 digits.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim buf(24) As Byte
Dim N, S, First, Last As Byte
Dim i As Byte

Sub Put(ByVal b As Byte)
    buf(N) = b
    Inc(N)
End Sub

Sub PrintW(ByVal v As Word)
    Dim started As Boolean
    Dim d As Word
    Dim digit As Byte
    started = False
    d = 10000
    While d > 0
        digit = 0
        While v >= d
            v = v - d
            Inc(digit)
        Wend
        If digit > 0 Or started Or d = 1 Then
            Put(48 + digit)
            started = True
        End If
        If d = 10000 Then
            d = 1000
        ElseIf d = 1000 Then
            d = 100
        ElseIf d = 100 Then
            d = 10
        ElseIf d = 10 Then
            d = 1
        Else
            d = 0
        End If
    Wend
End Sub

N = 0
PrintW(0)
PrintW(7)
PrintW(10)
PrintW(40000)
PrintW(65535)
First = buf(0)
Last = buf(N - 1)
S = 0
For i = 0 To N - 1
    S = S + buf(i) - 48
Next
