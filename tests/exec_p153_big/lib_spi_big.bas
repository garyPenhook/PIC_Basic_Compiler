' expect: SB_X1=0 SB_X2=0 SB_X3=0 SB_X4=0 SB_X5=0 SB_OK=1 SB_PSCK=21 SB_PSDO=22 SB_CLK=11 SB_DAT=17
' Spi on the PIC16(L)F15386: SCK1, SDO1 and the inputs SSP1CLKPPS and SSP1DATPPS reach ports B and C only (DS40001866E Tables 15-3 p.238 and 15-7 p.243). Refused: SCK on RA5 (5), SDO on RD0 (24), SDI on RA0 (0), SDI on RE1 (33),
' a pin above port F (48). Accepted: SCK on RB3 (11), SDO on RC2 (18), SDI on RC1 (17): RB3PPS = 15h, RC2PPS = 16h, SSP1CLKPPS = 11, SSP1DATPPS = 17.
Program Sb
Device = 16F15386
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "spi"
Dim x1 As Byte
Dim x2 As Byte
Dim x3 As Byte
Dim x4 As Byte
Dim x5 As Byte
Dim ok As Byte
Dim psck As Byte
Dim psdo As Byte
Dim clk As Byte
Dim dat As Byte
x1 = Spi.SpiInit(100000, 0, 5, 18, 17)
x2 = Spi.SpiInit(100000, 0, 11, 24, 17)
x3 = Spi.SpiInit(100000, 0, 11, 18, 0)
x4 = Spi.SpiInit(100000, 0, 11, 18, 33)
x5 = Spi.SpiInit(100000, 0, 48, 18, 17)
ok = Spi.SpiInit(100000, 0, 11, 18, 17)
psck = RB3PPS
psdo = RC2PPS
clk = SSP1CLKPPS
dat = SSP1DATPPS
