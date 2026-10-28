' expect: LD_R1=1 LD_CON0=160 LD_CON1=66 LD_SSA_OK=1 LD_DSA_OK=1 LD_SSZL=8 LD_DSZL=8 LD_SSZH=0 LD_DONE=0 LD_AGAIN=0 LD_BAD0=0 LD_BAD1=0 LD_BAD2=0 LD_BAD3=0 LD_BAD4=1 LD_LOCK=1 LD_SEL=1 LD_STP=0
' DMA library on the PIC18F16Q41. The simulator does not model the DMA engine (DGO stays set and no byte moves),
' so the test checks what DmaCopy leaves in channel 2's registers: addresses, sizes of 8, DMAnCON1 = 42h
' (both pointers increment, SFR/GPR source), EN and DGO set (A0h), PRLOCKED set. A second copy on the busy channel
' is refused, and a channel outside 1..4, a count of 0 and a count above 4095 are refused.
' The simulator does not overlay the registers by DMASELECT, so a second channel cannot be checked.
' Data movement is not checked: not yet run on a real part.
Program Ld
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "dma"
Dim s(8) As Byte
Dim d(8) As Byte
Dim r1 As Byte
Dim con0 As Byte
Dim con1 As Byte
Dim ssa_ok As Byte
Dim dsa_ok As Byte
Dim sszl As Byte
Dim sszh As Byte
Dim dszl As Byte
Dim done As Byte
Dim again As Byte
Dim bad0 As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim bad4 As Byte
Dim lock As Byte
Dim sel As Byte
Dim stp As Byte
Dim a As Word
r1 = Dma.DmaCopy(2, @s, @d, 8)
done = Dma.DmaDone(2)
con0 = DMAnCON0
con1 = DMAnCON1
a = @s
ssa_ok = 0
If DMAnSSAL = Byte(a) And DMAnSSAH = Byte(a >> 8) And DMAnSSAU = 0 Then
    ssa_ok = 1
End If
a = @d
dsa_ok = 0
If DMAnDSAL = Byte(a) And DMAnDSAH = Byte(a >> 8) Then
    dsa_ok = 1
End If
sszl = DMAnSSZL
sszh = DMAnSSZH
dszl = DMAnDSZL
again = Dma.DmaCopy(2, @s, @d, 4)
bad0 = Dma.DmaCopy(0, @s, @d, 8)
bad1 = Dma.DmaCopy(5, @s, @d, 8)
bad2 = Dma.DmaCopy(1, @s, @d, 0)
bad3 = Dma.DmaCopy(1, @s, @d, 4096)
bad4 = Dma.DmaDone(7)
lock = PRLOCK And 1
Dma.DmaStop(2)
stp = DMAnCON0
sel = DMASELECT
