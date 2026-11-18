' expect: T_K=15 T_J=240 T_B1=1 T_B2=1 T_B3=1 T_B4=1
' C-style `& | ^ ~ ! && ||` read as And, Or, Xor, Not.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Byte
Dim k As Byte
Dim j As Byte
Dim b1 As Byte
Dim b2 As Byte
Dim b3 As Byte
Dim b4 As Byte
i = 12
k = (i & 10) | (i ^ 3)
j = ~k
b1 = 0
If !(i = 1) && k <> 0 Then
    b1 = 1
End If
b2 = 1
If i = 1 || k = 0 Then
    b2 = 0
End If
b3 = 0
If i = 1 || k = 15 Then
    b3 = 1
End If
b4 = 0
If i = 12 && k = 15 Then
    b4 = 1
End If
End
