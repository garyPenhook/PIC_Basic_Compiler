' expect: FM_FM_BAD=0
' FMath against values computed on the host (relative error under 2e-6, or 2e-6 absolute near zero), on the PIC16F13245 (DS40002686B), where the Float routines are Basic code and not the PIC18 assembly.
Program Fm
Device = 16F13245
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "fmath"
Dim fm_bad As Byte
Sub Chk(ByVal got As Float, ByVal want As Float)
    Dim d As Float
    d = got - want
    If d < 0 Then
        d = -d
    End If
    If want < 0 Then
        want = -want
    End If
    If want < 1 Then
        want = 1
    End If
    If d > want * 0.000004 Then
        Inc(fm_bad)
    End If
End Sub
fm_bad = 0
Chk(FSqr(2), 1.41421356)
Chk(FSqr(144), 12)
Chk(FSqr(0.01), 0.1)
Chk(FLog(2.718281828), 1)
Chk(FLog(10), 2.30258509)
Chk(FLog(0.001), -6.90775528)
Chk(FLog10(1000), 3)
Chk(FExp(1), 2.71828183)
Chk(FExp(-2.5), 0.0820849986)
Chk(FExp(10), 22026.4658)
Chk(FPow(2, 10), 1024)
Chk(FSin(0.5), 0.479425539)
Chk(FSin(3), 0.141120008)
Chk(FSin(-2), -0.909297427)
Chk(FSin(100), -0.506365641)
Chk(FCos(1), 0.540302306)
Chk(FCos(3), -0.989992497)
Chk(FTan(0.7), 0.842288380)
