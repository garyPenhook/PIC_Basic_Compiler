Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i, j, crc As Byte
Dim sink As Byte

Asm
mark_a:
End Asm
For i = 0 To 63
    crc = crc Xor i
    For j = 1 To 8
        If (crc And $80) <> 0 Then
            crc = (crc << 1) Xor 7
        Else
            crc = crc << 1
        End If
    Next
Next
sink = crc
Asm
mark_b:
End Asm
