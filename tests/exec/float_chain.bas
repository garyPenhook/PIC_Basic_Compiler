' expect: FC_R1=1080033280 FC_R2=1088421888 FC_R3=1080033280 FC_R4=1073741824 FC_R5=1073741824
' A Float result stored to its variable and read straight back by the next statement (the peephole drops the reload).
Program Fc
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a, b, c As Float
Dim r1, r2, r3, r4, r5 As Float
a = 1.5
b = 2.0
c = a + b
r1 = c
c = c * b
r2 = c
c = c / b
r3 = c
c = c - a
r4 = c
c = c * 1.0
r5 = c
