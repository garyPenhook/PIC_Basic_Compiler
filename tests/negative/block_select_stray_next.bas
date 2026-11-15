' expect: E-SYNTAX
' says: `Next` has no `For` to close: the innermost open block is the `Select` on line 6
Program T
Device = 18F27Q10
Dim i As Byte
Select i
Case 1
    Next
Case 2
    While i = 2
        i = 3
    Wend
End Select
End
