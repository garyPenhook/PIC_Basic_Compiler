' warn: W-CASE-ELSE
Program T
Device = 18F27Q10
Dim b As Byte
Select b
    Case 0 To 127
        b = 1
    Case >= 128
        b = 2
    Else
        b = 3
EndSelect
