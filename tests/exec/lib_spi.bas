' expect: LS_S0=4 LS_OK=1 LS_ADD=15 LS_CON=42 LS_STAT=64 LS_CLK=19 LS_DAT=21 LS_PPSC=15 LS_PPSD=16 LS_TRIS=32 LS_OK3=1 LS_CON3=48 LS_STAT3=0 LS_OK1=1 LS_ADD1=1 LS_CON1=42 LS_STAT1=0 LS_NOSDO=1 LS_PPSN=0 LS_BAD1=0 LS_BAD2=0 LS_BAD3=0 LS_BAD4=0 LS_BAD5=0 LS_BAD6=0 LS_OFF=0 LS_PPSOFF=0
Program Ls
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "spi"
Dim s0 As Byte
Dim ok As Byte
Dim add As Byte
Dim con As Byte
Dim stat As Byte
Dim clk As Byte
Dim dat As Byte
Dim ppsc As Byte
Dim ppsd As Byte
Dim tris As Byte
Dim ok3 As Byte
Dim con3 As Byte
Dim stat3 As Byte
Dim ok1 As Byte
Dim add1 As Byte
Dim con1 As Byte
Dim stat1 As Byte
Dim nosdo As Byte
Dim ppsn As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim bad4 As Byte
Dim bad5 As Byte
Dim bad6 As Byte
Dim off As Byte
Dim ppsoff As Byte
Dim v As Byte
' Not initialised: status 4.
v = Spi.SpiTransfer(1)
s0 = Spi.SpiStatus()
' 1 MHz mode 0 at 64 MHz: SSPxADD = 64000000 / 4000000 - 1 = 15, SSPM = 1010, SSPEN, CKE = 1.
ok = Spi.SpiInit(1000000, 0, 19, 20, 21)
add = SSP1ADD
con = SSP1CON1
stat = SSP1STAT
clk = SSP1CLKPPS
dat = SSP1DATPPS
ppsc = RC3PPS
ppsd = RC4PPS
tris = TRISC And 56
' 16 MHz (FOSC / 4) mode 3: SSPM = 0000, CKP = 1, CKE = 0.
ok3 = Spi.SpiInit(16000000, 3, 19, 20, 21)
con3 = SSP1CON1
stat3 = SSP1STAT
' 8 MHz mode 1: SSPxADD = 1.
ok1 = Spi.SpiInit(8000000, 1, 19, 20, 21)
add1 = SSP1ADD
con1 = SSP1CON1
stat1 = SSP1STAT
' Receive-only: SDO = 255 leaves RC4 unrouted.
Spi.SpiOff(19, 20)
nosdo = Spi.SpiInit(1000000, 0, 19, 255, 21)
ppsn = RC4PPS
' Refused: mode 4, SCK on port A, SDO = SCK, SDI = SCK, clock below FOSC / 1024, zero.
bad1 = Spi.SpiInit(1000000, 4, 19, 20, 21)
bad2 = Spi.SpiInit(1000000, 0, 3, 20, 21)
bad3 = Spi.SpiInit(1000000, 0, 19, 19, 21)
bad4 = Spi.SpiInit(1000000, 0, 19, 20, 19)
bad5 = Spi.SpiInit(10000, 0, 19, 20, 21)
bad6 = Spi.SpiInit(0, 0, 19, 20, 21)
' The routines end in bounded time whatever the module does.
ok = Spi.SpiInit(1000000, 0, 19, 20, 21)
v = Spi.SpiTransfer(165)
Spi.SpiWrite(1)
v = Spi.SpiRead()
Spi.SpiOff(19, 20)
off = SSP1CON1
ppsoff = RC3PPS
