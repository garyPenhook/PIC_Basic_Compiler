' expect: KI_I=1 KI_ADD=39 KI_R=17 KI_ST=0 KI_P=1 KI_NO=3 KI_W=0 KI_B0=34 KI_B1=51 KI_BAD=0
' stim: lib_i2c.stim.toml
' I2C library on the PIC18(L)F2x/4xK22 (DS40001412H chapter 15): MSSP1 as host on its fixed pins SCL1 = RC3 (19), SDA1 = RC4 (20); 400 kHz
' at 64 MHz: SSP1ADD = ceil(64 MHz / (4 * 400 kHz)) - 1 = 39. A register read, a ping of the client and of an absent address (no
' acknowledge, status 3), a register write and a two-byte block read. Other pins are refused.
Program Ki
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "i2c"
Dim i As Byte
Dim add As Byte
Dim r As Byte
Dim st As Byte
Dim p As Byte
Dim no As Byte
Dim w As Byte
Dim b0 As Byte
Dim b1 As Byte
Dim bad As Byte
i = I2c.I2cInit(400000, 19, 20)
add = SSP1ADD
r = I2c.I2cReadReg(80, 0)
st = I2c.I2cStatus()
If I2c.I2cPing(80) Then
    p = 1
End If
no = I2c.I2cProbe(81)
w = I2c.I2cWriteReg(80, 3, 9)
w = w + I2c.I2cReadRegs(80, 1, 2)
b0 = I2c.I2cBuf(0)
b1 = I2c.I2cBuf(1)
I2c.I2cOff(19, 20)
bad = I2c.I2cInit(100000, 8, 9)
