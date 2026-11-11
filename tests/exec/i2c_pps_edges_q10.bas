' expect: PQ_REF=1 PQ_E1=1 PQ_N1=0 PQ_OFF1=0 PQ_E2=1 PQ_N2=0 PQ_OFF2=0 PQ_BAD=0
' devices: 18F27Q10
' The RxyPPS write of module I2c goes through FSR2 at RA0PPS + pin (pins 8..23 on the PIC18F27Q10): the edge pins RB0, RB7, RC0 and RC7 get the SCL / SDA code,
' the registers next to them stay 0, and I2cOff gives them back. The code is read from the reference pins RC3 / RC4 of the reset selection.
Program Pq
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
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
ok = I2c.I2cInit(100000, 19, 20)
scl = RC3PPS
sda = RC4PPS
ref = 0
If scl <> 0 And sda <> 0 And scl <> sda Then
    ref = 1
End If
I2c.I2cOff(19, 20)
' RB0 = SCL, RC7 = SDA
ok = I2c.I2cInit(100000, 8, 23)
e1 = 0
If RB0PPS = scl And RC7PPS = sda Then
    e1 = 1
End If
n1 = RB1PPS Or RB7PPS Or RC0PPS Or RC6PPS Or RB2PPS
I2c.I2cOff(8, 23)
off1 = RB0PPS Or RC7PPS
' RB7 = SCL, RC0 = SDA
ok = I2c.I2cInit(100000, 15, 16)
e2 = 0
If RB7PPS = scl And RC0PPS = sda Then
    e2 = 1
End If
n2 = RB6PPS Or RC1PPS Or RB0PPS Or RC7PPS
I2c.I2cOff(15, 16)
off2 = RB7PPS Or RC0PPS
If RB7PPS <> 0 Or RC0PPS <> 0 Or RB0PPS <> 0 Or RC7PPS <> 0 Then
    Inc(bad)
End If
