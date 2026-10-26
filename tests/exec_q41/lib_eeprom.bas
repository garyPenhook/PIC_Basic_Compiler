' expect: LE_W1=1 LE_ADL=255 LE_ADH=1 LE_ADU=56 LE_DAT=90 LE_CMD=0 LE_GIE=1 LE_BAD=255 LE_WBAD=0 LE_GIE2=0 LE_WW=1 LE_SIZE=512
' Data EEPROM library on the PIC18F16Q41: 512 bytes at NVM address 380000h (NVMADRU = 38h). The simulator
' does not model data EEPROM reads (the byte read back is whatever NVMDATL held), so the value stored is not
' checked: the test checks the NVM registers the routines leave behind (NVMCMD back at 000, address of the
' last byte 511 = 01FFh) and that interrupts are put back as they were found.
Program Le
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "eeprom"
Dim w1 As Byte
Dim adl As Byte
Dim adh As Byte
Dim adu As Byte
Dim dat As Byte
Dim cmd As Byte
Dim gie As Byte
Dim gie2 As Byte
Dim bad As Byte
Dim wbad As Byte
Dim ww As Byte
Dim size As Word
INTCON0 = 128
w1 = Eeprom.EepromWrite(511, 90)
adl = NVMADRL
adh = NVMADRH
adu = NVMADRU
dat = NVMDATL
cmd = NVMCON1 And 7
gie = INTCON0 >> 7
bad = Eeprom.EepromRead(512)
wbad = Eeprom.EepromWrite(512, 1)
INTCON0 = 0
ww = Eeprom.EepromWriteWord(20, 4660)
gie2 = INTCON0 >> 7
size = Eeprom.EepromSize
