' expect: KL_I=1 KL_O=1 KL_ST=0 KL_P=1
' stim: lib_oled.stim.toml
' engine: sim
' The oled module over the hardware I2C host on the PIC18(L)F2x/4xK22: MSSP1 on its fixed pins SCL1 = RC3 (19), SDA1 = RC4 (20)
' (DS40001412H Tables 2, 3 p.6-7) and a simulated OLED at 3Ch on them, which acknowledges the set-up bytes.
Program Kl
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "i2c"
Include "oled"
Dim i As Byte
Dim o As Byte
Dim st As Byte
Dim p As Byte
i = I2c.I2cInit(400000, 19, 20)
o = Oled.OledInitI2c(60, 255)
st = Oled.OledStatus()
If I2c.I2cPing(60) Then
    p = 1
End If
