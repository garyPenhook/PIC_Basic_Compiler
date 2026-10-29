' Data EEPROM on the PIC16F17146 (DS40002343F section 15.2): NVMREGS = 1, NVMADRH = 70h, NVMADRL = the byte address (256 bytes). The simulator models the data EEPROM, so the stored bytes are read back (rb = byte 255, rc = high byte of the word at 20, w2 = the word); adu holds NVMCON1.NVMREGS, clear again after each operation.
' expect: LE_W1=1 LE_ADL=255 LE_ADH=112 LE_ADU=0 LE_DAT=90 LE_EN=0 LE_GIE=1 LE_BAD=255 LE_WBAD=0 LE_GIE2=0 LE_WW=1 LE_ER=0 LE_RB=90 LE_RC=18 LE_W2=4660
Program Le
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "eeprom"
Dim w1 As Byte
Dim adl As Byte
Dim adh As Byte
Dim adu As Byte
Dim dat As Byte
Dim en As Byte
Dim gie As Byte
Dim gie2 As Byte
Dim bad As Byte
Dim wbad As Byte
Dim ww As Byte
Dim er As Byte
Dim rb As Byte
Dim rc As Byte
Dim w2 As Word
INTCON = 128
w1 = Eeprom.EepromWrite(255, 90)
adl = NVMADRL
adh = NVMADRH
adu = NVMCON1 And 64
dat = NVMDATL
en = NVMCON1 And 4
er = NVMCON1 And 8
gie = INTCON >> 7
bad = Eeprom.EepromRead(256)
wbad = Eeprom.EepromWrite(256, 1)
INTCON = 0
ww = Eeprom.EepromWriteWord(20, 4660)
gie2 = INTCON >> 7
rb = Eeprom.EepromRead(255)
rc = Eeprom.EepromRead(21)
w2 = Eeprom.EepromReadWord(20)
