' expect: LS_BRGL=138 LS_BRGH=0 LS_TX=38 LS_RC=144 LS_BAUD=72 LS_PPS=9 LS_RXPPS=23 LS_SENT=1
' Serial library: SerialInit programs the EUSART and PPS registers, and writing a byte reaches
' TX1REG once the transmitter reports empty (TXIF). 115200 baud at 64 MHz: n = 138. TX1STA reads
' back with TRMT (bit 1) set and BAUD1CON with RCIDL (bit 6) set, both read-only status bits.
Program Ls
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "serial"
Dim brgl As Byte
Dim brgh As Byte
Dim tx As Byte
Dim rc As Byte
Dim baud As Byte
Dim pps As Byte
Dim rxpps As Byte
Dim sent As Byte
Serial.SerialInit(115200)
brgl = SP1BRGL
brgh = SP1BRGH
tx = TX1STA
rc = RC1STA
baud = BAUD1CON
pps = RC6PPS
rxpps = RX1PPS
Serial.SerialWrite("ok")
Serial.SerialWriteWord(1234)
Serial.SerialFlush()
sent = 1
