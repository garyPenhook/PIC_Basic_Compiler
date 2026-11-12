' expect: T_B1=2 T_B2=254 T_W1=998 T_W2=65535 T_I1=-9 T_I2=32767 T_I3=32767 T_L1=4294967288 T_S1=127
' `(n - 1) - i` is evaluated as `n - (i + 1)`: the same value at every width, wrapping the same way.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim b1 As Byte
Dim b2 As Byte
Dim w1 As Word
Dim w2 As Word
Dim i1 As Integer
Dim i2 As Integer
Dim i3 As Integer
Dim l1 As LongInt
Dim s1 As ShortInt

NoInline Function DB(ByVal n As Byte, ByVal i As Byte) As Byte
    Result = n - 1 - i
End Function

NoInline Function DW(ByVal n As Word, ByVal i As Word) As Word
    Result = n - 1 - i
End Function

NoInline Function DI(ByVal n As Integer, ByVal i As Integer) As Integer
    Result = n - 1 - i
End Function

NoInline Function DL(ByVal n As LongInt, ByVal i As LongInt) As LongInt
    Result = n - 1 - i
End Function

NoInline Function DS(ByVal n As ShortInt, ByVal i As ShortInt) As ShortInt
    Result = n - 1 - i
End Function

b1 = DB(5, 2)
b2 = DB(0, 1)
w1 = DW(1000, 1)
w2 = DW(0, 0)
i1 = DI(-5, 3)
i2 = DI(32767, -1)
i3 = DI(-32768, 0)
l1 = DL(-5, 0) + DL(1, 1) + DL(0, 0)
s1 = DS(-127, 0) + DS(0, 0)
