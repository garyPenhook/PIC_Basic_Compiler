' expect: I_ST=1 I_S1=0 I_S2=3 I_S3=0 I_PING=0 I_WR=3 I_BAD=0 I_DONE=1
' stim: lib_i2c.scl
' cycles: 13900 15500
' Library i2c on the dsPIC33CK: the software host on RB8 (SCL) and RB9 (SDA) with the lines pulled high by the stimulus file and no client on the bus. Start and Stop succeed, a byte is sent with every bit read back as sent (else status 2),
' the acknowledge reads high so the status is 3 (no acknowledge), I2cPing is False, I2cWriteReg gives 3, and pins the part lacks (RA5 = 5) or the same pin twice are refused by I2cInit.
Program I
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "i2c"
Dim ST As Byte
Dim S1 As Byte
Dim S2 As Byte
Dim S3 As Byte
Dim PING As Byte
Dim WR As Byte
Dim BAD As Byte
Dim DONE As Byte
BAD = I2c.I2cInit(100000, 5, 25)
BAD = BAD + I2c.I2cInit(100000, 25, 25)
BAD = BAD + I2c.I2cInit(1000, 24, 25)
ST = I2c.I2cInit(100000, 24, 25)
S1 = I2c.I2cStart()
S2 = I2c.I2cSend($A0)
S3 = I2c.I2cStop()
PING = 0
If I2c.I2cPing($50) Then
    PING = 1
End If
WR = I2c.I2cWriteReg($50, 1, 2)
DONE = 1
