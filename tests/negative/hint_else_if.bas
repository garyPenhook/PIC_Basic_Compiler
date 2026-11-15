' expect: E-SYNTAX
' says: help: write `ElseIf`
Program T
Device = 18F27Q10
Dim i As Byte
Dim j As Byte
If i = 1 Then
    j = 1
Else If i = 2 Then
    j = 2
End If
End
