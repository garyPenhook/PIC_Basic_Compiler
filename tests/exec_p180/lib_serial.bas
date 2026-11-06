' expect: LS_BRGL=68 LS_BRGH=0 LS_TX=38 LS_RC=144 LS_BAUD=72 LS_PPS=14 LS_RXP=23 LS_SENT=1
' Serial library on the PIC16F18056 (DS40002325C): SerialInit programs the EUSART and PPS registers, and writing a byte reaches TX1REG once TXIF (PIR3 bit 2) is set. 115200 baud at 32 MHz: n = round(32e6 / (4 * 115200)) - 1 = 68.
' TX on RC6 (RC6PPS = 14, TX1/CK1, Table 18-2 p.170), RX on RC7 (RX1PPS = 23, RC7 = 010 111, 18.8.1 p.173). TX1STA reads back with TRMT (bit 1) set and BAUD1CON with RCIDL (bit 6) set, both read-only status bits.
Program Ls
Device = 16F18056
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHZ, WDTE = OFF, LVP = ON
Include "serial"
Dim brgl As Byte
Dim brgh As Byte
Dim tx As Byte
Dim rc As Byte
Dim baud As Byte
Dim pps As Byte
Dim rxp As Byte
Dim sent As Byte
Serial.SerialInit(115200)
brgl = SP1BRGL
brgh = SP1BRGH
tx = TX1STA
rc = RC1STA
baud = BAUD1CON
pps = RC6PPS
rxp = RX1PPS
Serial.SerialWrite("ok")
Serial.SerialWriteWord(1234)
Serial.SerialFlush()
sent = 1
