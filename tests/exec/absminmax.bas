' expect: T_A1=1234 T_A2=0 T_A3=100 T_A4=70000 T_A5=7 T_A6=200
' expect: T_M1=3 T_M2=9 T_M3=-5 T_M4=7 T_M5=200 T_M6=1000 T_M7=-70000 T_M8=5
' expect: T_N1=-10 T_N2=7 T_N3=1 T_N4=70
' Abs, Min and Max on variables of every width; Inc and Dec with an amount.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Integer
Dim s As ShortInt
Dim l As LongInt
Dim b As Byte
Dim c As Byte
Dim w As Word
Dim a1 As Integer
Dim a2 As Integer
Dim a3 As ShortInt
Dim a4 As LongInt
Dim a5 As Byte
Dim a6 As Word
Dim m1 As Byte
Dim m2 As Byte
Dim m3 As Integer
Dim m4 As Integer
Dim m5 As Byte
Dim m6 As Word
Dim m7 As LongInt
Dim m8 As LongInt
Dim n1 As Integer
Dim n2 As Integer
Dim n3 As Byte
Dim n4 As Byte
Dim amt As Byte
i = -1234
a1 = Abs(i)
i = 0
a2 = Abs(i)
s = -100
a3 = Abs(s)
l = -70000
a4 = Abs(l)
b = 7
a5 = Abs(b)
w = 200
a6 = Abs(w)
b = 3
c = 9
m1 = Min(b, c)
m2 = Max(b, c)
i = -5
m3 = Min(i, 7)
m4 = Max(i, 7)
b = 200
m5 = Max(b, 100)
w = 1000
m6 = Max(w, 999)
l = -70000
m7 = Min(l, 5)
m8 = Max(l, 5)
i = 2
n1 = -10
Inc(n1, 5)
Dec(n1, 0)
Inc(n1, i)
Dec(n1, 2)
Dec(n1, i)
Dec(n1, 3)
n2 = 5
Inc(n2, 2)
amt = 10
n3 = 1
Inc(n3, 0)
n4 = 100
Dec(n4, amt)
Dec(n4, 40)
Inc(n4, amt)
Inc(n4, 30)
Dec(n4, 20)
