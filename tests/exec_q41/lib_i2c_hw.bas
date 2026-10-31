' expect: LH_S0=4 LH_S1=4 LH_S2=4 LH_BAD1=0 LH_BAD2=0 LH_BAD3=0 LH_BAD4=0 LH_BAD5=0 LH_OK=1 LH_BAUD=31 LH_CON0=132 LH_CON2=16 LH_CLK=0 LH_PPS0=33 LH_PPS1=34 LH_SCLIN=16 LH_SDAIN=17 LH_ANS=0 LH_ODC=3 LH_RN0=5 LH_RN9=5 LH_WN0=5 LH_WN9=5 LH_OFF0=0 LH_OFFPPS=0 LH_OFFR=4
' I2c library on the PIC18F16Q41 with `#option I2c = Hardware` (the I2C1 peripheral): not initialised answers 4. I2cInit(100000, RC0, RC1)
' at 64 MHz: I2C1CLK = 0 (FOSC/4), I2C1BAUD = 16 MHz / (5 * 100 kHz) - 1 = 31, I2C1CON2 = ABD (16), I2C1CON0 = EN | host 7-bit (132),
' RC0PPS = 33 (SCL1) and RC1PPS = 34 (SDA1) [DS40002214G Table 21-2], I2C1SCLPPS / I2C1SDAPPS = the pins, RC0 and RC1 digital and open
' drain. Bad pins (RA3 is input only), equal pins and a rate out of 1..400000 or too slow for the divider are refused; a count outside 1..8
' is refused before the peripheral is touched. The simulator has no I2C1 model (SimPeripheralSupport.csv), so the transfers are not run
' here: scripts/test_i2chw.py runs them on an instruction-level model.
Program Lh
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#option I2c = Hardware
Include "i2c"
Dim s0 As Byte
Dim s1 As Byte
Dim s2 As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim bad4 As Byte
Dim bad5 As Byte
Dim ok As Byte
Dim baud As Byte
Dim con0 As Byte
Dim con2 As Byte
Dim clk As Byte
Dim pps0 As Byte
Dim pps1 As Byte
Dim sclin As Byte
Dim sdain As Byte
Dim ans As Byte
Dim odc As Byte
Dim rn0 As Byte
Dim rn9 As Byte
Dim wn0 As Byte
Dim wn9 As Byte
Dim off0 As Byte
Dim offpps As Byte
Dim offr As Byte
s0 = I2c.I2cReadRegs(111, 0, 1)
s1 = I2c.I2cWriteRegs(111, 0, 1)
s2 = I2c.I2cProbe(111)
ANSELC = 255
ODCONC = 0
bad1 = I2c.I2cInit(100000, 3, 17)
bad2 = I2c.I2cInit(100000, 16, 16)
bad3 = I2c.I2cInit(0, 16, 17)
bad4 = I2c.I2cInit(500000, 16, 17)
bad5 = I2c.I2cInit(100, 16, 17)
ok = I2c.I2cInit(100000, 16, 17)
baud = I2C1BAUD
con0 = I2C1CON0
con2 = I2C1CON2
clk = I2C1CLK
pps0 = RC0PPS
pps1 = RC1PPS
sclin = I2C1SCLPPS
sdain = I2C1SDAPPS
ans = ANSELC And 3
odc = ODCONC And 3
rn0 = I2c.I2cReadRegs(111, 0, 0)
rn9 = I2c.I2cReadRegs(111, 0, 9)
wn0 = I2c.I2cWriteRegs(111, 0, 0)
wn9 = I2c.I2cWriteRegs(111, 0, 9)
I2c.I2cOff(16, 17)
off0 = I2C1CON0
offpps = RC0PPS Or RC1PPS
offr = I2c.I2cReadRegs(111, 0, 1)
