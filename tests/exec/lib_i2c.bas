' expect: LI_S0=4 LI_OK=1 LI_ADD=159 LI_STAT=128 LI_CON1=40 LI_CLK=19 LI_DAT=20 LI_PPSC=15 LI_PPSD=16 LI_TRIS=24 LI_OK4=1 LI_ADD4=39 LI_STAT4=0 LI_BAD1=0 LI_BAD2=0 LI_BAD3=0 LI_BAD4=0 LI_ADDK=39 LI_OFF=0 LI_PPSOFF=0
Program Li
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "i2c"
Dim s0 As Byte
Dim ok As Byte
Dim add As Byte
Dim stat As Byte
Dim con1 As Byte
Dim clk As Byte
Dim dat As Byte
Dim ppsc As Byte
Dim ppsd As Byte
Dim tris As Byte
Dim ok4 As Byte
Dim add4 As Byte
Dim stat4 As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim bad4 As Byte
Dim addk As Byte
Dim off As Byte
Dim ppsoff As Byte
Dim st As Byte
Dim ex As Byte
Dim p As Boolean
Dim v As Byte
' Not initialised: every routine answers 4.
s0 = I2c.I2cStart()
' 100 kHz at 64 MHz: SSPxADD = 64000000 / 400000 - 1 = 159, slew rate control disabled (SMP = 1).
ok = I2c.I2cInit(100000, 19, 20)
add = SSP1ADD
stat = SSP1STAT
con1 = SSP1CON1
clk = SSP1CLKPPS
dat = SSP1DATPPS
ppsc = RC3PPS
ppsd = RC4PPS
tris = TRISC And 24
' 400 kHz: SSPxADD = 39, SMP = 0.
ok4 = I2c.I2cInit(400000, 19, 20)
add4 = SSP1ADD
stat4 = SSP1STAT
' Refused: SCL on port A, the same pin twice, a clock below FOSC / 1024, zero.
bad1 = I2c.I2cInit(100000, 3, 20)
bad2 = I2c.I2cInit(100000, 19, 19)
bad3 = I2c.I2cInit(10000, 19, 20)
bad4 = I2c.I2cInit(0, 19, 20)
addk = SSP1ADD
' The routines end in bounded time whatever the bus does (the simulator has no pull-ups).
ok = I2c.I2cInit(100000, 19, 20)
st = I2c.I2cStart()
st = I2c.I2cSend(160)
v = I2c.I2cReceive(True)
st = I2c.I2cStop()
p = I2c.I2cPing(80)
ex = I2c.I2cWriteReg(80, 1, 2)
v = I2c.I2cReadReg(80, 1)
I2c.I2cOff(19, 20)
off = SSP1CON1
ppsoff = RC3PPS
