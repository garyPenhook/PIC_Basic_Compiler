' expect: KE_W1=1 KE_R1=90 KE_W2=1 KE_R2=17 KE_WW=1 KE_RW=4660 KE_BAD=255 KE_WBAD=0 KE_SAME=1 KE_GIE=1 KE_CON=0 KE_SIZE=256
' Data EEPROM on the PIC18(L)F2x/4xK22 (DS40001412H chapter 7): EepromWrite unlocks (55h, AAh to EECON2, WR) with interrupts off,
' waits for WR to clear, and checks by reading back; EECON1 is left 0 (WREN off). 256 bytes on the PIC18F25K22 (Table 1 p.2):
' address 300 is refused. GIE is restored as found (set here).
Program Ke
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "eeprom"
Dim w1 As Byte
Dim r1 As Byte
Dim w2 As Byte
Dim r2 As Byte
Dim ww As Byte
Dim rw As Word
Dim bad As Byte
Dim wbad As Byte
Dim same As Byte
Dim gie As Byte
Dim con As Byte
Dim size As Word
INTCON.7 = 1
w1 = Eeprom.EepromWrite(5, 90)
r1 = Eeprom.EepromRead(5)
w2 = Eeprom.EepromWrite(255, 17)
r2 = Eeprom.EepromRead(255)
ww = Eeprom.EepromWriteWord(10, 4660)
rw = Eeprom.EepromReadWord(10)
bad = Eeprom.EepromRead(300)
wbad = Eeprom.EepromWrite(300, 1)
' Writing the value the byte already holds is skipped and still reports success.
same = Eeprom.EepromWrite(5, 90)
gie = INTCON.7
con = EECON1
size = Eeprom.EepromSize
INTCON.7 = 0
