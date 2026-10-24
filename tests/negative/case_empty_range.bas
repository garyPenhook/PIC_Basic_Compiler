' expect: E-CASE-RANGE
Program T
Device = 18F27Q10
Dim b As Byte
Select b
    Case 5 To 1
        b = 0
EndSelect
