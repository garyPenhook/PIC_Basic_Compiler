' expect: E-RECURSION
Program T
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF
CFile "x.c"
Extern Sub c_work()
Export Sub Back()
    c_work()
End Sub
c_work()
