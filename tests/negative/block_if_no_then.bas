' expect: E-SYNTAX
' says: expected `Then` at the end of the condition
Program T
Device = 18F27Q10
Dim i As Byte
If i = 3
    i = 1
End If
End
