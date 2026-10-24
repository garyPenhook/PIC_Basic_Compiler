' expect: T_B=39 T_C=4 T_K=6 T_W=2540 T_V=300 T_L=310000 T_M=70000 T_I=65528 T_J=3 T_B2=7
' In-place read-modify-write: `x = x op <expression>` and `x = <expression> op x` fold the
' operand straight into x. The operand may mention x itself or wrap around.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim b As Byte
Dim c As Byte
Dim k As Byte
Dim w As Word
Dim v As Word
Dim l As LongWord
Dim m As LongWord
Dim i As Integer
Dim j As Integer
Dim b2 As Byte
Function F(ByVal x As Byte) As Byte
    Result = x + 1
End Function
c = 4
b = 5
b = b + c * 3
b = c * 3 + b
b = b - c * 2
b = b And (c Or 3)
b = (c Xor 8) Or b
b = b + (b << 1)
k = 250
k = k + c * 3
v = 300
w = 1000
w = w + v * 3
w = (v << 2) + w
w = w - v * 2
w = w Or (v And 255)
m = 70000
l = 100000
l = l + m * 2
l = m * 3 + l
l = l - m * 2
i = -5
j = 3
i = i + j * 4
i = i - j * 5
b2 = 3
b2 = b2 + F(b2)
