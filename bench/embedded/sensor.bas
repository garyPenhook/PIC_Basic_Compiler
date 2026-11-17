' expect: K_SINK=167716
Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim sink As LongWord

' Eight ADC samples per control update; hysteresis drives heater and alarm bits.
Const samples(32) As Word = (0, 8, 16, 80, 200, 380, 399, 400, 401, 450, 599, 600, 601, 700, 849, 850, 851, 900, 901, 950, 1023, 1010, 920, 880, 800, 650, 550, 410, 390, 300, 100, 0)
Dim batch, sample, heater, alarm, outputs As Byte
Dim adc, total, average, millivolts As Word
For batch = 0 To 63
    total = 0
    For sample = 0 To 7
        adc = samples((batch + sample) And 31)
        total = total + adc
    Next
    average = total >> 3
    millivolts = Word(LongWord(average) * 5000 / 1023)
    If average < 400 Then
        heater = 1
    ElseIf average > 600 Then
        heater = 0
    End If
    If average > 900 Then
        alarm = 1
    ElseIf average < 850 Then
        alarm = 0
    End If
    outputs = heater Or (alarm << 1)
    sink = sink + millivolts + outputs
Next
