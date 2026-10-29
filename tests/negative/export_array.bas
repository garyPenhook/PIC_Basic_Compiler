' expect: E-EXTERN
Program T
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF
CFile "x.c"
Export Sub Take(ByRef a() As Byte)
End Sub
