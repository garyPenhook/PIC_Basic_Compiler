' expect: E-SYNTAX
' says: `Next` has no `For` to close: the innermost open block is the `While` on line 7, closed by `Wend`
' says: help: write `Wend` here to close the `While`
Program T
Device = 18F27Q10
Dim j As Byte
While j < 4
    Inc(j)
Next
End
