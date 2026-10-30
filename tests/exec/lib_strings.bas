' expect: SL_SL_A=5 SL_SL_B=0 SL_SL_C=3 SL_SL_D=0 SL_SL_E=8
Program Sl
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "strings"
Dim s As String(10) = "hello"
Dim t As String(8)
Dim big As String(100)
Dim sl_a As Byte
Dim sl_b As Byte
Dim sl_c As Byte
Dim sl_d As Byte
Dim sl_e As Byte
sl_a = Len(s)
sl_b = Len(t)
sl_c = Len("abc")
t = "xyz"
t = t + "w"
Clear(big)
sl_d = Len(big)
big = "12345678"
sl_e = Len(big)
