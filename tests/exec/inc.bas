' expect: T_X=15 T_Y=250
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x As Byte
Dim y As Byte
x = 5
y = 255
Repeat
    x = x + 1
Until x = 15
y = y - 5
