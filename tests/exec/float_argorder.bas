' expect: FO_R1=1073741824 FO_R2=1065353216 FO_R3=3212836864 FO_R4=0 FO_R5=1073741824 FO_R6=1073741824
Program Fo
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
' Float operands go to the routines in registers; an operand is still computed before the one after it.
Dim g, r1, r2, r3, r4, r5, r6 As Float
Dim a(3) As Float

Function Bump() As Float
    g = g + 1
    Result = g
End Function

g = 0
r1 = Bump() + g
g = 0
r2 = g + Bump()
g = 0
r3 = g - Bump()
g = 0
r4 = Bump() - g
a(0) = 1
a(1) = 2
a(2) = 3
' two array elements, neither a plain variable
r5 = a(0) + a(0)
r6 = a(2) - a(0)
