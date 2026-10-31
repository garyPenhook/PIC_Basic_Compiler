' expect: LS_BRGL=68 LS_BRGH=0 LS_TX=38 LS_RC=144 LS_BAUD=72 LS_PPS=5 LS_RXP=21 LS_SENT=1
' Serial library on the PIC16F152xx (20-pin PIC16F15244 here): SerialInit programs the EUSART and PPS registers, and writing a byte reaches TX1REG once the shift register is empty
' (TRMT, erratum 1.3.1 of DS80000918K). 115200 baud at 32 MHz: n = round(32e6 / (4 * 115200)) - 1 = 68. TX on RC4 (RC4PPS = 5, TX1/CK1, DS40002195E Table 18-2 p.148), RX on RC5 (RX1PPS = 21,
' RC5 = 010 101, 18.8.1 p.151). TX1STA reads back with TRMT (bit 1) set and BAUD1CON with RCIDL (bit 6) set, both read-only status bits.
Program Ls
Device = 16F15244
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
pps = RC4PPS
rxp = RX1PPS
Serial.SerialWrite("ok")
Serial.SerialWriteWord(1234)
Serial.SerialFlush()
sent = 1
