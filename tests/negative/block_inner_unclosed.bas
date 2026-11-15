' expect: E-SYNTAX
' says: `Next` found while the `If` on line 8 is still open
Program T
Device = 18F27Q10
Dim i As Byte
Dim j As Byte
For i = 0 To 3
    If i = 2 Then
        j = 1
Next
End
