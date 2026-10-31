' expect: LQ_MSKS=16642103 LQ_MSKD=16707639
' The pins `I2cInit` accepts on the PIC18F16Q41 (software host): RA0..RA2, RA4, RA5, RB4..RB7, RC0..RC7 (RA3 is input only; RA6, RA7 and RB0..RB3
' do not exist), as a bit mask over the pin numbers 0..31, once with SCL scanned (SDA on RC1, so RC1 is refused as equal pins) and once with SDA scanned.
' scripts/test_i2chw.py checks that the hardware host accepts the same set, so the two pin checks cannot drift apart.
Program Lq
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "i2c"
Dim mskS As LongWord
Dim mskD As LongWord
Dim p As Byte
Dim r As Byte
mskS = 0
mskD = 0
For p = 0 To 31
    r = I2cInit(100000, p, 17)
    If r = 1 Then
        mskS = mskS Or (LongWord(1) << p)
    End If
    r = I2cInit(100000, 16, p)
    If r = 1 Then
        mskD = mskD Or (LongWord(1) << p)
    End If
Next
