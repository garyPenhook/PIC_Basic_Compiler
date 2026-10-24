Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Byte
Dim sum As Word
Dim sink As Word

Asm
mark_a:
End Asm
For i = 1 To 200
    sum = sum + i
Next
sink = sum
Asm
mark_b:
End Asm
