' expect: LDB_R=1 LDB_D=21542142465 LDB_MID=0 LDB_AB=1 LDB_DONE=1 LDB_CON0=128
' dma: mailbox=LDB_TRG slow
' A DmaCopy of 8 bytes in slow mode (a started message waits for step commands) with the DMA model of
' scripts/dma_sim.py. Mailbox 0x83 = run 3 transactions of channel 1: three bytes have moved and DmaDone = 0. DmaAbortOn
' then abort request 0x42 = abort channel 1 after 2 more transactions: five bytes in all, DGO and SIRQEN clear,
' DmaAborted = 1, DmaDone = 1, EN still set. Not run on a real part.
Program Ldb
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "dma"
Dim s(8) As Byte
Dim d(8) As Byte
Dim trg As Byte
Dim r As Byte
Dim mid As Byte
Dim ab As Byte
Dim done As Byte
Dim con0 As Byte
Dim x As Byte
s(0) = 1
s(1) = 2
s(2) = 3
s(3) = 4
s(4) = 5
s(5) = 6
s(6) = 7
s(7) = 8
r = Dma.DmaCopy(1, @s, @d, 8)
trg = 131
mid = Dma.DmaDone(1)
x = Dma.DmaAbortOn(1, 5)
trg = 66
ab = Dma.DmaAborted(1)
done = Dma.DmaDone(1)
con0 = DMAnCON0
