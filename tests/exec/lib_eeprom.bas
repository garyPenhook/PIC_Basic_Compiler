' expect: LE_W1=1 LE_ADL=255 LE_ADH=3 LE_ADU=49 LE_DAT=90 LE_EN=0 LE_GIE=1 LE_BAD=255 LE_WBAD=0 LE_GIE2=0 LE_WW=1 LE_ER=0
' The simulator does not model data EEPROM reads (the byte read back is whatever NVMDATL held), so the
' value stored is not checked: the test checks the NVM registers the routines leave behind.
Program Le
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
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
INTCON = 128
w1 = Eeprom.EepromWrite(1023, 90)
adl = NVMADRL
adh = NVMADRH
adu = NVMADRU
dat = NVMDATL
en = NVMCON0 And 128
er = NVMCON0 And 16
gie = INTCON >> 7
bad = Eeprom.EepromRead(1024)
wbad = Eeprom.EepromWrite(1024, 1)
INTCON = 0
ww = Eeprom.EepromWriteWord(20, 4660)
gie2 = INTCON >> 7
