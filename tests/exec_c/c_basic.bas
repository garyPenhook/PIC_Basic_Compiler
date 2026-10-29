' expect: T_X=41 T_W=1041 T_L=100012 T_Y=82 T_F=205 T_X2=41
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF
CFile "c_basic.c"
Extern Function bump() As Byte
Extern Function add(a As Byte, b As Word) As Word
Extern Function mix(a As Integer, b As LongInt, c As Byte) As LongInt
Extern Function fill(n As Byte) As Word
Extern Sub setit(v As Byte)
Dim x As Byte
Dim y As Byte
Dim x2 As Byte
Dim f As Word
Dim w As Word
Dim big(30) As Byte
Dim l As LongInt
setit(40)
x = bump()
y = bump() + 40
w = add(x, 1000)
l = mix(-5, 100000, 7)
big(29) = 9
f = fill(10)
x2 = x
