' expect: E-SYNTAX
' says: `Next` is written without the loop variable
Program T
Device = 18F27Q10
Dim i As Byte
Dim j As Byte
For i = 0 To 3
    j = i
Next i
End
