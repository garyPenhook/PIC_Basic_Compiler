' expect: LDF_R=1 LDF_CON0=160 LDF_CON1=74 LDF_SSAU=0 LDF_SSA_OK=1 LDF_DSA_OK=1 LDF_SSZL=5 LDF_DSZL=5 LDF_BAD=0 LDF_HI=1 LDF_CON1H=74 LDF_SSAUH=1
' DmaCopyFlash on the PIC18F16Q41 (the simulator does not model the engine): checks DMAnCON1 = 4Ah (flash source,
' both pointers increment), the 22-bit source address taken from @table, the destination and the sizes. A second call
' on the busy channel is refused. Then a made-up flash address 0x01_2345 checks that bits 23:16 reach DMAnSSAU.
' Data movement: not run on a real part.
Program Ldf
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "dma"
Const tbl(5) As Byte = (1, 2, 3, 4, 5)
Dim d(5) As Byte
Dim r As Byte
Dim con0 As Byte
Dim con1 As Byte
Dim ssau As Byte
Dim ssa_ok As Byte
Dim dsa_ok As Byte
Dim sszl As Byte
Dim dszl As Byte
Dim bad As Byte
Dim hi As Byte
Dim con1h As Byte
Dim ssauh As Byte
Dim a As LongWord
Dim w As Word
r = Dma.DmaCopyFlash(1, @tbl, @d, 5)
con0 = DMAnCON0
con1 = DMAnCON1
ssau = DMAnSSAU
a = @tbl
ssa_ok = 0
If DMAnSSAL = Byte(a) And DMAnSSAH = Byte(a >> 8) Then
    ssa_ok = 1
End If
w = @d
dsa_ok = 0
If DMAnDSAL = Byte(w) And DMAnDSAH = Byte(w >> 8) Then
    dsa_ok = 1
End If
sszl = DMAnSSZL
dszl = DMAnDSZL
bad = Dma.DmaCopyFlash(1, @tbl, @d, 5)
Dma.DmaStop(1)
hi = Dma.DmaCopyFlash(1, 74565, @d, 5)
con1h = DMAnCON1
ssauh = DMAnSSAU
