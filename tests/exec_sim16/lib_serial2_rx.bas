' expect: SR2_S2_A=1 SR2_S2_N=5 SR2_S2_C=104 SR2_S2_D=1 SR2_S2_V=4294967251 SR2_S2_W=1 SR2_S2_T=1 SR2_S2_E=0 SR2_S2_Z=0 SR2_S2_Q=81
' stim: lib_serial2_rx.stim.toml
' Receiving with a time limit (115200 baud, 32 MHz): a line, a decimal number inside other text, a wanted text and then
' silence, which must time out (a byte read, a number and a line) instead of waiting for ever.
Program Sr2
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "serial2"
Include "strings"
Dim s2_a As Boolean
Dim s2_n As Byte
Dim s2_c As Byte
Dim s2_d As Boolean
Dim s2_v As LongInt
Dim s2_w As Boolean
Dim s2_t As Boolean
Dim s2_e As Boolean
Dim s2_z As Boolean
Dim s2_q As Integer
Serial2Init(115200)
s2_a = Serial2ReadLine(10)
s2_n = Len(Serial2Line)
s2_c = Byte(Serial2Line(0))
s2_d = Serial2ReadDec(10)
s2_v = Serial2Number
s2_w = Serial2WaitFor("OK", 10)
s2_t = Serial2ReadTimeout(2) < 0
s2_e = Serial2ReadDec(2)
s2_z = Serial2ReadLine(2)
s2_q = Serial2ReadTimeout(30)
