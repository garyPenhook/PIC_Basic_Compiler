' expect: MR_PRODUCT=3220927662 MR_FIBOUT=512559680 MR_BYTEOUT=78
Program MR
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x(4), y(4) As Integer
Dim ba(2), bb(2) As Byte
Dim i As Byte
Volatile Dim product As LongInt
Volatile Dim fibout As LongWord
Volatile Dim byteout As Byte
Dim fa, fb, ft As LongWord
x(0) = -32768
x(1) = 32767
x(2) = -1
x(3) = 1234
y(0) = -1
y(1) = -32768
y(2) = -32768
y(3) = -321
product = 0
For i = 0 To 3
    product = product + x(i) * y(i)
Next
ba(0) = 255
ba(1) = 37
bb(0) = 255
bb(1) = 9
byteout = 0
For i = 0 To 1
    byteout = byteout + ba(i) * bb(i)
Next
fa = 0
fb = 1
For i = 1 To 48
    ft = fa + fb
    fa = fb
    fb = ft
Next
' Keep the rotation's result observable without exposing its intermediate writes.
fibout = fa
