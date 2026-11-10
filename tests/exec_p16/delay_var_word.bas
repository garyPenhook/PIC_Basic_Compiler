' cycles: 10136 10260
' Variable delays through both loops: Word counts of 256, 511 and 300 (the low byte wraps on the way), 0 (no pass),
' a Byte of 200 and of 0. 1267 us at 8 cycles a microsecond is 10136 cycles, plus the set-up of each delay.
Program T
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Dim w As Word
Dim b As Byte
w = 256
DelayUS(w)
w = 511
DelayUS(w)
w = 300
DelayUS(w)
w = 0
DelayMS(w)
b = 200
DelayUS(b)
b = 0
DelayMS(b)
