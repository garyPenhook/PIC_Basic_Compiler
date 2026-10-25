' expect: T_ACC=60 T_CNT=2 T_FLAG=2 T_FLAG2=9 T_D=20 T_HITS=3
' Calls: a Byte argument passed in WREG (constant, variable, expression, nested call, a parameter
' read after WREG was reused, a parameter never read), and routines called from one place only,
' which are placed at the call (with a `Return` in the middle of one).
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim acc As Word
Dim cnt As Byte
Dim flag As Byte
Dim flag2 As Byte
Dim d As Byte
Dim x As Byte
Dim hits As Byte

Sub AddTo(ByVal v As Byte)
    Dim t As Byte
    t = 7
    acc = acc + v + t
End Sub

Function Dbl(ByVal v As Byte) As Byte
    Result = v + v
End Function

Sub Unused(ByVal v As Byte)
    cnt = cnt + 1
End Sub

Sub Poll(ByVal v As Byte)
    While hits < 3
        Inc(hits)
    Wend
    acc = acc + v - v
End Sub

Sub Once()
    If acc > 100 Then
        flag = 1
        Exit
    End If
    flag = 2
End Sub

Sub Once3()
    If cnt = 2 Then
        flag2 = 9
        Exit
    End If
    flag2 = 1
End Sub

x = 10
AddTo(1)
AddTo(x)
AddTo(Dbl(3))
AddTo(Byte(x + 5))
Unused(5)
Unused(x)
d = Dbl(x)
Poll(4)
Poll(x)
Once()
Once3()
