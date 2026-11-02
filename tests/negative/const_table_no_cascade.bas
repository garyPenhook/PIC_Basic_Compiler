' expect: E-CONST-RANGE
Program T
Device = 18F27Q10
Const T(300) As Byte = Table(i, i + 1)
Dim x As Byte
x = T(2)
