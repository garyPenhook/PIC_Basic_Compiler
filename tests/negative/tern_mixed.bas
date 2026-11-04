' expect: E-TYPE
Program Tm
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x As Byte
Dim t As Boolean
x = 1
t = True
x = Tern(x, 1, 2)
