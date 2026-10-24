' expect: E-CASE-OVERLAP
Program T
Device = 18F27Q10
Dim b As Byte
Select b
    Case 1 To 5
        b = 0
    Case 3
        b = 1
EndSelect
