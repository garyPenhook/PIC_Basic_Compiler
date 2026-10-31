' expect: FW_SA=16352 FW_R1=1 FW_R2=1 FW_R3=1 FW_R6=1 FW_R7=1 FW_R8=1 FW_R9=1 FW_W31=100 FW_W0B=8192 FW_W0=8192 FW_W1=5678 FW_W2=16383 FW_ADL=225 FW_ADH=191 FW_CON=0 FW_GIE=1 FW_GIE2=0 FW_R4=0 FW_R5=0
' Program flash self-write on the PIC16F183xx (PIC16F18326, DS40001839E section 11.4; NVMADRH bit 7 is unimplemented and reads 1, so the high address 3Fh reads back as 191): a sector is the 32-word row, here the last one (words 16352..16383).
' The simulator models the flash: erase (row = 3FFFh), a word write through the write latches, and the row modify of FlashUpdateWord
' (row read into RAM, erase, 32 latch loads, write). After the last read NVMADR holds word 16353 = 3FE1h and NVMCON1 is 0; GIE is restored
' as found (set, then clear). Word 16383 is the last latch of the row: it is written (erased word), then changed to a smaller pattern, which needs the row
' erase, with words 0 and 1 of the row kept (FW_W0B). Sector 512 and word 16384 are outside the 16K-word flash and are refused.
Program Fw
Device = 16F18326
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "flashwrite"
Dim sa As Word
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Byte
Dim r7 As Byte
Dim r8 As Byte
Dim r9 As Byte
Dim w31 As Word
Dim w0b As Word
Dim w0 As Word
Dim w1 As Word
Dim w2 As Word
Dim adl As Byte
Dim adh As Byte
Dim con As Byte
Dim gie As Byte
Dim gie2 As Byte
Dim er As Byte
INTCON = 128
sa = Flashwrite.FlashSectorAddr(511)
r1 = Flashwrite.FlashEraseSector(511)
r2 = Flashwrite.FlashWriteWord(16352, 4660)
r3 = Flashwrite.FlashUpdateWord(16353, 5678)
r6 = Flashwrite.FlashUpdateWord(16352, 8192)
r7 = Flashwrite.FlashUpdateWord(16352, 8192)
r8 = Flashwrite.FlashUpdateWord(16383, 1234)
r9 = Flashwrite.FlashUpdateWord(16383, 100)
w31 = Flashwrite.FlashReadWord(16383)
w0b = Flashwrite.FlashReadWord(16352)
w0 = Flashwrite.FlashReadWord(16352)
w2 = Flashwrite.FlashReadWord(16354)
w1 = Flashwrite.FlashReadWord(16353)
adl = NVMADRL
adh = NVMADRH
con = NVMCON1
gie = INTCON >> 7
INTCON = 0
r2 = Flashwrite.FlashWriteWord(16355, 4660)
gie2 = INTCON >> 7
r4 = Flashwrite.FlashEraseSector(512)
r5 = Flashwrite.FlashWriteWord(16384, 1)
