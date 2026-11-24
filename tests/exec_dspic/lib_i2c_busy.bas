' expect: I_ST=1 I_S1=2 I_S2=1 I_DONE=1
' Library i2c on the dsPIC33CK with no pull-ups: both lines read low in the simulator, so Start finds the bus busy (status 2) and the byte routine, clocking SCL that never rises, reports a stuck clock (status 1).
Program I
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "i2c"
Dim ST As Byte
Dim S1 As Byte
Dim S2 As Byte
Dim DONE As Byte
ST = I2c.I2cInit(100000, 24, 25)
S1 = I2c.I2cStart()
S2 = I2c.I2cSend($A0)
DONE = 1
