' expect: T_A=120 T_B=21 T_C=1 T_E=5040 T_F=36 T_G=15
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a As Word
Dim b As Word
Dim c As Boolean
Dim e As Word
Dim f As Byte
Dim g As Byte
Reentrant Function Fact(ByVal n As Byte) As Word
    If n <= 1 Then
        Result = 1
    Else
        Result = Fact(n - 1) * n
    End If
End Function
Reentrant Function Fib(ByVal n As Byte) As Word
    Dim t As Word
    If n < 2 Then
        Result = n
    Else
        t = Fib(n - 1)
        Result = t + Fib(n - 2)
    End If
End Function
Reentrant Function SumTo(ByVal n As Byte, ByVal acc As Byte) As Byte
    Dim keep As Byte
    keep = n
    If n = 0 Then
        Result = acc
    Else
        Result = SumTo(n - 1, acc + keep) - 0
    End If
End Function
Reentrant Sub Down(ByVal n As Byte)
    g = g + n
    If n > 0 Then
        Down(n - 1)
    End If
End Sub
a = Fact(5)
b = Fib(8)
c = True
e = Fact(7)
f = SumTo(8, 0)
Down(5)
