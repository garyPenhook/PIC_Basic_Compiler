' warn:
' No W-NOTCMP: the `Not` is parenthesised either way, applies to a Boolean or a Bit (where both
' readings agree), stands on the right of the comparison, or is the left of an arithmetic operator.
Program T
Device = 18F27Q10
Dim x As Byte
Dim y As Byte
Dim f As Boolean
Dim b As Bit
If (Not x) = 5 Then
    y = 1
End If
If Not (x = 5) Then
    y = 2
End If
If Not f = True Then
    y = 3
End If
If Not b = 1 Then
    y = 4
End If
If 5 = Not x Then
    y = 5
End If
If Not x + 1 = 5 Then
    y = 6
End If
End
