' Word << 4 and >> 4 into another variable (nibble swap) and in place (loop)
' expect: T_L0=0 T_R0=0 T_P0=0 T_L1=16 T_R1=0 T_P1=16 T_L2=240 T_R2=0
' expect: T_P2=240 T_L3=256 T_R3=1 T_P3=256 T_L4=4080 T_R4=15 T_P4=4080 T_L5=4096
' expect: T_R5=16 T_P5=4096 T_L6=65520 T_R6=255 T_P6=65520 T_L7=0 T_R7=256 T_P7=0
' expect: T_L8=9024 T_R8=291 T_P8=9024 T_L9=0 T_R9=2048 T_P9=0 T_L10=48336 T_R10=2748
' expect: T_P10=48336 T_L11=65520 T_R11=4095 T_P11=65520 T_L12=61680 T_R12=240 T_P12=61680 T_L13=3840
' expect: T_R13=3855 T_P13=3840
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim X0 As Word
Dim L0 As Word
Dim R0 As Word
Dim P0 As Word
Dim X1 As Word
Dim L1 As Word
Dim R1 As Word
Dim P1 As Word
Dim X2 As Word
Dim L2 As Word
Dim R2 As Word
Dim P2 As Word
Dim X3 As Word
Dim L3 As Word
Dim R3 As Word
Dim P3 As Word
Dim X4 As Word
Dim L4 As Word
Dim R4 As Word
Dim P4 As Word
Dim X5 As Word
Dim L5 As Word
Dim R5 As Word
Dim P5 As Word
Dim X6 As Word
Dim L6 As Word
Dim R6 As Word
Dim P6 As Word
Dim X7 As Word
Dim L7 As Word
Dim R7 As Word
Dim P7 As Word
Dim X8 As Word
Dim L8 As Word
Dim R8 As Word
Dim P8 As Word
Dim X9 As Word
Dim L9 As Word
Dim R9 As Word
Dim P9 As Word
Dim X10 As Word
Dim L10 As Word
Dim R10 As Word
Dim P10 As Word
Dim X11 As Word
Dim L11 As Word
Dim R11 As Word
Dim P11 As Word
Dim X12 As Word
Dim L12 As Word
Dim R12 As Word
Dim P12 As Word
Dim X13 As Word
Dim L13 As Word
Dim R13 As Word
Dim P13 As Word

X0 = 0
L0 = X0 << 4
R0 = X0 >> 4
P0 = X0
P0 = P0 << 4
X1 = 1
L1 = X1 << 4
R1 = X1 >> 4
P1 = X1
P1 = P1 << 4
X2 = 15
L2 = X2 << 4
R2 = X2 >> 4
P2 = X2
P2 = P2 << 4
X3 = 16
L3 = X3 << 4
R3 = X3 >> 4
P3 = X3
P3 = P3 << 4
X4 = 255
L4 = X4 << 4
R4 = X4 >> 4
P4 = X4
P4 = P4 << 4
X5 = 256
L5 = X5 << 4
R5 = X5 >> 4
P5 = X5
P5 = P5 << 4
X6 = 4095
L6 = X6 << 4
R6 = X6 >> 4
P6 = X6
P6 = P6 << 4
X7 = 4096
L7 = X7 << 4
R7 = X7 >> 4
P7 = X7
P7 = P7 << 4
X8 = 4660
L8 = X8 << 4
R8 = X8 >> 4
P8 = X8
P8 = P8 << 4
X9 = 32768
L9 = X9 << 4
R9 = X9 >> 4
P9 = X9
P9 = P9 << 4
X10 = 43981
L10 = X10 << 4
R10 = X10 >> 4
P10 = X10
P10 = P10 << 4
X11 = 65535
L11 = X11 << 4
R11 = X11 >> 4
P11 = X11
P11 = P11 << 4
X12 = 3855
L12 = X12 << 4
R12 = X12 >> 4
P12 = X12
P12 = P12 << 4
X13 = 61680
L13 = X13 << 4
R13 = X13 >> 4
P13 = X13
P13 = P13 << 4
End
