Program T
Device = 18F27Q10
Dim l As LongWord
Dim w As Word
Dim b As Byte
Dim bits As Bit
Dim bo As Boolean
Dim arr(4) As Byte
Dim big As arr(0).AsLongWord
b = l.Byte0 + l.Byte3
w = l.Word1
bits = l.31
bits = w.Bits(3)
bo = Boolean(w.Bits(2))
b = w.Bytes(1)
w.Byte0 = 5
big = 1
