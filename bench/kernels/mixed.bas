Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim buf(32) As Byte
Dim i, j, s, st, hi As Byte
Dim crc, t, v, ds, q, dv, yw As Word
Dim x, y, d As Integer
Dim acc As LongWord
Dim sink As Word

Asm
mark_a:
End Asm
' 1. fill a buffer from a byte LCG
s = 7
For i = 0 To 31
    s = s * 5 + 3
    buf(i) = s
Next
' 2. CRC-16/CCITT over it, bit by bit
crc = $FFFF
For i = 0 To 31
    t = buf(i)
    t = t << 8
    crc = crc Xor t
    For j = 1 To 8
        If (crc And $8000) <> 0 Then
            crc = (crc << 1) Xor $1021
        Else
            crc = crc << 1
        End If
    Next
Next
' 3. signed one-pole filter, 32-bit running sum and a three-state machine
For i = 0 To 31
    x = buf(i)
    x = x * 37
    d = x - y
    y = y + (d >> 2)
    acc = acc + (acc >> 3) + buf(i)
    Select st
        Case 0
            If buf(i) > 128 Then
                st = 1
            End If
        Case 1
            hi = hi + 1
            st = 2
        Case Else
            st = 0
    End Select
Next
' 4. decimal digit sums (divide and Mod by a constant) and a variable divide
For i = 1 To 8
    v = crc + i * 977
    While v > 0
        ds = ds + v Mod 10
        v = v / 10
    Wend
    dv = buf(i) Or 1
    q = q + crc / dv
Next
yw = y
sink = crc Xor ds Xor q Xor yw Xor hi
sink = sink Xor acc
Asm
mark_b:
End Asm
