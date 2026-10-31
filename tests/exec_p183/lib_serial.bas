' expect: LS_BRGL=68 LS_BRGH=0 LS_TX=38 LS_RC=144 LS_BAUD=72 LS_PPS=20 LS_RXP=21 LS_SENT=1
' Serial library on the PIC16F183xx (14-pin PIC16F18326 here): SerialInit programs the EUSART and PPS registers, and writing a byte reaches TX1REG once the
' transmitter reports empty (TXIF, PIR1 bit 4). 115200 baud at 32 MHz: n = round(32e6 / (4 * 115200)) - 1 = 68. TX on RC4 (RC4PPS = 20 = 14h, TX/CK,
' DS40001839E Register 13-2 p.163), RX on RC5 (RXPPS = 21, RC5 = 10101, Register 13-1 p.162). TX1STA reads back with TRMT (bit 1) set and BAUD1CON with
' RCIDL (bit 6) set, both read-only status bits.
Program Ls
Device = 16F18326
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
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
rxp = RXPPS
Serial.SerialWrite("ok")
Serial.SerialWriteWord(1234)
Serial.SerialFlush()
sent = 1
