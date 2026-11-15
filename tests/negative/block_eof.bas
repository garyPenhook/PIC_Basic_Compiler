' expect: E-SYNTAX
' says: the `If` on line 7 is not closed: expected `End If` before the end of the file
Program T
Device = 18F27Q10
Dim i As Byte
While i < 3
    If i = 1 Then
        i = 2
