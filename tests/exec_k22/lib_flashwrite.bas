' expect: KF_LAST=511 KF_SA=16352 KF_E=1 KF_B=65535 KF_W=1 KF_R=4660 KF_N=1 KF_U=1 KF_R2=22136 KF_K=4660 KF_K2=65535 KF_GIE=1 KF_CON=0
' Program flash self-write on the PIC18(L)F2x/4xK22 (DS40001412H chapter 6): a sector is the 64-byte (32-word) erase and write block, so
' the PIC18F25K22's 32 KB give sectors 0..511 and the last starts at word 16352. Erase gives FFFFh; FlashWriteWord programs an erased
' word (the other holding registers stay FFh, which leaves their bytes); FlashUpdateWord of a programmed word reads the block into RAM,
' erases it and writes all 64 bytes back, so the next word (written with 4660 first) keeps its value and the one after stays erased.
Program Kf
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "flashwrite"
Dim last As Word
Dim sa As Word
Dim e As Byte
Dim b As Word
Dim w As Byte
Dim r As Word
Dim n As Byte
Dim u As Byte
Dim r2 As Word
Dim k As Word
Dim k2 As Word
Dim gie As Byte
Dim con As Byte
last = Flashwrite.FlashLastSector
sa = Flashwrite.FlashSectorAddr(last)
INTCON.7 = 1
e = Flashwrite.FlashEraseSector(last)
b = Flashwrite.FlashReadWord(sa + 7)
w = Flashwrite.FlashWriteWord(sa, 4660)
r = Flashwrite.FlashReadWord(sa)
n = Flashwrite.FlashWriteWord(sa + 1, 4660)
u = Flashwrite.FlashUpdateWord(sa, 22136)
r2 = Flashwrite.FlashReadWord(sa)
k = Flashwrite.FlashReadWord(sa + 1)
k2 = Flashwrite.FlashReadWord(sa + 2)
gie = INTCON.7
con = EECON1
INTCON.7 = 0
