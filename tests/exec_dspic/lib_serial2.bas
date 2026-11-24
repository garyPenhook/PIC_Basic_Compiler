' expect: T_BRG=103 T_MODE=32944 T_MODEH=128 T_R2=768 T_R19=65316 T_DONE=1
' Library serial2 on the dsPIC33CK: UART2 set-up (BRG for 9600 baud at Fp = 4 MHz, 8N1, BRGH = 1, RUNOVF) and PPS routing (TX RP37 = U2TX code 3, RX RP36); RPINR19 keeps U2DSRR = FFh.
Program T
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "serial2"
Dim BRG As Word
Dim MODE As Word
Dim MODEH As Word
Dim R2 As Word
Dim R19 As Word
Dim DONE As Byte
Serial2.Serial2Init(9600)
BRG = U2BRG
MODE = U2MODE
MODEH = U2MODEH
R2 = RPOR2
R19 = RPINR19
Serial2.Serial2WriteByte(85)
Serial2.Serial2Flush()
DONE = 1
