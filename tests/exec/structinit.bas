' expect: T_A=7 T_B=1000 T_C=1 T_D=104 T_E=0 T_F=50 T_G=9
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Structure Pt
    x As Byte
    y As Word
    on As Boolean
    tag As String(4)
    z As Byte
End Structure
Structure One
    v As Byte
End Structure
Dim p As Pt = (7, 1000, True, "hi", 0)
Dim o As One = (9)
Dim a As Byte
Dim b As Word
Dim c As Boolean
Dim d As Byte
Dim e As Byte
Dim f As Byte
Dim g As Byte
Sub Local()
    Dim q As Pt = (50, 2, False, "z", 3)
    f = q.x
End Sub
a = p.x
b = p.y
c = p.on
d = Byte(p.tag(0))
e = p.z
Local()
g = o.v
