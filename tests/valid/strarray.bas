' expect: T_A=99 T_B=1 T_C=1 T_D=120 T_E=0 T_F=98 T_G=25
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim names(3) As String(12)
Dim big As String(30)
Dim s As String(12)

Dim t As String(12)
Dim a As Byte
Dim b As Boolean
Dim c As Boolean
Dim d As Byte
Dim e As Boolean
Dim f As Byte
Dim g As Byte
Dim i As Byte
Sub Show(ByRefConst x As String)
    g = Byte(x(0)) - 95
End Sub
names(1) = "abc"
s = names(1)
a = Byte(names(1)(2))
names(2) = "abc!"
i = 1
names(i) = "xy"
b = names(i) = "xy"
c = names(2) = "abc!"
d = Byte(names(i)(0))
i = 2
names(i) = names(1)
big = names(i) + "z" + names(1)
t = names(i)
e = names(0) = "q"
i = 0
names(i) = "b"
f = Byte(names(i)(0))
i = 1
Show(names(i))
