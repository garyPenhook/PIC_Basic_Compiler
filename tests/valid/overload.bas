' expect: T_A=7 T_B=600 T_C=9 T_D=97 T_E=15
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a As Byte
Dim b As Word
Dim c As Byte
Dim d As Byte
Dim e As Byte
Dim w As Word
Dim bb As Byte
Dim s As String(8)
Function Twice(ByVal v As Byte) As Byte
    Result = v + v
End Function
Function Twice(ByVal v As Word) As Word
    Result = v + v
End Function
Function Add(ByVal x As Byte, ByVal y As Byte) As Byte
    Result = x + y
End Function
Function Add(ByVal x As Byte, ByVal y As Byte, ByVal z As Byte) As Byte
    Result = x + y + z
End Function
Function Len2(ByRefConst t As String) As Byte
    Result = Byte(t(0))
End Function
Function Len2(ByVal n As Byte) As Byte
    Result = n
End Function
w = 300
bb = 3
a = Twice(bb) + 1
b = Twice(w)
c = Add(3, 2, 4)
s = "abc"
d = Len2(s)
e = Add(bb, 5) + Len2(7)
