Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim led As PORTB.0
Dim p As Byte
PinMode(led, Output)
PinMode(PORTB.1, Input_PullUp)
PinMode(PORTC, Input)
PinMode(9, PullUp)
PinMode(p, Output)
PinMode(p + 1, Input)
