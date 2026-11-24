' expect: F_R0=65535 F_ERA=1 F_W1=1 F_V1=4660 F_W2=0 F_P=1 F_V2=22136 F_V3=39612 F_U=1 F_V4=2748 F_V5=4660 F_V6=39612 F_TB=0 F_DONE=1
' Library flashwrite on the dsPIC33CK: erase of the last sector (word 20480..), single-word write into an erased pair (partner left FFFFh and refused a second write: W2 = 0), pair write, and FlashUpdateWord on a used pair (page image, erase, reprogram: the neighbour words keep their values); TBLPAG is back to 0.
Program F
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "flashwrite"
Dim R0 As Word
Dim ERA As Byte
Dim W1 As Byte
Dim V1 As Word
Dim W2 As Byte
Dim P As Byte
Dim V2 As Word
Dim V3 As Word
Dim U As Byte
Dim V4 As Word
Dim V5 As Word
Dim V6 As Word
Dim TB As Word
Dim DONE As Byte
Dim S As Word
S = Flashwrite.FlashSectorAddr(Flashwrite.FlashLastSector)
ERA = Flashwrite.FlashEraseSector(Flashwrite.FlashLastSector)
R0 = Flashwrite.FlashReadWord(S)
W1 = Flashwrite.FlashWriteWord(S, $1234)
V1 = Flashwrite.FlashReadWord(S)
W2 = Flashwrite.FlashWriteWord(S + 1, $5678)
P = Flashwrite.FlashWritePair(S + 2, $5678, $9ABC)
V2 = Flashwrite.FlashReadWord(S + 2)
V3 = Flashwrite.FlashReadWord(S + 3)
U = Flashwrite.FlashUpdateWord(S + 1, $0ABC)
V4 = Flashwrite.FlashReadWord(S + 1)
V5 = Flashwrite.FlashReadWord(S)
V6 = Flashwrite.FlashReadWord(S + 3)
TB = TBLPAG
DONE = 1
