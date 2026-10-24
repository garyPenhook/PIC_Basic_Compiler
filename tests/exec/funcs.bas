' expect: T_A=7 T_B=300 T_C=24 T_D=13 T_E=65 T_F=1 T_G=11
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a As Byte
Dim b As Word
Dim c As Byte
Dim d As Byte
Dim e As Word
Dim f As Boolean
Dim g As Byte
Function Add3(ByVal x As Byte, ByVal y As Byte, ByVal z As Byte) As Byte
    Result = x + y + z
End Function
Function Twice(ByVal v As Word) As Word
    Twice = v + v
End Function
Function Fact(ByVal n As Byte) As Word
    Dim i As Byte
    Result = 1
    For i = 2 To n
        Result = Result * i
    Next
End Function
Function IsBig(ByVal v As Byte) As Boolean
    Result = v > 100
End Function
Sub Bump(ByVal by As Byte)
    g = g + by
End Sub
Function Dflt(ByVal x As Byte, ByVal y As Byte = 5) As Byte
    Result = x + y
End Function
a = Add3(1, 2, 4)
b = Twice(150)
c = Add3(Add3(1, 2, 3), Add3(4, 5, 6), 3)
d = Dflt(8)
e = Fact(4) + Twice(20) + 1
f = IsBig(200) And Not IsBig(3)
Bump(4)
Bump(7)
