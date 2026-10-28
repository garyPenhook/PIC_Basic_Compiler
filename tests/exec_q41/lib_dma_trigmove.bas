' expect: LDG_A_R=1 LDG_A_MID=0 LDG_A_DONE=1 LDG_A_CON0=128 LDG_B_R=1 LDG_RX=101124105 LDG_B_DONE=1 LDG_C_R=1 LDG_C_AB=0 LDG_C_DONE=0 LDG_D_R=1 LDG_D_DONE=1 LDG_D_AB=1
' dma: mailbox=LDG_TRG sfr=U1RXB:9,8,7,6
' dma-writes: U1TXB=1,2,3,4,5,6,7,8
' DmaOnTrigger with the DMA model of scripts/dma_sim.py (MDB has no DMA), requests raised through the mailbox byte
' (bits 7:6 command, 5:4 channel - 1, 3:0 count). A: channel 1 feeds buf to the transmit register with DmaOnce; five
' requests leave it armed (DmaDone = 0), three more send the other bytes, SIRQEN clears and DmaDone = 1. B: channel 2
' reads the receive register (which returns 9, 8, 7, 6) into rx. C: with no request nothing moves and the channel
' stays armed. D: DmaAbortOn on channel 3 and an abort request set DMA3AIF: DmaAborted = 1, DmaDone = 1.
' The writes to U1TXB are what the DMA wrote there, in order. Not run on a real part.
Program Ldg
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "dma"
Dim buf(8) As Byte
Dim rx(4) As Byte
Dim trg As Byte
Dim a_r As Byte
Dim a_mid As Byte
Dim a_done As Byte
Dim a_con0 As Byte
Dim b_r As Byte
Dim b_done As Byte
Dim c_r As Byte
Dim c_ab As Byte
Dim c_done As Byte
Dim d_r As Byte
Dim d_ab As Byte
Dim d_done As Byte
Dim x As Byte
buf(0) = 1
buf(1) = 2
buf(2) = 3
buf(3) = 4
buf(4) = 5
buf(5) = 6
buf(6) = 7
buf(7) = 8
a_r = Dma.DmaOnTrigger(1, Dma.DmaTrigU1Tx, @buf, @U1TXB, 8, Dma.DmaFixedDst + Dma.DmaOnce)
trg = 5
a_mid = Dma.DmaDone(1)
trg = 3
a_done = Dma.DmaDone(1)
a_con0 = DMAnCON0
Dma.DmaStop(1)
b_r = Dma.DmaOnTrigger(2, Dma.DmaTrigU1Rx, @U1RXB, @rx, 4, Dma.DmaFixedSrc + Dma.DmaOnce)
trg = 20
b_done = Dma.DmaDone(2)
c_r = Dma.DmaOnTrigger(4, Dma.DmaTrigU1Tx, @buf, @U1TXB, 8, Dma.DmaFixedDst)
c_ab = Dma.DmaAborted(4)
c_done = Dma.DmaDone(4)
Dma.DmaStop(4)
d_r = Dma.DmaOnTrigger(3, Dma.DmaTrigU1Tx, @buf, @U1TXB, 8, Dma.DmaFixedDst)
x = Dma.DmaAbortOn(3, 5)
trg = 96
d_ab = Dma.DmaAborted(3)
d_done = Dma.DmaDone(3)
