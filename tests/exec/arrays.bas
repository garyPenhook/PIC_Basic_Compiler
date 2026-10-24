' expect: ARRAYS_SUM=45 ARRAYS_C=7 ARRAYS_D=6 ARRAYS_E=1554 ARRAYS_M=70000 ARRAYS_N=1501
Program Arrays
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim b(10) As Byte
Dim w(4) As Word
Dim l(3) As LongWord
Dim i As Byte
Dim sum As Byte
Dim c As Byte
Dim d As Byte
Dim e As Word
Dim k As Byte
Dim m As LongWord
Dim n As Word
For i = 0 To 9
    b(i) = i
Next
For i = 0 To 9
    sum = sum + b(i)
Next
w(2) = 1500
k = 2
e = w(k)
l(k) = 70000
l(0) = l(k)
c = b(3) + b(4)
Inc(b(5))
d = b(5)
Inc(w(k))
w(1) = w(k) - 1500
e = e + w(1) + 53
m = l(0)
n = w(2)
