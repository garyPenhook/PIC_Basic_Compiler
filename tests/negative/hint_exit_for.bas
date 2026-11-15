' expect: E-SYNTAX
' says: help: write `Break`
Program T
Device = 18F27Q10
Dim i As Byte
Dim j As Byte
For i = 0 To 3
    Exit For
Next
End
