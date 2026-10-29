' expect: T_R0=1 T_R1=2 T_R2=3 T_R3=3
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim A(4) As Byte
Dim y As Word
Dim M As A(1).AsWord
Dim SW As A(2).AsWord
Dim R0 As Byte
Dim R1 As Byte
Dim R2 As Byte
Dim R3 As Byte
y = 1
A(0) = 1
A(1) = 2
A(2) = 3
A(3) = 4
SW = M + y
R0 = A(0)
R1 = A(1)
R2 = A(2)
R3 = A(3)
End
