Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim led As PORTB.0
Dim i, n As Byte
Dim sink As Byte
Output(led)
Asm
mark_a:
End Asm
For i = 1 To 20
    High(led)
    Low(led)
    n = n + 1
Next
sink = n
Asm
mark_b:
End Asm
