' expect: T_SUM1=294 T_SUM2=1160 T_SUM3=294 T_SUM4=363 T_W1=256 T_W2=0 T_W3=0
' A routine that walks literal tables with TBLPTR (two literals share one table, one is read
' twice), and 16-bit Inc carrying out of the low byte.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim sum1 As Word
Dim sum2 As Word
Dim sum3 As Word
Dim w1 As Word
Dim w2 As Word
Dim w3 As Word
Dim sum4 As Word
Dim w As Word

Function Total(ByRefConst s As String(40)) As Word
    Dim i As Byte
    Dim c As Byte
    Dim t As Word
    i = 0
    t = 0
    While True
        c = Byte(s(i))
        If c = 0 Then
            Break
        End If
        t = t + c
        Inc(i)
    Wend
    Result = t
End Function

Function Once(ByRefConst s As String(40)) As Word
    Dim i As Byte
    Dim c As Byte
    Dim t As Word
    i = 0
    t = 0
    While True
        c = Byte(s(i))
        If c = 0 Then
            Break
        End If
        t = t + c
        Inc(i)
    Wend
    Result = t
End Function

sum1 = Total("abc")
sum2 = Total("hello, world")
sum3 = Total("abc")
sum4 = Once("xyz")
w = 255
Inc(w)
w1 = w
w = 65535
Inc(w)
w2 = w
w = 0
Repeat
    Inc(w)
Until w = 0
w3 = w
