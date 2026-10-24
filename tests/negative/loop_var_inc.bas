' expect: E-LOOPVAR
Program T
Device = 18F27Q10
Dim i As Byte
For i = 1 To 5
    Inc(i)
Next
