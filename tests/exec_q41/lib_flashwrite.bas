' expect: FW_SA=32640 FW_R1=1 FW_R2=1 FW_R3=1 FW_R5=1 FW_RD=22136 FW_RD2=26214 FW_R6=0 FW_ADL=2 FW_ADH=255 FW_ADU=0 FW_CMD=0 FW_GIE=1 FW_TL=2 FW_TA=86 FW_GIE2=0 FW_R4=0 FW_LAST=255
' Flashwrite on the PIC18F16Q41 (32 K words, sectors 0..255). The simulator models the program flash, so values
' are checked: after the sector erase, word 32640 takes 4660 (R2) and word 32641 takes 26214 (R3: an erased word
' goes through the quick word write); then FlashUpdateWord(32640, 22136) must go the page way (the word is
' programmed): page read, page erase, the two TBLWT*+ (TBLPTRL = 0 + 2, TABLAT = 56h) and page write (R5), and the
' neighbouring word 32641 must survive it (RD2). Writing 4660 over the programmed word again must fail (R6 = 0). NVMCMD is back at 000, GIE is restored as found (set, then clear).
Program Fw
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "flashwrite"
Dim sa As Word
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Byte
Dim rd As Word
Dim rd2 As Word
Dim adl As Byte
Dim adh As Byte
Dim adu As Byte
Dim cmd As Byte
Dim gie As Byte
Dim gie2 As Byte
Dim tl As Byte
Dim ta As Byte
Dim last As Word
INTCON0 = 128
sa = Flashwrite.FlashSectorAddr(255)
r1 = Flashwrite.FlashEraseSector(255)
r2 = Flashwrite.FlashWriteWord(32640, 4660)
r3 = Flashwrite.FlashUpdateWord(32641, 26214)
r5 = Flashwrite.FlashUpdateWord(32640, 22136)
rd = Flashwrite.FlashReadWord(32640)
rd2 = Flashwrite.FlashReadWord(32641)
adl = NVMADRL
adh = NVMADRH
adu = NVMADRU
cmd = NVMCON1 And 7
gie = INTCON0 >> 7
tl = TBLPTRL
ta = TABLAT
INTCON0 = 0
r6 = Flashwrite.FlashWriteWord(32640, 4660)
gie2 = INTCON0 >> 7
r4 = Flashwrite.FlashEraseSector(256)
last = Flashwrite.FlashLastSector
