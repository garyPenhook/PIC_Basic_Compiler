' expect: TN_TN_A=10 TN_TN_B=20 TN_TN_C=1000 TN_TN_D=1 TN_TN_E=66 TN_TN_F=1 TN_TN_G=105 TN_TN_H=1 TN_TN_I=7 TN_TN_J=3 TN_TN_K=5 TN_TN_L=4 TN_TN_M=6 TN_TN_N=13
Program Tn
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim calls As Byte
Dim tn_l As Byte
Dim tn_m As Byte
Dim tn_n As Byte
Dim bt As Bit
Dim i As Byte
Dim x As Byte = 5
Dim w As Word = 300
Dim c As Char
Dim ca As Char = "A"
Dim cb As Char = "B"
Dim t As Boolean
Dim tn_a As Byte
Dim tn_b As Byte
Dim tn_c As Word
Dim tn_d As Byte
Dim tn_e As Byte
Dim tn_f As Byte
Dim tn_g As Word
Dim tn_h As Byte
Dim tn_i As Byte
Dim tn_j As Byte
Dim tn_k As Byte

Function Bump(ByVal n As Byte) As Byte
    calls = calls + 1
    Result = n
End Function

tn_a = Tern(x = 5, 10, 20)
tn_b = Tern(x <> 5, 10, 20)
tn_c = Tern(x > 3, w + 700, 0)
t = Tern(x < 9, True, False)
If t Then
    tn_d = 1
End If
c = Tern(x = 5, cb, ca)
tn_e = Byte(c)
' only the chosen branch runs
tn_i = Tern(x = 5, Bump(7), Bump(9))
tn_j = calls + 2
' inside a larger expression and a condition
tn_g = 100 + Tern(x = 5, 5, 6)
If Tern(x = 5, x > 4, x > 9) Then
    tn_f = 1
End If
tn_h = Tern(x = 5, 1, 2) + Tern(x = 6, 10, 0)
tn_k = Tern(x > 100, 1, x)
' a Bit condition, a constant condition, other statement contexts
bt = 1
tn_l = Tern(bt, 4, 8)
tn_m = Tern(True, 6, Bump(1))
tn_n = 0
For i = 0 To Tern(x = 5, 2, 9)
    tn_n = tn_n + 1
Next
If x = 0 Then
    tn_n = 99
Else
    tn_n = tn_n + 10
End If
