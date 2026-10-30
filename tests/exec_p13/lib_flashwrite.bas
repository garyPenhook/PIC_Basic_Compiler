' expect: FW_SA=8160 FW_R1=1 FW_R2=1 FW_R3=1 FW_R6=1 FW_R7=1 FW_R8=1 FW_R9=1 FW_W31=100 FW_W0B=8192 FW_W0=8192 FW_W1=5678 FW_W2=16383 FW_ADL=225 FW_ADH=31 FW_CON=0 FW_GIE=1 FW_GIE2=0 FW_R4=0 FW_R5=0
' Program flash self-write on the PIC16F13145 (DS40002519D section 15.1, the same NVM as the PIC16F17146): a sector is the 32-word row, here the last one (words 8160..8191).
' The simulator models the flash: erase (row = 3FFFh), a word write through the write latches, and the row modify of FlashUpdateWord
' (row read into RAM, erase, 32 latch loads, write). After the last read NVMADR holds word 8161 = 1FE1h and NVMCON1 is 0; GIE is restored
' as found (set, then clear). Word 8191 is the last latch of the row: it is written (erased word), then changed to a smaller pattern, which needs the row
' erase, with words 0 and 1 of the row kept (FW_W0B). Sector 256 and word 8192 are outside the 8K-word flash and are refused.
Program Fw
Device = 16F13145
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
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
sa = Flashwrite.FlashSectorAddr(255)
r1 = Flashwrite.FlashEraseSector(255)
r2 = Flashwrite.FlashWriteWord(8160, 4660)
r3 = Flashwrite.FlashUpdateWord(8161, 5678)
r6 = Flashwrite.FlashUpdateWord(8160, 8192)
r7 = Flashwrite.FlashUpdateWord(8160, 8192)
r8 = Flashwrite.FlashUpdateWord(8191, 1234)
r9 = Flashwrite.FlashUpdateWord(8191, 100)
w31 = Flashwrite.FlashReadWord(8191)
w0b = Flashwrite.FlashReadWord(8160)
w0 = Flashwrite.FlashReadWord(8160)
w2 = Flashwrite.FlashReadWord(8162)
w1 = Flashwrite.FlashReadWord(8161)
adl = NVMADRL
adh = NVMADRH
con = NVMCON1
gie = INTCON >> 7
INTCON = 0
r2 = Flashwrite.FlashWriteWord(8163, 4660)
gie2 = INTCON >> 7
r4 = Flashwrite.FlashEraseSector(256)
r5 = Flashwrite.FlashWriteWord(8192, 1)
