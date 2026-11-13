' expect: BRI_BRI_A=60 BRI_BRI_B=7 BRI_BRI_C=1 BRI_BRI_D=1
Program Bri
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim big(300) As Byte
Dim small(8) As Byte = (1, 2, 3, 4, 5, 6, 7, 8)
Dim bri_a As Byte
Dim bri_b As Byte
Dim bri_c As Byte
Dim bri_d As Byte
Dim i As Byte
Function Sum(ByRef a() As Byte, ByVal n As Byte) As Byte
    Dim k As Byte
    Dim t As Byte
    t = 0
    For k = 0 To n - 1
        t = t + a(k)
    Next
    Result = t
End Function
Sub Put(ByRef a() As Byte, ByVal k As Byte, ByVal v As Byte)
    a(k) = v
    a(k - 1) = v + 1
End Sub
Function Fetch(ByRef a() As Byte, ByVal k As Byte) As Byte
    Result = a(k)
End Function
Put(big, 255, 9)
Put(big, 3, 4)
bri_a = Sum(small, 8) + 24
bri_b = Fetch(small, 6)
If big(255) = 9 Then
    bri_c = 1
EndIf
If big(254) = 10 Then
    bri_d = 1
EndIf
