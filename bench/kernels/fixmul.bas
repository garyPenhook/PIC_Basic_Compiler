Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x, acc As Word
Dim sink As Word

Asm
mark_a:
End Asm
For x = 0 To 1000 Step 7
    acc = acc + ((x * 10) >> 8)
Next
sink = acc
Asm
mark_b:
End Asm
