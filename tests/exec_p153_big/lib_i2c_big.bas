' expect: IB_X1=0 IB_X2=0 IB_X3=0 IB_OK=1 IB_PSCL=21 IB_PSDA=22 IB_CLK=9 IB_DAT=10
' I2c on the PIC16(L)F15386: SCL1, SDA1, SSP1CLKPPS and SSP1DATPPS reach ports B and C only (DS40001866E Tables 15-3 p.238 and 15-7 p.243), and only RB1, RB2, RC3 and RC4 have the I2C input buffers (15.3 note p.240). Refused: SCL on RA1 (1),
' SDA on RD0 (24), SCL on RE0 (32). Accepted: SCL on RB1 (9) and SDA on RB2 (10): RB1PPS = 15h, RB2PPS = 16h, SSP1CLKPPS = 9, SSP1DATPPS = 10.
Program Ib
Device = 16F15386
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "i2c"
Dim x1 As Byte
Dim x2 As Byte
Dim x3 As Byte
Dim ok As Byte
Dim pscl As Byte
Dim psda As Byte
Dim clk As Byte
Dim dat As Byte
x1 = I2c.I2cInit(100000, 1, 10)
x2 = I2c.I2cInit(100000, 9, 24)
x3 = I2c.I2cInit(100000, 32, 10)
ok = I2c.I2cInit(100000, 9, 10)
pscl = RB1PPS
psda = RB2PPS
clk = SSP1CLKPPS
dat = SSP1DATPPS
