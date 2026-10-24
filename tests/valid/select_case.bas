Program T
Device = 18F27Q10
Dim b As Byte
Dim c As Char
Select b
    Case 1, 3, 5
        b = 0
    Case 10 To 20
        b = 1
    Case > 200
        b = 2
    Case Else
        b = 3
EndSelect
Select c
    Case "a"
        b = 1
    Case "b" To "z"
        b = 2
EndSelect
