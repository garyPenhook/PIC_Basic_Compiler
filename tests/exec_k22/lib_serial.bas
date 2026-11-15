' expect: LS_BRGL=138 LS_BRGH=0 LS_TX=38 LS_RC=144 LS_BAUD=72 LS_TRIS=192 LS_ANS=0 LS_SENT=1
' Serial library on the PIC18(L)F2x/4xK22 (DS40001412H chapter 16): SerialInit programs EUSART1 on its fixed pins RC6/RC7, both TRIS bits
' set (SPEN takes TX, 16.1.1.7 p.262) and ANSELC bits 6 and 7 cleared. 115200 baud at 64 MHz with BRG16 = BRGH = 1: n = 138 in
' SPBRGH1:SPBRG1. TXSTA1 = TXEN | BRGH reads back with TRMT (bit 1) set, BAUDCON1 = BRG16 with RCIDL (bit 6) set (Registers 16-1 to 16-3).
Program Ls
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "serial"
Dim brgl As Byte
Dim brgh As Byte
Dim tx As Byte
Dim rc As Byte
Dim baud As Byte
Dim tris As Byte
Dim ans As Byte
Dim sent As Byte
Serial.SerialInit(115200)
brgl = SPBRG1
brgh = SPBRGH1
tx = TXSTA1
rc = RCSTA1
baud = BAUDCON1
tris = TRISC And 192
ans = ANSELC And 192
Serial.SerialWrite("ok")
Serial.SerialWriteWord(1234)
Serial.SerialFlush()
sent = 1
