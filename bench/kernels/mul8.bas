Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i, k As Byte
Dim w As Word
Dim sink As Word
k = 37
Asm
mark_a:
End Asm
For i = 1 To 100
    w = w + i * k
Next
sink = w
Asm
mark_b:
End Asm
