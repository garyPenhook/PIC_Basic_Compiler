' expect: LDT_A_R=1 LDT_A_CON0=192 LDT_A_CON1=2 LDT_A_SSZ=8 LDT_A_DSZ=1 LDT_A_SIRQ=33 LDT_A_DONE=0 LDT_A_AGAIN=0 LDT_BAD0=0 LDT_BAD1=0 LDT_BAD2=0 LDT_BAD3=0 LDT_STP=0 LDT_DONE2=1 LDT_B_R=1 LDT_B_CON1=96 LDT_B_SSZ=1 LDT_B_DSZ=8 LDT_B_SIRQ=32 LDT_C_R=1 LDT_C_CON1=3 LDT_C_SSZ=8 LDT_C_DSZ=1
' DmaOnTrigger on the PIC18F16Q41. The simulator does not model the DMA engine, so the test checks the registers left
' behind: A a buffer-to-register feed (fixed destination), B a register-to-buffer receive with DmaOnce (fixed source,
' DSTP), C a feed with DmaOnce (SSTP). EN and SIRQEN set (C0h), the fixed side has size 1, DMAnSIRQ holds the trigger.
' DmaDone reports 0 while armed and 1 after DmaStop. Bad channel, trigger and count are refused.
' Data movement: not run on a real part.
Program Ldt
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "dma"
Dim buf(8) As Byte
Dim a_r As Byte
Dim a_con0 As Byte
Dim a_con1 As Byte
Dim a_ssz As Byte
Dim a_dsz As Byte
Dim a_sirq As Byte
Dim a_done As Byte
Dim a_again As Byte
Dim bad0 As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim stp As Byte
Dim done2 As Byte
Dim b_r As Byte
Dim b_con1 As Byte
Dim b_ssz As Byte
Dim b_dsz As Byte
Dim b_sirq As Byte
Dim c_r As Byte
Dim c_con1 As Byte
Dim c_ssz As Byte
Dim c_dsz As Byte
a_r = Dma.DmaOnTrigger(1, Dma.DmaTrigU1Tx, @buf, @U1TXB, 8, Dma.DmaFixedDst)
a_con0 = DMAnCON0
a_con1 = DMAnCON1
a_ssz = DMAnSSZL
a_dsz = DMAnDSZL
a_sirq = DMAnSIRQ
a_done = Dma.DmaDone(1)
a_again = Dma.DmaOnTrigger(1, Dma.DmaTrigU1Tx, @buf, @U1TXB, 8, Dma.DmaFixedDst)
bad0 = Dma.DmaOnTrigger(0, 33, @buf, @U1TXB, 8, 2)
bad1 = Dma.DmaOnTrigger(2, 0, @buf, @U1TXB, 8, 2)
bad2 = Dma.DmaOnTrigger(2, 94, @buf, @U1TXB, 8, 2)
bad3 = Dma.DmaOnTrigger(2, 33, @buf, @U1TXB, 0, 2)
Dma.DmaStop(1)
stp = DMAnCON0
done2 = Dma.DmaDone(1)
b_r = Dma.DmaOnTrigger(1, Dma.DmaTrigU1Rx, @U1RXB, @buf, 8, Dma.DmaFixedSrc + Dma.DmaOnce)
b_con1 = DMAnCON1
b_ssz = DMAnSSZL
b_dsz = DMAnDSZL
b_sirq = DMAnSIRQ
Dma.DmaStop(1)
c_r = Dma.DmaOnTrigger(1, Dma.DmaTrigU1Tx, @buf, @U1TXB, 8, Dma.DmaFixedDst + Dma.DmaOnce)
c_con1 = DMAnCON1
c_ssz = DMAnSSZL
c_dsz = DMAnDSZL
