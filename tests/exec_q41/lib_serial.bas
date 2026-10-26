' expect: LS_BRGL=138 LS_BRGH=0 LS_CON0=176 LS_CON1=128 LS_CON2=128 LS_PPS=16 LS_RXPPS=21 LS_SENT=1
' Serial library on the PIC18F16Q41: SerialInit programs UART1 and PPS, and writing a byte reaches
' U1TXB once the transmit buffer is not full. 115200 baud at 64 MHz: n = 138 (BRGS = 1). The simulator accepts the
' write but never drains the transmit buffer (TXBE and TXMTIF stay 0), so only one byte is sent and SerialFlush
' is not called.
Program Ls
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "serial"
Dim brgl As Byte
Dim brgh As Byte
Dim con0 As Byte
Dim con1 As Byte
Dim con2 As Byte
Dim pps As Byte
Dim rxpps As Byte
Dim sent As Byte
Serial.SerialInit(115200)
brgl = U1BRGL
brgh = U1BRGH
con0 = U1CON0
con1 = U1CON1
con2 = U1CON2
pps = RC4PPS
rxpps = U1RXPPS
Serial.SerialWriteByte(65)
sent = 1
