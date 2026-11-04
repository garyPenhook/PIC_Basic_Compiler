' expect: BT_BT_A=137 BT_BT_B=1 BT_BT_C=0 BT_BT_D=33 BT_BT_E=4 BT_BT_F=72 BT_BT_G=195 BT_BT_H=22359 BT_BT_I=4 BT_BT_J=3 BT_BT_K=5 BT_BT_L=1000 BT_BT_M=255 BT_BT_N=7 BT_BT_O=1 BT_BT_P=0 BT_BT_Q=33153 BT_BT_R=32768 BT_BT_S=2147483648 BT_BT_T=13483 BT_BT_U=8192
' devices: 18F27Q10
Program Bt
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "bits"
Dim x As Byte
Dim w As Word
Dim bt_a As Byte
Dim bt_b As Boolean
Dim bt_c As Boolean
Dim bt_d As Byte
Dim bt_e As Byte
Dim bt_f As Byte
Dim bt_g As Byte
Dim bt_h As Word
Dim bt_i As Byte
Dim bt_j As Byte
Dim bt_k As Byte
Dim bt_l As Word
Dim bt_m As Byte
Dim bt_n As Byte
Dim bt_o As Boolean
Dim bt_p As Byte
Dim bt_q As Word
Dim bt_r As Word
Dim bt_s As LongWord
Dim bt_t As Word
Dim bt_u As Word
x = $A1
x = SetBit(x, 3)
x = ClearBit(x, 0)
x = LoadBit(x, 5, 0)
x = LoadBit(x, 0, 1)
bt_a = x
bt_b = GetBit(x, 7)
bt_c = GetBit(x, 6)
bt_d = SetBit(Byte(1), 5) Or ClearBit(Byte(1), 9)
bt_e = Ncd(8)
bt_f = Ror(Byte(%10010000))
bt_g = SwapNibbles($3C)
w = $ABAB
bt_h = Rol(w)
bt_i = Dig(1234, 0)
bt_j = Dig(1234, 1)
bt_k = Dig(5, 0)
bt_l = ISqr(1000000)
bt_m = ISqr(65535)
bt_n = Ncd(100)
Seed(1)
bt_o = Random() <> Random()
bt_p = Dcd(40)
Seed(0)
bt_q = Random()
bt_r = SetBit(Word(0), 15)
bt_s = SetBit(LongWord(0), 31)
bt_t = SwapBytes($AB34)
bt_u = Ror(Word(1)) Xor ClearBit(Word($8000), 15) Xor $A000
