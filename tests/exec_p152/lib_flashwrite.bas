' expect: FW_SA=4064 FW_R1=1 FW_R2=1 FW_R3=1 FW_R6=1 FW_R7=1 FW_R8=1 FW_R9=1 FW_W31=100 FW_W0B=8192 FW_W0=8192 FW_W1=5678 FW_W2=16383 FW_ADL=225 FW_ADH=15 FW_CON=0 FW_GIE=1 FW_GIE2=0 FW_R4=0 FW_R5=0
' Program flash self-write on the PIC16F152xx (PIC16F15244, DS40002195E section 15.1; 4096 words, last address 0FFFh): a sector is the 32-word row, here the last one (words 4064..4095, sector 127).
' The simulator models the flash: erase (row = 3FFFh), a word write through the write latches, and the row modify of FlashUpdateWord
' (row read into RAM, erase, 32 latch loads, write). After the last read (bit 15 of NVMADR is undefined after a write, Register 15.2.1, so it is masked) NVMADR holds word 4065 = 0FE1h and NVMCON1 is 0; GIE is restored
' as found (set, then clear). Word 4095 is the last latch of the row: it is written (erased word), then changed to a smaller pattern, which needs the row
' erase, with words 0 and 1 of the row kept (FW_W0B). Sector 128 and word 4096 are outside the 4K-word flash and are refused.
Program Fw
Device = 16F15244
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHZ, WDTE = OFF, LVP = ON
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
sa = Flashwrite.FlashSectorAddr(127)
r1 = Flashwrite.FlashEraseSector(127)
r2 = Flashwrite.FlashWriteWord(4064, 4660)
r3 = Flashwrite.FlashUpdateWord(4065, 5678)
r6 = Flashwrite.FlashUpdateWord(4064, 8192)
r7 = Flashwrite.FlashUpdateWord(4064, 8192)
r8 = Flashwrite.FlashUpdateWord(4095, 1234)
r9 = Flashwrite.FlashUpdateWord(4095, 100)
w31 = Flashwrite.FlashReadWord(4095)
w0b = Flashwrite.FlashReadWord(4064)
w0 = Flashwrite.FlashReadWord(4064)
w2 = Flashwrite.FlashReadWord(4066)
w1 = Flashwrite.FlashReadWord(4065)
adl = NVMADRL
adh = NVMADRH And 127
con = NVMCON1
gie = INTCON >> 7
INTCON = 0
r2 = Flashwrite.FlashWriteWord(4067, 4660)
gie2 = INTCON >> 7
r4 = Flashwrite.FlashEraseSector(128)
r5 = Flashwrite.FlashWriteWord(4096, 1)
