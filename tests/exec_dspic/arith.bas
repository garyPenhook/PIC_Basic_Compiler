' expect: ARITH_A=44 ARITH_B=60000 ARITH_C=-35 ARITH_D=300000 ARITH_E=-14285 ARITH_F=55
Program Arith
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW

Dim a As Byte
Dim b As Word
Dim c As Integer
Dim d As LongWord
Dim e As LongInt
Dim f As Byte
Dim i As Byte

a = 200
a = a + 100
b = 1000
b = b * 60
c = -5
c = c * 7
d = 100000
d = d * 3
e = -100000
e = e / 7
f = 0
For i = 1 To 10
    f = f + i
Next
Terminate
