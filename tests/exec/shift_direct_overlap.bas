' expect: T_L0=1 T_L1=2 T_L2=32 T_L3=48 T_R0=1 T_R1=2 T_R2=48 T_R3=0 T_U0=1 T_U1=2 T_U2=0 T_U3=2 T_V0=1 T_V1=2 T_V2=3 T_V3=0
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim A(4) As Byte
Dim B(4) As Byte
Dim C(4) As Byte
Dim D(4) As Byte
Dim M As A(1).AsWord
Dim SW As A(2).AsWord
Dim M2 As B(1).AsWord
Dim SW2 As B(2).AsWord
Dim M3 As C(1).AsWord
Dim SW3 As C(2).AsWord
Dim M4 As D(1).AsWord
Dim SW4 As D(2).AsWord
Dim L0 As Byte
Dim L1 As Byte
Dim L2 As Byte
Dim L3 As Byte
Dim R0 As Byte
Dim R1 As Byte
Dim R2 As Byte
Dim R3 As Byte
Dim U0 As Byte
Dim U1 As Byte
Dim U2 As Byte
Dim U3 As Byte
Dim V0 As Byte
Dim V1 As Byte
Dim V2 As Byte
Dim V3 As Byte
A(0) = 1
A(1) = 2
A(2) = 3
A(3) = 4
B(0) = 1
B(1) = 2
B(2) = 3
B(3) = 4
C(0) = 1
C(1) = 2
C(2) = 3
C(3) = 4
D(0) = 1
D(1) = 2
D(2) = 3
D(3) = 4
SW = M << 4
SW2 = M2 >> 4
SW3 = M3 << 8
SW4 = M4 >> 8
L0 = A(0)
L1 = A(1)
L2 = A(2)
L3 = A(3)
R0 = B(0)
R1 = B(1)
R2 = B(2)
R3 = B(3)
U0 = C(0)
U1 = C(1)
U2 = C(2)
U3 = C(3)
V0 = D(0)
V1 = D(1)
V2 = D(2)
V3 = D(3)
End
