Program T
Device = 18F27Q10
Dim b1 As Byte
Dim b2 As Byte
Dim b3 As Byte
Dim w As Word
Dim i As Integer
Dim l As LongWord
Dim li As LongInt
Dim f As Boolean
w = b1 * b2
b3 = b1 + b2 + 1
f = b1 + b2 > 300
l = w * 2
li = i + 100000
i = b1 + i
f = (b1 = 5) And (b2 <> 3)
b3 = b1 And $0F
b3 = b1 << 2
b3 = Not b1
