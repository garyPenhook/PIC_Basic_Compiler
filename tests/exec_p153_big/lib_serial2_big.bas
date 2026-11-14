' expect: SS_TXP=17 SS_RXP=15 SS_TRIS=128 SS_BRG=68 SS_TX=38 SS_RC=144
' Serial2 on the PIC16(L)F15386: TX2/CK2 and RX2/DT2 reach ports B and D on this part (DS40001866E Tables 15-3 p.238 and 15-7 p.243), so EUSART2 is on RB6 (RB6PPS = 11h, the reset selection of TX2CKPPS) and RB7 (RX2DTPPS = PORT[5:3] | PIN[2:0] =
' 001 111 = 15, the reset selection too), not on RC2 and RC1 as on the 14- and 20-pin parts. TRISB bit 7 (RX) is set and bit 6 (TX) clear: 128 of the 192 bits. 115200 baud at 32 MHz: n = 68.
Program Ss
Device = 16F15386
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "serial2"
Dim txp As Byte
Dim rxp As Byte
Dim tris As Byte
Dim brg As Byte
Dim tx As Byte
Dim rc As Byte
TRISB = 255
Serial2.Serial2Init(115200)
txp = RB6PPS
rxp = RX2DTPPS
tris = TRISB And 192
brg = SP2BRGL
tx = TX2STA
rc = RC2STA
