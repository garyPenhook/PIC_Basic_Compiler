' expect: L2_BRGL=138 L2_BRGH=0 L2_TX=38 L2_RC=144 L2_BAUD=72 L2_PPS=11 L2_RXPPS=15 L2_SENT=1
' Serial2 library: Serial2Init programs the EUSART2 and PPS registers. 115200 baud at 64 MHz: n = 138.
' TX2STA reads back with TRMT (bit 1) set and BAUD2CON with RCIDL (bit 6) set, both read-only status
' bits. The MDB simulator does not model EUSART2's TX2IF (PIR3 bit 6 never sets), so no byte is sent:
' a send would wait forever.
Program L2
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
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
pps = RB6PPS
rxpps = RX2PPS
sent = 1
