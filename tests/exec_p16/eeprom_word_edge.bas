' Word routines of the data EEPROM at the end of the address range (PIC16F17146: 256 bytes). addr + 1 wraps at 65535 and
' must not reach byte 0: a word write there stores nothing and reports 0, a word read there gives 65535. At the last byte
' (255) the first byte is stored, the second does not exist: the write returns 0 and a read gives 255 in the high byte.
' expect: EW_B0=90 EW_W1=0 EW_R1=65535 EW_W2=0 EW_B255=52 EW_R2=65332 EW_W3=1 EW_R3=4660
Program Ew
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "eeprom"
Dim b0 As Byte
Dim w1 As Byte
Dim r1 As Word
Dim w2 As Byte
Dim b255 As Byte
Dim r2 As Word
Dim w3 As Byte
Dim r3 As Word
Dim junk As Byte
junk = Eeprom.EepromWrite(0, 90)
w1 = Eeprom.EepromWriteWord(65535, 4660)
b0 = Eeprom.EepromRead(0)
r1 = Eeprom.EepromReadWord(65535)
w2 = Eeprom.EepromWriteWord(255, 4660)
b255 = Eeprom.EepromRead(255)
r2 = Eeprom.EepromReadWord(255)
w3 = Eeprom.EepromWriteWord(20, 4660)
r3 = Eeprom.EepromReadWord(20)
