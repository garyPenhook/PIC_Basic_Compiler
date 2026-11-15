' expect: K2_BRG=103 K2_TX=38 K2_RC=144 K2_BAUD=72 K2_TRIS=192 K2_ANS=0 K2_SENT=1
' EUSART2 on the 40/44-pin PIC18(L)F2x/4xK22 (DS40001412H chapter 16): TX2 on RD6 and RX2 on RD7 (Table 3 p.7), both TRIS bits set and
' ANSELD bits 6 and 7 cleared; 9600 baud at 4 MHz with BRG16 = BRGH = 1: n = 4 MHz / (4 * 9600) - 1 = 103 in SPBRGH2:SPBRG2.
' devices: 18F45K22
Program K2
Device = 18F45K22
Clock = 4
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "serial2"
Dim brg As Byte
Dim tx As Byte
Dim rc As Byte
Dim baud As Byte
Dim tris As Byte
Dim ans As Byte
Dim sent As Byte
Serial2.Serial2Init(9600)
brg = SPBRG2
tx = TXSTA2
rc = RCSTA2
baud = BAUDCON2
tris = TRISD And 192
ans = ANSELD And 192
Serial2.Serial2WriteByte(65)
Serial2.Serial2Flush()
sent = 1
