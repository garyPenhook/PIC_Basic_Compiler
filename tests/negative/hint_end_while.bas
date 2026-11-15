' expect: E-SYNTAX
' says: `End While` is written `Wend` here
Program T
Device = 18F27Q10
Dim i As Byte
Dim j As Byte
While i < 3
    Inc(i)
End While
End
