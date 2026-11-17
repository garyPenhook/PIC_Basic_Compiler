' expect: K_SINK=474523
Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim sink As LongWord

' Render a 16-character LCD status line: decimal ADC, millivolts and relay state.
Dim line(16) As Byte
Dim update, i, relay As Byte
Dim adc, millivolts, value As Word
For update = 0 To 63
    adc = (Word(update) * 37 + 17) And 1023
    millivolts = Word(LongWord(adc) * 5000 / 1023)
    relay = update And 1
    For i = 0 To 15
        line(i) = 32
    Next
    line(0) = 65
    line(1) = 61
    value = adc
    For i = 5 To 2 Step -1
        line(i) = Byte(value Mod 10) + 48
        value = value / 10
    Next
    line(7) = 86
    line(8) = 61
    value = millivolts
    For i = 12 To 9 Step -1
        line(i) = Byte(value Mod 10) + 48
        value = value / 10
    Next
    line(14) = 82
    line(15) = relay + 48
    For i = 0 To 15
        sink = sink + Word(line(i)) * (i + 1)
    Next
Next
