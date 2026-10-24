Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Byte
Dim n, q, m As Word
Dim sink As Word
n = 54321
Asm
mark_a:
End Asm
For i = 1 To 50
    q = q + n / i
    m = m + n Mod i
Next
sink = q Xor m
Asm
mark_b:
End Asm
