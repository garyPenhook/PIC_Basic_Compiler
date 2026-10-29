' expect: L2_BRGL=68 L2_BRGH=0 L2_TX=38 L2_RC=144 L2_BAUD=72 L2_PPS=22 L2_RXPPS=17 L2_SENT=1
' Serial2 library on the PIC16F17146: EUSART2, TX on RC2 (RC2PPS = 22, TX2/CK2) and RX on RC1 (RX2PPS = 17, DS40002343F Tables 18-1 and 18-2). 115200 baud at 32 MHz: n = 68.
' TX2STA reads back with TRMT (bit 1) set and BAUD2CON with RCIDL (bit 6) set, both read-only status bits.
Program L2
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "serial2"
Dim brgl As Byte
Dim brgh As Byte
Dim tx As Byte
Dim rc As Byte
Dim baud As Byte
Dim pps As Byte
Dim rxpps As Byte
Dim sent As Byte
Serial2.Serial2Init(115200)
brgl = SP2BRGL
brgh = SP2BRGH
tx = TX2STA
rc = RC2STA
baud = BAUD2CON
pps = RC2PPS
rxpps = RX2PPS
Serial2.Serial2Write("ok")
Serial2.Serial2WriteWord(1234)
Serial2.Serial2Flush()
sent = 1
