' expect: T_R=120 T_B=33 T_C=7 T_D=121 T_E=2
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Structure TS
    Tag As String(4)
    V As Byte
End Structure
Dim a(3) As TS
Dim i As Byte
Dim s As String(12)
Dim r As Byte
Dim b As Byte
Dim c As Byte
Dim d As Byte
Dim e As Byte
i = 1
a(i).Tag = "x"
a(i).V = 7
i = 2
a(i).Tag = "yz"
s = a(1).Tag + "!"
i = 1
s = a(i).Tag + "!"
r = Byte(a(i).Tag(0))
b = Byte(s(1))
c = a(i).V
i = 2
d = Byte(a(i).Tag(0))
e = Byte(a(i).V) + 2
