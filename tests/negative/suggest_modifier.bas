' expect: E-NOMEMBER
' says: help: did you mean `Byte0`, `Byte1` or `Bytes`?
Program T
Device = 18F27Q10
Dim w As Word
w.Bytez = 1
End
