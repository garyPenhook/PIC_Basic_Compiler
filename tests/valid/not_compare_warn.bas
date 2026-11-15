' warn: W-NOTCMP
' `Not x = 5` is `(Not x) = 5`: on an integer it compares the complement, which is rarely meant.
Program T
Device = 18F27Q10
Dim x As Byte
Dim w As Integer
Dim y As Byte
If Not x = 5 Then
    y = 1
End If
If y = 2 And Not w < 0 Then
    y = 3
End If
End
