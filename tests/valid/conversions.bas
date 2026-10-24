' warn: W-NARROW
Program T
Device = 18F27Q10
Dim b As Byte
Dim w As Word
Dim i As Integer
Dim l As LongWord
Dim f As Float
Dim bo As Boolean
Dim bi As Bit
b = Byte(w)
i = Integer(b) - 1
l = LongWord(w) << 8
f = Float(w) / 2.0
bo = Boolean(bi)
bi = Bit(bo)
w = Word(f)
b = Abs(i)
b = Min(b, 5)
b = Max(b, Byte(w))
