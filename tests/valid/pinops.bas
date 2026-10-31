Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim led As PORTB.0
Dim p As Byte
PinSet(led)
PinClear(PORTB.1)
PinSet(PORTC)
PinSet(9)
PinSet(p)
PinClear(p + 1)
PinPullup(led)
PinPullup(Enable, PORTB)
PinPullup(Disable, 9)
PinPullup(Off, p)
