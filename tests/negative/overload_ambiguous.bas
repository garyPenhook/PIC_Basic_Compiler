' expect: E-AMBIG
Program T
Device = 18F27Q10
Dim x As Boolean
Sub P(ByVal a As Byte, ByVal b As Word)
End Sub
Sub P(ByVal a As Word, ByVal b As Byte)
End Sub
Dim w As Byte
P(w, w)
