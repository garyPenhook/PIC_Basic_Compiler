' expect: T_BRG=103 T_MODE=32944 T_MODEH=128 T_R3=1 T_R18=65319 T_DONE=1
' Library serial on the dsPIC33CK: UART1 set-up (BRG for 9600 baud at Fp = 4 MHz, 8N1, BRGH = 1, RUNOVF) and PPS routing (TX RP38, RX RP39); RPINR18 keeps U1DSRR = FFh.
Program T
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "serial"
Dim BRG As Word
Dim MODE As Word
Dim MODEH As Word
Dim R3 As Word
Dim R18 As Word
Dim DONE As Byte
Serial.SerialInit(9600)
BRG = U1BRG
MODE = U1MODE
MODEH = U1MODEH
R3 = RPOR3
R18 = RPINR18
Serial.SerialWriteByte(85)
Serial.SerialFlush()
DONE = 1
