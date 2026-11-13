' expect: FT_FT_A=1 FT_FT_B=1 FT_FT_C=1 FT_FT_D=1 FT_FT_E=1 FT_FT_F=1 FT_FT_G=1 FT_FT_H=1 FT_FT_I=1 FT_FT_J=1 FT_FT_K=1 FT_FT_L=1 FT_FT_M=1 FT_FT_N=1 FT_FT_O=1
Program Ft
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "format"
Dim b As Byte
Dim w As Word
Dim l As LongWord
Dim sb As ShortInt
Dim si As Integer
Dim sl As LongInt
Dim ft_a As Boolean
Dim ft_b As Boolean
Dim ft_c As Boolean
Dim ft_d As Boolean
Dim ft_e As Boolean
Dim ft_f As Boolean
Dim ft_g As Boolean
Dim ft_h As Boolean
Dim ft_i As Boolean
Dim ft_j As Boolean
Dim ft_k As Boolean
Dim ft_l As Boolean
Dim ft_m As Boolean
Dim ft_n As Boolean
Dim ft_o As Boolean
b = 42
FmtDec(b, 5, "0")
ft_a = FmtBuf = "00042"
FmtDec(b, 0, "0")
ft_b = FmtBuf = "42"
FmtDec(Byte(0), 3, " ")
ft_c = FmtBuf = "  0"
w = 65535
FmtDec(w, 7, " ")
ft_d = FmtBuf = "  65535"
FmtDec(w, 2, "0")
ft_e = FmtBuf = "65535"
l = 4000000000
FmtDec(l, 12, "0")
ft_f = FmtBuf = "004000000000"
sb = -5
FmtSDec(sb, 4, " ")
ft_g = FmtBuf = "  -5"
si = -1234
FmtSDec(si, 7, "0")
ft_h = FmtBuf = "-001234"
FmtSDec(si, 0, " ")
ft_i = FmtBuf = "-1234"
sl = -2000000000
FmtSDec(sl, 0, "0")
ft_j = FmtBuf = "-2000000000"
FmtSDec(si, 3, " ")
si = 77
FmtSDec(si, 4, "0")
ft_k = FmtBuf = "0077"
FmtHex(Byte($2A), 4)
ft_l = FmtBuf = "002A"
w = $BEEF
FmtHex(w, 4)
ft_m = FmtBuf = "BEEF"
l = $DEADBEEF
FmtHex(l, 8)
FmtBin(Byte(5), 8)
ft_n = FmtBuf = "00000101"
FmtBin(w, 3)
ft_o = FmtBuf = "111"
