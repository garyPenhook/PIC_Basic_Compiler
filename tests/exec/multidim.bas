' expect: T_A=23 T_B=12 T_C=6 T_D=53 T_E=3
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim m(3, 4) As Byte
Dim w(2, 3) As Word = (1, 2, 3, 4, 5, 6)
Dim a As Byte
Dim b As Byte
Dim c As Byte
Dim d As Word
Dim e As Byte
Dim i As Byte
Dim j As Byte
For i = 0 To 2
    For j = 0 To 3
        m(i, j) = i * 10 + j
    Next
Next
i = 3
j = 4
a = m(2, 3)
m(1, 1) = 12
b = m(1, 1)
c = m(i - 1, j - 3) - 15
d = w(1, 2) + w(0, i - 1) + 44
e = m(0, 3)
