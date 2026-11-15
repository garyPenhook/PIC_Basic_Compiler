' expect: E-SYNTAX
' says: help: write `Select x`, without `Case`
Program T
Device = 18F27Q10
Dim i As Byte
Dim j As Byte
Select Case i
Case 1
    j = 1
End Select
End
