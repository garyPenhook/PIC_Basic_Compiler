' expect: SZ_SZ_A=150 SZ_SZ_B=2 SZ_SZ_C=4 SZ_SZ_D=9 SZ_SZ_E=9 SZ_SZ_F=300 SZ_SZ_G=3
Program Sz
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Structure Pt
    x As Word
    y As Byte
End Structure
Dim b As Byte
Dim w As Word
Dim l As LongInt
Dim s As String(8)
Dim arr(10) As Byte
Dim big(150) As Word
Dim p As Pt
Dim sz_a As Byte
Dim sz_b As Byte
Dim sz_c As Byte
Dim sz_d As Byte
Dim sz_e As Byte
Dim sz_f As Word
Dim sz_g As Byte
sz_a = SizeOf(b)
sz_b = SizeOf(w)
sz_c = SizeOf(l)
sz_d = SizeOf(s)
sz_e = SizeOf(arr) - 1
sz_f = SizeOf(big)
sz_g = SizeOf(p)
sz_a = SizeOf(big) / SizeOf(big(0))
