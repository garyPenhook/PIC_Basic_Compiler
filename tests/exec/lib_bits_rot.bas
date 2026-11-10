' expect: BR_BR_A=3 BR_BR_B=49152 BR_BR_C=32772 BR_BR_D=8193 BR_BR_E=13483 BR_BR_F=1 BR_BR_G=0 BR_BR_S4=11 BR_BR_S5=5 BR_BR_S6=2 BR_BR_S7=1 BR_BR_L4=112 BR_BR_L5=224 BR_BR_L6=192 BR_BR_L7=128 BR_BR_P=1 BR_BR_N2=-19 BR_BR_N7=-1 BR_BR_P3=6
' Word rotates, SwapBytes and GetBit with run-time values (both values of the bit carried round), byte shifts by 4..7,
' signed byte shifts, and a loop that polls a bit (`While bit = 1`).
Program Br
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "bits"
Dim v As Word
Dim v2 As Word
Dim x As Byte
Dim n As Byte
Dim flags As Byte
Dim fl As flags.3
Dim br_a As Word
Dim br_b As Word
Dim br_c As Word
Dim br_d As Word
Dim br_e As Word
Dim br_f As Boolean
Dim br_g As Boolean
Dim br_s4 As Byte
Dim br_s5 As Byte
Dim br_s6 As Byte
Dim br_s7 As Byte
Dim br_l4 As Byte
Dim br_l5 As Byte
Dim br_l6 As Byte
Dim br_l7 As Byte
Dim br_p As Byte
Dim sx As ShortInt
Dim sy As ShortInt
Dim br_n2 As ShortInt
Dim br_n7 As ShortInt
Dim br_p3 As ShortInt
v = $8001
v2 = $4002
x = $B7
n = 15
br_a = Rol(v)
br_b = Ror(v)
br_c = Rol(v2)
br_d = Ror(v2)
br_e = SwapBytes($AB34 Xor v Xor $8001)
br_f = GetBit(LongWord(v) << 8, n + 8)
br_g = GetBit(LongWord(v2) << 8, n + 8)
br_s4 = x >> 4
br_s5 = x >> 5
br_s6 = x >> 6
br_s7 = x >> 7
br_l4 = x << 4
br_l5 = x << 5
br_l6 = x << 6
br_l7 = x << 7
sx = -73
sy = 55
br_n2 = sx >> 2
br_n7 = sx >> 7
br_p3 = sy >> 3
flags = 8
br_p = 0
While fl = 1
    Inc(br_p)
    flags = 0
Wend
