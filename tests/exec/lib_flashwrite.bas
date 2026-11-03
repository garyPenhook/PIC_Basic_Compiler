' expect: FW_SA=65408 FW_R1=1 FW_R2=1 FW_R3=1 FW_R5=1 FW_R6=4660 FW_ADL=2 FW_ADH=255 FW_ADU=1 FW_EN=0 FW_GIE=1 FW_TL=4 FW_TA=18 FW_GIE2=0 FW_ER=0 FW_R4=0
' The simulator models program-flash reads, word writes, sector read/erase/write and TBLWT into the holding
' registers (picsim periph/nvm.rs). R3 is the quick word write into an erased word. R5 updates that now-programmed
' word to a value that needs an erase, so FlashUpdateWord takes its sector path (sector read, sector erase, two
' TBLWT*+, sector write) and R6 reads the result back. The test also checks the registers the routines leave behind:
' NVMADR (word 65409 = byte 1FF02h), NVMEN off, GIE restored as found (set, then clear), NVMERR clear, and
' TBLPTRL = 2 + 2 / TABLAT = 12h, which only that sector path leaves. Errata 1.9.1 (the two NOPs after each
' self-write instruction) is checked in the generated assembly, not by this run.
Program Fw
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "flashwrite"
Dim sa As Word
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Word
Dim adl As Byte
Dim adh As Byte
Dim adu As Byte
Dim en As Byte
Dim gie As Byte
Dim gie2 As Byte
Dim tl As Byte
Dim ta As Byte
Dim er As Byte
INTCON = 128
sa = Flashwrite.FlashSectorAddr(511)
r1 = Flashwrite.FlashEraseSector(511)
r2 = Flashwrite.FlashWriteWord(65408, 4660)
r3 = Flashwrite.FlashUpdateWord(65409, 22136)
r5 = Flashwrite.FlashUpdateWord(65409, 4660)
r6 = Flashwrite.FlashReadWord(65409)
adl = NVMADRL
adh = NVMADRH
adu = NVMADRU
en = NVMCON0 And 128
er = NVMCON0 And 16
gie = INTCON >> 7
tl = TBLPTRL
ta = TABLAT
INTCON = 0
r2 = Flashwrite.FlashWriteWord(65408, 4660)
gie2 = INTCON >> 7
r4 = Flashwrite.FlashEraseSector(512)
