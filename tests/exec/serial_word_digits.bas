' expect: T_NW=30 T_N=4 T_S=89 T_FIRST=48 T_LAST=53 T_HEXSUM=236 T_L1=53 T_L2=48 T_L3=57 T_L4=70 T_L5=53
' Same digit extraction as SerialWriteWord and SerialWriteHex in lib/serial.bas (the Const table of powers of ten, the final digit sent as
' it stands), with the bytes stored instead of sent: 0, 7, 10, 40000, 65535, 100, 9999, 1000, 12345 give 30 digits, and the hex of $A5 and
' $0F is "A5" "0F". The last byte left in TX1REG by the library's own routines is checked too (65535, 40000, 9, $AF, $05).
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "serial"
Dim buf(40) As Byte
Dim N, NW, S, First, Last, HexSum As Byte
Dim L1, L2, L3, L4, L5 As Byte
Dim i As Byte
Const Pow10(4) As Word = (10000, 1000, 100, 10)

Sub Put(ByVal b As Byte)
    buf(N) = b
    Inc(N)
End Sub

Sub PrintW(ByVal v As Word)
    Dim started As Boolean
    Dim k As Byte
    Dim digit As Byte
    Dim d As Word
    started = False
    For k = 0 To 3
        d = Pow10(k)
        digit = 48
        While v >= d
            v = v - d
            Inc(digit)
        Wend
        If digit > 48 Or started Then
            Put(digit)
            started = True
        End If
    Next
    Put(48 + Byte(v))
End Sub

Sub PrintH(ByVal v As Byte)
    Dim h As Byte
    Dim j As Byte
    For j = 0 To 1
        h = v >> 4
        v = v << 4
        If h > 9 Then
            h = h + 7
        End If
        Put(48 + h)
    Next
End Sub

N = 0
PrintW(0)
PrintW(7)
PrintW(10)
PrintW(40000)
PrintW(65535)
PrintW(100)
PrintW(9999)
PrintW(1000)
PrintW(12345)
NW = N
First = buf(0)
Last = buf(N - 1)
S = 0
For i = 0 To N - 1
    S = S + buf(i) - 48
Next
N = 0
PrintH($A5)
PrintH($0F)
HexSum = buf(0) + buf(1) + buf(2) + buf(3)
Serial.SerialInit(115200)
Serial.SerialWriteWord(65535)
L1 = TX1REG
Serial.SerialWriteWord(40000)
L2 = TX1REG
Serial.SerialWriteWord(9)
L3 = TX1REG
Serial.SerialWriteHex($AF)
L4 = TX1REG
Serial.SerialWriteHex($05)
L5 = TX1REG
