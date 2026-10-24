Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i, s, n As Byte
Dim sink As Byte

Asm
mark_a:
End Asm
For i = 1 To 100
    Select s
        Case 0
            s = 1
        Case 1
            s = 2
            n = n + 1
        Case 2
            s = 3
        Case Else
            s = 0
    End Select
Next
sink = n
Asm
mark_b:
End Asm
