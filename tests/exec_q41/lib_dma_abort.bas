' expect: LDA_A_R=1 LDA_A_AIRQ=32 LDA_A_CON0=196 LDA_BAD0=0 LDA_BAD1=0 LDA_BAD2=0 LDA_OFF=0 LDA_AB0=0 LDA_AB1=1 LDA_AB2=0
' DmaAbortOn / DmaAborted on the PIC18F16Q41 (the simulator does not model the engine): after DmaOnTrigger, DmaAbortOn
' leaves DMAnAIRQ = the trigger and AIRQEN set (EN + SIRQEN + AIRQEN = C4h). Bad channel, bad trigger and a
' stopped channel are refused. DmaAborted reads and clears DMA1AIF. Not run on a real part.
Program Lda
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "dma"
Dim buf(8) As Byte
Dim a_r As Byte
Dim a_airq As Byte
Dim a_con0 As Byte
Dim bad0 As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim off As Byte
Dim ab0 As Byte
Dim ab1 As Byte
Dim ab2 As Byte
a_r = Dma.DmaOnTrigger(1, Dma.DmaTrigU1Tx, @buf, @U1TXB, 8, Dma.DmaFixedDst)
a_r = Dma.DmaAbortOn(1, 32)
a_airq = DMAnAIRQ
a_con0 = DMAnCON0
bad0 = Dma.DmaAbortOn(0, 32)
bad1 = Dma.DmaAbortOn(1, 0)
bad2 = Dma.DmaAbortOn(1, 94)
Dma.DmaStop(1)
off = Dma.DmaAbortOn(1, 32)
ab0 = Dma.DmaAborted(1)
PIR2 = PIR2 Or 128
ab1 = Dma.DmaAborted(1)
ab2 = Dma.DmaAborted(1)
