' expect: LDE_R=1 LDE_CON0=160 LDE_CON1=90 LDE_SSAU=0 LDE_SSAH=0 LDE_SSAL=16 LDE_SSZL=4 LDE_DSA_OK=1 LDE_BAD1=0 LDE_BAD2=0 LDE_BAD3=0 LDE_R2=1 LDE_SSAH2=1 LDE_SSAL2=252
' DmaCopyEeprom on the PIC18F16Q41 (512 bytes of EEPROM; the simulator does not model the engine): DMAnCON1 = 5Ah
' (SMR = 11, both pointers increment), source offset 16, 4 bytes. A busy channel, an offset past the end, a copy
' running off the end (508 + 5) and a count of 0 are refused; 508 + 4 is accepted. Data movement: not run on a real part.
Program Lde
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "dma"
Dim d(8) As Byte
Dim r As Byte
Dim con0 As Byte
Dim con1 As Byte
Dim ssau As Byte
Dim ssah As Byte
Dim ssal As Byte
Dim sszl As Byte
Dim dsa_ok As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim r2 As Byte
Dim ssah2 As Byte
Dim ssal2 As Byte
Dim w As Word
r = Dma.DmaCopyEeprom(1, 16, @d, 4)
con0 = DMAnCON0
con1 = DMAnCON1
ssau = DMAnSSAU
ssah = DMAnSSAH
ssal = DMAnSSAL
sszl = DMAnSSZL
w = @d
dsa_ok = 0
If DMAnDSAL = Byte(w) And DMAnDSAH = Byte(w >> 8) Then
    dsa_ok = 1
End If
bad1 = Dma.DmaCopyEeprom(1, 0, @d, 4)
Dma.DmaStop(1)
bad2 = Dma.DmaCopyEeprom(1, 508, @d, 5)
bad3 = Dma.DmaCopyEeprom(1, 512, @d, 1)
r2 = Dma.DmaCopyEeprom(1, 508, @d, 4)
ssah2 = DMAnSSAH
ssal2 = DMAnSSAL
