Program T
Device = 18F27Q10
Const A = 5
Const B = A * 2 + 1
Const C As Word = 1000
Const D = A << 4
Const E = Not $0F
Const F = B > 10
Const G = "text"
Const H = 3.5
Dim x As Byte
Dim y(B) As Byte
x = B
y(0) = D
