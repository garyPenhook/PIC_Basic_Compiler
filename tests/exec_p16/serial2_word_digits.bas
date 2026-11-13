' expect: T_L1=53 T_L2=48 T_L3=57 T_L4=70 T_L5=53 T_L6=48
' Serial2WriteWord and Serial2WriteHex (the Const table of powers of ten, the final digit sent as it stands, the two-pass hex loop; same
' code as lib/serial.bas): the last byte the library leaves in TX2REG after 65535, 40000, 9, $AF, $05 and 0 is the last character printed.
Program T
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "serial2"
Dim L1, L2, L3, L4, L5, L6 As Byte
Serial2.Serial2Init(115200)
Serial2.Serial2WriteWord(65535)
L1 = TX2REG
Serial2.Serial2WriteWord(40000)
L2 = TX2REG
Serial2.Serial2WriteWord(9)
L3 = TX2REG
Serial2.Serial2WriteHex($AF)
L4 = TX2REG
Serial2.Serial2WriteHex($05)
L5 = TX2REG
Serial2.Serial2WriteWord(0)
L6 = TX2REG
