' The I2C1 hardware host with the Rtcc driver on top: must build with no warning on every part of the PIC18-Q41 family (the 14-pin parts have no port B).
Program T
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#option I2c = Hardware
Include "i2c"
Include "rtcc"
Dim s As Byte
Dim v As Byte
s = I2cInit(100000, 16, 17)
s = I2cProbe(111)
s = I2cWriteRegs(111, 0, 2)
s = I2cReadRegs(111, 0, 7)
v = I2cReadReg(111, 3)
s = RtccRead()
s = RtccSecond()
s = RtccEeRead(0, v)
I2cOff(16, 17)
