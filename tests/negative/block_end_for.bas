' expect: E-SYNTAX E-UNDECLARED
' says: `End For` is written `Next` here
' says: help: did you mean `Byte`?
Program T
Device = 18F27Q10
Dim i As Byte
Dim j As Byte
Sub S()
    For i = 0 To 3
        j = i
    End For
End Sub
Dim zz As Bytee
S()
End
