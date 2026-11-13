' expect: SR_SR_A=1 SR_SR_N=5 SR_SR_C=104 SR_SR_D=1 SR_SR_V=4294967251 SR_SR_W=1 SR_SR_T=1 SR_SR_E=0 SR_SR_Z=0 SR_SR_Q=81
' stim: lib_serial_rx.stim.toml
' Receiving with a time limit (115200 baud, 64 MHz): a line, a decimal number inside other text, a wanted text and then
' silence, which must time out (a byte read, a number and a line) instead of waiting for ever.
Program Sr
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "serial"
Include "strings"
Dim sr_a As Boolean
Dim sr_n As Byte
Dim sr_c As Byte
Dim sr_d As Boolean
Dim sr_v As LongInt
Dim sr_w As Boolean
Dim sr_t As Boolean
Dim sr_e As Boolean
Dim sr_z As Boolean
Dim sr_q As Integer
SerialInit(115200)
sr_a = SerialReadLine(10)
sr_n = Len(SerialLine)
sr_c = Byte(SerialLine(0))
sr_d = SerialReadDec(10)
sr_v = SerialNumber
sr_w = SerialWaitFor("OK", 10)
sr_t = SerialReadTimeout(2) < 0
sr_e = SerialReadDec(2)
sr_z = SerialReadLine(2)
sr_q = SerialReadTimeout(30)
