' expect: PC_R1=40 PC_R2=3 PC_R3=7 PC_R4=1 PC_R5=2 PC_R6=9 PC_R7=64
Program Pc
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
' #constant is a compile-time value: #if can test it and the program can use it as a Const
#constant Width = 8
#constant Size = Width * 5
#constant Mask = (1 << Width) - 1
#constant Fast = _clock >= 32
#define Level 3
#define Plain
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Byte
Dim r7 As Byte
r1 = Size
#if Mask = 255 and Width * 2 = 16
r4 = 1
#else
r4 = 99
#endif
#if Level > 2
r2 = Size - 37
#endif
#if Size / 4 < 10 or Plain
r3 = Width - 1
#endif
#if Fast
r5 = 2
#else
r5 = 3
#endif
#if Width mod 3 = 2
r6 = 9
#endif
#if _clock = 64
r7 = Size + Width * 3
#endif
End
