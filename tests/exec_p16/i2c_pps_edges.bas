' expect: PE_REF=1 PE_E1=1 PE_N1=0 PE_OFF1=0 PE_E2=1 PE_N2=0 PE_OFF2=0 PE_BAD=0
' The RxyPPS write of module I2c goes through FSR0 at RA0PPS + pin: the edge pins every part with a port C has (RA0, RA5, RC0, RC5) get the SCL / SDA code,
' the registers next to them stay 0, and I2cOff gives them back. The code is read from a reference pin (RC1 / RC2), so the test holds for every family's own codes.
' `tests/exec_p132/i2c_pps_edges20.bas` has the pins of the 20-pin parts (RB4, RB5, RC6, RC7).
Program Pe
Device = 16F17146
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
' RA0 = SCL, RC5 = SDA
ok = I2c.I2cInit(100000, 0, 21)
e1 = 0
If RA0PPS = scl And RC5PPS = sda Then
    e1 = 1
End If
n1 = RA1PPS Or RA2PPS Or RA4PPS Or RC4PPS Or RC3PPS
I2c.I2cOff(0, 21)
off1 = RA0PPS Or RC5PPS
' RA5 = SCL, RC0 = SDA
ok = I2c.I2cInit(100000, 5, 16)
e2 = 0
If RA5PPS = scl And RC0PPS = sda Then
    e2 = 1
End If
n2 = RA4PPS Or RA2PPS Or RA1PPS Or RC1PPS Or RC2PPS
I2c.I2cOff(5, 16)
off2 = RA5PPS Or RC0PPS
If RA5PPS <> 0 Or RC0PPS <> 0 Or RA0PPS <> 0 Or RC5PPS <> 0 Then
    Inc(bad)
End If
