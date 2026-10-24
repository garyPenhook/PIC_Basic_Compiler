Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Byte
Dim acc As LongWord
Dim sink As LongWord

Asm
mark_a:
End Asm
For i = 1 To 100
    acc = acc + i * 1000
Next
sink = acc
Asm
mark_b:
End Asm
