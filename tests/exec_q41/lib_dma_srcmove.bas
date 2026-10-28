' expect: LDS_F_R=1 LDS_F=21542142465 LDS_E_R=1 LDS_E=67305985
' dma: ee=16:1,2,3,4
' DmaCopyFlash and DmaCopyEeprom with the DMA model of scripts/dma_sim.py (MDB has no DMA). The flash source is a Const
' table (5 bytes, read from the hex file), the EEPROM source offset 16 where the test put 1, 2, 3, 4 before the run.
' The EEPROM address form (a byte offset) is the model's reading of TB3164 section 7.1, not checked on a part.
Program Lds
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "dma"
Const tbl(5) As Byte = (1, 2, 3, 4, 5)
Dim f(5) As Byte
Dim e(4) As Byte
Dim f_r As Byte
Dim e_r As Byte
f_r = Dma.DmaCopyFlash(1, @tbl, @f, 5)
e_r = Dma.DmaCopyEeprom(2, 16, @e, 4)
