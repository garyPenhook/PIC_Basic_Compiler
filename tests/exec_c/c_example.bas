' expect: T_CRC=244 T_TOT=45 T_OK=1
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF

CFile "c_example.c"
Extern Function crc8(crc As Byte, data As Byte) As Byte
Extern Sub total_add(v As Byte)
Extern Function total_get() As Word
Extern Function scale(v As Integer, mul As Byte) As LongInt

Dim crc As Byte
Dim tot As Word
Dim r As LongInt
Dim ok As Byte
Dim i As Byte

crc = 0
For i = 1 To 9
    crc = crc8(crc, 48 + i)        ' the bytes of "123456789": CRC-8 is 0xF4
    total_add(i)
Next
tot = total_get()                  ' 1 + 2 + ... + 9 = 45

r = scale(-300, 7)
If r = -2100 Then
    ok = 1
End If
