Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i, m, d As Word
Dim hits, acc, q As Word
Dim sink As Word

' The handler owns hits, acc and q; the main program owns i, m and d. Each pass raises TMR0IF in
' software and waits for the handler, so it runs exactly 50 times in every build.
Interrupt Tick()
    PIR0.5 = 0
    Inc(hits)
    acc = acc * 5 + hits
    q = q + acc / 7 + acc Mod 13
End Interrupt

PIE0.5 = 1
Enable(Tick)
Asm
mark_a:
End Asm
For i = 1 To 50
    m = m + i * 37
    d = d + 54321 / (i + 3)
    PIR0.5 = 1
    While hits < i
    Wend
Next
sink = (m Xor d) + (acc Xor q)
Asm
mark_b:
End Asm
