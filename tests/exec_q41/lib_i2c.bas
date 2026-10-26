' expect: LI_S0=4 LI_OK=1 LI_TC=24 LI_LC=0 LI_BAD1=0 LI_BAD2=0 LI_BAD3=0 LI_BAD4=0 LI_BAD5=0 LI_OFF=4
' I2c library on the PIC18F16Q41 (software host, no peripheral): not initialised answers 4; I2cInit(100000, RC3, RC4)
' releases both pins (TRISC bits 3 and 4 set, LATC bits clear). Bad pins (RA3 is input only), equal pins and a
' clock out of 2000..400000 are refused. The simulator has no bus, so the transfer routines are not run here.
Program Li
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "i2c"
Dim s0 As Byte
Dim ok As Byte
Dim tc As Byte
Dim lc As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim bad4 As Byte
Dim bad5 As Byte
Dim off As Byte
s0 = I2c.I2cStart()
TRISC = 0
LATC = 255
ok = I2c.I2cInit(100000, 19, 20)
tc = TRISC And 24
lc = LATC And 24
bad1 = I2c.I2cInit(100000, 3, 20)
bad2 = I2c.I2cInit(100000, 19, 19)
bad3 = I2c.I2cInit(1000, 19, 20)
bad4 = I2c.I2cInit(500000, 19, 20)
bad5 = I2c.I2cInit(100000, 24, 20)
I2c.I2cOff(19, 20)
off = I2c.I2cStart()
