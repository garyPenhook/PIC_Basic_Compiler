' expect: T_I1=258 T_I2=252 T_R=0 T_E=0 T_BIG=7
' Regressions from review: code after a skip instruction runs on one path only; Result is zero
' when the routine exits before assigning it; objects over 256 bytes still get placed.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim s As ShortInt
Dim i1 As Integer
Dim i2 As Integer
Dim r As Byte
Dim e As Byte
Dim big As Byte
Dim buf(300) As Byte
Function G(ByVal x As Byte) As Byte
    Result = x
End Function
Function Q(ByVal x As Byte) As Byte
    If x = 3 Then
        Exit
    End If
    Result = 5
End Function
s = 3
i1 = s + 255
s = -3
i2 = s + 255
r = G(1)
r = Q(3)
e = Q(3)
buf(299) = 7
big = buf(299)
