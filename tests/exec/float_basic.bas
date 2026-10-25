' expect: FT_Y=1077936128 FT_Z=1065353216 FT_W=3225419776 FT_F1=3227516928 FT_N1=3 FT_N2=3 FT_N3=253 FT_B1=1 FT_B2=0 FT_B3=1 FT_B4=1 FT_F2=1075838976 FT_F3=1075838976 FT_N4=77 FT_S=1084227584 FT_F5=1069547520 FT_F6=1232348160 FT_N5=0 FT_X=1069547520 FT_AB=1077936128
Program Ft
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x As Float = 1.5
Dim ab, y, z, w, f1, f2, f3, s, f5, f6 As Float
Dim a(3) As Float
Dim k As Integer = -7
Dim n1, n2, n3, n4, n5, i As Byte
Dim b1, b2, b3, b4 As Boolean

Function Half(ByVal v As Float) As Float
    Result = v * 0.5
End Function

y = x + x
z = y / 3
w = -y
f1 = k * 0.5
n1 = Byte(y)
n2 = Byte(-f1)
n3 = Byte(f1)
b1 = x < y
b2 = x > y
b3 = x = 1.5
b4 = y >= 3
f2 = Half(5)
a(1) = 2.5
f3 = a(1) + a(2)
If x < 2 Then
    n4 = 77
End If
s = 0
For i = 1 To 10
    s = s + 0.5
Next
f5 = Float(n1) / 2
f6 = 1000 * 1000
ab = Abs(w)
n5 = 0
If x > y Then
    n5 = 1
End If
