Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i, lo, hi, mid As Byte
Dim sink As Byte

Asm
mark_a:
End Asm
For i = 0 To 200
    If i < 50 Then
        lo = lo + 1
    ElseIf i >= 50 And i < 150 Then
        mid = mid + 1
    Else
        hi = hi + 1
    End If
Next
sink = lo + mid + hi
Asm
mark_b:
End Asm
