' expect: LDM_R=1 LDM_D=1735880461161533969 LDM_DONE=1 LDM_CON0=128 LDM_R2=1 LDM_E=4625 LDM_DONE2=1 LDM_ZERO=0 LDM_R3=1 LDM_G=353637138 LDM_STP=0
' dma:
' DmaCopy on the PIC18F16Q41 with the DMA model of scripts/dma_sim.py (MDB has no DMA): the bytes really move.
' An 8-byte copy on channel 2 ends with DGO clear (DmaDone = 1) and EN still set (DMAnCON0 = 80h). A 2-byte copy on
' the same channel, now free, lands in e; the bytes after it in e stay 0. A copy on channel 4 runs next to it
' (the model keeps one register set per channel, as the overlay does). Not run on a real part.
Program Ldm
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "dma"
Dim s(8) As Byte
Dim d(8) As Byte
Dim e(4) As Byte
Dim g(4) As Byte
Dim t(4) As Byte
Dim r As Byte
Dim done As Byte
Dim con0 As Byte
Dim r2 As Byte
Dim done2 As Byte
Dim zero As Byte
Dim r3 As Byte
Dim stp As Byte
s(0) = 17
s(1) = 18
s(2) = 19
s(3) = 20
s(4) = 21
s(5) = 22
s(6) = 23
s(7) = 24
r = Dma.DmaCopy(2, @s, @d, 8)
done = Dma.DmaDone(2)
con0 = DMAnCON0
r2 = Dma.DmaCopy(2, @s, @e, 2)
done2 = Dma.DmaDone(2)
zero = e(2)
t(0) = 18
t(1) = 19
t(2) = 20
t(3) = 21
r3 = Dma.DmaCopy(4, @t, @g, 4)
Dma.DmaStop(2)
Dma.DmaStop(4)
stp = DMAnCON0
