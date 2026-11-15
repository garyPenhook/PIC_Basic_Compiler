' expect: E-SYNTAX
' says: `GoTo` needs a label name, not a line number
Program T
Device = 18F27Q10
Dim i As Byte
Dim j As Byte
GoTo 10
End
