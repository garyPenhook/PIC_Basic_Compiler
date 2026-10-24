Program T
Device = 18F27Q10
Dim a As Byte
If a = 1 Then
    a = 2
ElseIf a = 2 Then
    a = 3
Else
    a = 4
End If
Select a
    Case 1
        a = 2
End Select
While a < 3
    Inc(a)
Wend
