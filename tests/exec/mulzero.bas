' expect: T_G=2 T_W=0 T_L=0
' A product with a zero constant factor still evaluates the other operand's side effects.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim g, w As Word
Dim l As LongWord
Function f() As Word
    g = g + 1
    f = 7
End Function
w = f() * 0
l = 0 * f()
