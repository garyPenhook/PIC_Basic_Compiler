' expect: T_A=16 T_B=5 T_C=5 T_D=0 T_E=0 T_F=16 T_G=36 T_H=16 T_I=4
' Frame overlay: sibling routines share storage, so locals and Result are cleared on entry
' and nothing a caller needs may live in a callee's frame.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a As Byte
Dim b As Byte
Dim c As Byte
Dim d As Byte
Dim e As Byte
Dim f As Byte
Dim g As Byte
Dim h As Byte
Dim i As Byte
Function F1(ByVal x As Byte) As Byte
    Dim t As Byte
    t = x + 1
    Result = t * 2
End Function
Function F2(ByVal x As Byte) As Byte
    Dim t As Byte
    t = x + 10
    Result = t
End Function
Sub Dirty()
    Dim n As Byte
    Dim q(4) As Byte
    n = 99
    q(0) = 7
    q(1) = 7
    q(2) = 7
    q(3) = 7
End Sub
Function Z() As Byte
    Dim n As Byte
    n = n + 5
    Result = n
End Function
Function ZA() As Byte
    Dim q(4) As Byte
    Result = q(0) + q(1) + q(2) + q(3)
End Function
Function NoRes() As Byte
    Dim u As Byte
    u = 1
End Function
Function Inner(ByVal x As Byte) As Byte
    Dim t As Byte
    t = x * 2
    Result = t + 1
End Function
Function Mid(ByVal x As Byte) As Byte
    Dim m As Byte
    m = x + 1
    Result = Inner(m) + m
End Function
Function Outer(ByVal x As Byte) As Byte
    Dim o As Byte
    o = x
    Result = Mid(o) + o
End Function
Function Sum3() As Byte
    Dim k As Byte
    Dim s As Byte
    For k = 1 To 3
        s = s + F1(k)
    Next
    Result = s
End Function
Function Add2(ByVal x As Byte, ByVal y As Byte) As Byte
    Result = x + y
End Function
a = F1(1) + F2(2)
b = Z()
Dirty()
c = Z()
Dirty()
d = ZA()
e = F2(2)
e = NoRes()
f = Outer(3)
g = Sum3() + Sum3()
h = Add2(F1(1), F2(2))
i = F1(1)
