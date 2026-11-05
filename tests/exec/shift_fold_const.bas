' y = (x >> k) Xor K, (x << k) Or K, K And (x >> k): shift into the destination, then the constant byte by byte.
' Destination equal to, different from, or (Word from Byte) narrower than the source; signed shifts keep their sign.
' expect: T_R0=65535 T_R1=49152 T_R2=1 T_R3=9024 T_R4=4660 T_R5=0 T_R6=2147483648 T_R7=3835865116 T_R8=63
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim R0 As Word
Dim R1 As Word
Dim R2 As Word
Dim R3 As Word
Dim R4 As Word
Dim R5 As Word
Dim R6 As LongWord
Dim R7 As LongWord
Dim R8 As Integer
Dim X As Word
Dim Y As Word
Dim L As LongWord
Dim S As Integer

X = $FFFF
R0 = (X >> 0) Xor 0
Y = $8001
R1 = (Y >> 1) Or $8000
X = $1234
R2 = $0021 And (X >> 2)
R3 = (X << 4) Xor $1234 Xor $1234 Xor $0000
X = $FF00
X = (X << 8) Or $1234
R4 = X
X = $1234
R5 = (X >> 12) And $0000
L = $FFFFFFFF
L = (L >> 1) Xor $FFFFFFFF
R6 = L
L = $12345678
L = (L >> 1) Xor $EDB88320
R7 = L
S = -2
S = (S >> 1) And $003F
R8 = S
End
