' expect: T_A1=1500 T_A2=-1500 T_A3=1500 T_A4=-1500 T_A5=44104 T_A6=-5 T_A7=0 T_A8=-32768 T_A9=-32768 T_B1=-100 T_B2=1275 T_B3=-1275 T_B4=18 T_B5=-300 T_C1=-35 T_C2=-1200 T_C3=300 T_C4=900 T_C3=300 T_C4=900
' expect-O0: T_A1=1500 T_A2=-1500 T_A3=1500 T_A4=-1500 T_A5=44104 T_A6=-5 T_A7=0 T_A8=-32768 T_A9=-32768 T_B1=-100 T_B2=1275 T_B3=-1275 T_B4=18 T_B5=-300 T_C1=-35 T_C2=-1200 T_C3=300 T_C4=900 T_C3=300 T_C4=900
' Integer * Byte (either order) is two hardware multiplies; sign and wrap-around must match the 16-bit product.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a1 As Integer
Dim a2 As Integer
Dim a3 As Integer
Dim a4 As Integer
Dim a5 As Word
Dim a6 As Integer
Dim a7 As Integer
Dim a8 As Integer
Dim a9 As Integer
Dim b1 As Integer
Dim b2 As Integer
Dim b3 As Integer
Dim b4 As Integer
Dim b5 As Integer
Dim gi As Integer
Dim gb As Byte
Dim cnt As Byte
Dim c1 As Integer
Dim c2 As Integer
Dim c3 As Integer
Dim c4 As Integer

NoInline Function IxB(ByVal x As Integer, ByVal y As Byte) As Integer
    Result = x * y
End Function

NoInline Function BxI(ByVal y As Byte, ByVal x As Integer) As Integer
    Result = y * x
End Function

NoInline Function WxB(ByVal x As Word, ByVal y As Byte) As Word
    Result = x * y
End Function

' the byte is an expression, the wide operand a variable
NoInline Function IxExpr(ByVal x As Integer, ByVal y As Byte) As Integer
    Result = x * (y + 1)
End Function

' the wide operand is an expression, the byte a variable
NoInline Function ExprxB(ByVal x As Integer, ByVal y As Byte) As Integer
    Result = (x + 1) * y
End Function

Function Next1() As Byte
    cnt = cnt + 1
    Result = cnt
End Function

' a call in the wide operand changes the byte: the byte is read first (left operand) or after (right operand)
Function Change() As Integer
    gb = 9
    Result = 100
End Function

NoInline Function Acc(ByVal y As Byte) As Integer
    gi = gi * y
    Result = gi
End Function

a1 = IxB(300, 5)
a2 = IxB(-300, 5)
a3 = BxI(5, 300)
a4 = BxI(5, -300)
a5 = WxB(45000, 17)
a6 = IxB(-1, 5)
a7 = IxB(256, 0)
a8 = IxB(-32768, 1)
a9 = IxB(16384, 2)
b1 = IxB(-100, 1)
b2 = IxB(255, 5)
b3 = IxB(-255, 5)
cnt = 0
b4 = IxExpr(3, 5)
b5 = ExprxB(-101, 3)
gi = -7
c1 = Acc(5)
c2 = IxB(-300, Next1() + 3)
gb = 3
c3 = gb * Change()
gb = 3
c4 = Change() * gb
End
