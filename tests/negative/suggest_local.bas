' expect: E-UNDECLARED
' says: help: did you mean `total`?
' says: note: `total` is declared here
Program T
Device = 18F27Q10
Sub Add(ByVal n As Byte)
    Dim total As Word
    totl = total + n
End Sub
Add(1)
End
