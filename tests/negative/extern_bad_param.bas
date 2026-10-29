' expect: E-EXTERN
Program T
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF
Extern Sub f(ByRef a As Byte)
Dim x As Byte
x = 1
