' expect: P2_REF=1 P2_E1=1 P2_N1=0 P2_OFF1=0 P2_E2=1 P2_N2=0 P2_OFF2=0 P2_BAD=0
' The RxyPPS write of module I2c goes through FSR0 at RA0PPS + pin: the edge pins of the 20-pin parts (RA0, RA5, RB4, RB5, RC6, RC7) get the SCL / SDA code,
' the registers next to them stay 0, and I2cOff gives them back. The code is read from a reference pin (RC1 / RC2), so the test holds for every family's own codes.
Program P2
Device = 16F13245
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "i2c"
Dim scl As Byte
Dim sda As Byte
Dim ref As Byte
Dim e1 As Byte
Dim n1 As Byte
Dim off1 As Byte
Dim e2 As Byte
Dim n2 As Byte
Dim off2 As Byte
Dim bad As Byte
Dim ok As Byte
bad = 0
ok = I2c.I2cInit(100000, 17, 18)
scl = RC1PPS
sda = RC2PPS
ref = 0
If scl <> 0 And sda <> 0 And scl <> sda Then
    ref = 1
End If
I2c.I2cOff(17, 18)
' RA0 = SCL, RC7 = SDA
ok = I2c.I2cInit(100000, 0, 23)
e1 = 0
If RA0PPS = scl And RC7PPS = sda Then
    e1 = 1
End If
n1 = RA1PPS Or RA2PPS Or RA4PPS Or RC6PPS Or RC5PPS
I2c.I2cOff(0, 23)
off1 = RA0PPS Or RC7PPS
' RB4 = SCL, RA5 = SDA, then RB5 = SCL, RC6 = SDA
ok = I2c.I2cInit(100000, 12, 5)
e2 = 0
If RB4PPS = scl And RA5PPS = sda Then
    e2 = 1
End If
n2 = RB5PPS Or RB6PPS Or RB7PPS Or RA4PPS Or RA2PPS
I2c.I2cOff(12, 5)
off2 = RB4PPS Or RA5PPS
ok = I2c.I2cInit(100000, 13, 22)
If RB5PPS <> scl Or RC6PPS <> sda Then
    Inc(bad)
End If
I2c.I2cOff(13, 22)
If RB5PPS <> 0 Or RC6PPS <> 0 Then
    Inc(bad)
End If
