' expect: E-SYNTAX
' says: help: write `i = i + …` (or `Inc(i, …)`)
Program T
Device = 18F27Q10
Dim i As Byte
Dim j As Byte
i += 1
End
