' expect: T_A1=-617 T_A2=617 T_A3=0 T_A4=-16384 T_A5=16383 T_A6=-308 T_A7=0 T_A8=-5 T_A9=-3 T_B1=-8 T_B2=-35000 T_B3=-8 T_B4=0
' Signed Integer, ShortInt and LongInt `/ 2^k`: truncation toward zero, sign, and the extremes.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Integer
Dim s As ShortInt
Dim l As LongInt
Dim a1 As Integer
Dim a2 As Integer
Dim a3 As Integer
Dim a4 As Integer
Dim a5 As Integer
Dim a6 As Integer
Dim a7 As Integer
Dim a8 As ShortInt
Dim a9 As ShortInt
Dim b1 As ShortInt
Dim b2 As LongInt
Dim b3 As Integer
Dim b4 As Integer
i = -1234
a1 = i / 2
i = 1235
a2 = i / 2
i = -1
a3 = i / 2
i = -32768
a4 = i / 2
i = 32767
a5 = i / 2
i = -1234
a6 = i / 4
i = -1
a7 = i / 256
s = -10
a8 = s / 2
s = -13
a9 = s / 4
s = -128
b1 = s / 16
l = -70000
b2 = l / 2
i = -2300
b3 = i / 256
i = 255
b4 = i / 256
End
