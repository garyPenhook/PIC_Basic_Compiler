' expect: LS_BRGL=68 LS_BRGH=0 LS_TX=38 LS_RC=144 LS_BAUD=72 LS_PPS=19 LS_RXPPS=21 LS_SENT=1
' Serial library: SerialInit programs the EUSART and PPS registers, and writing a byte reaches
' TX1REG once the transmitter reports empty (TXIF). 115200 baud at 32 MHz: n = round(32e6 / (4 * 115200)) - 1 = 68. TX on RC4 (RC4PPS = 19, TX1/CK1, DS40002343F Table 18-2),
' RX on RC5 (RX1PPS = 21, port C = 010, pin 5, Table 18-1). TX1STA reads
' back with TRMT (bit 1) set and BAUD1CON with RCIDL (bit 6) set, both read-only status bits.
Program Ls
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
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
pps = RC4PPS
rxpps = RX1PPS
Serial.SerialWrite("ok")
Serial.SerialWriteWord(1234)
Serial.SerialFlush()
sent = 1
