' expect: FL_BAD=0
' devices: 18F27Q10
' FLog against values computed on the host with a relative error bound of 5e-7 (3e-7 expected; the s^9 term of the series is left out, see FMath.FLog), and absolute 5e-7 near zero.
Program Fl
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "fmath"
Dim bad As Byte
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
    If d > want * 0.0000005 Then
        Inc(bad)
    End If
End Sub
bad = 0
Chk(FLog(0.001), -6.907755278982137)
Chk(FLog(0.05), -2.995732273553991)
Chk(FLog(0.3), -1.2039728043259361)
Chk(FLog(0.5), -0.6931471805599453)
Chk(FLog(0.7071), -0.346583180371942)
Chk(FLog(0.9), -0.10536051565782628)
Chk(FLog(0.999), -0.0010005003335835344)
Chk(FLog(1.001), 0.0009995003330834232)
Chk(FLog(1.2), 0.1823215567939546)
Chk(FLog(1.4142), 0.3465640001880033)
Chk(FLog(1.5), 0.4054651081081644)
Chk(FLog(2), 0.6931471805599453)
Chk(FLog(2.718281828), 0.9999999998311266)
Chk(FLog(3.3), 1.1939224684724346)
Chk(FLog(7.5), 2.0149030205422647)
Chk(FLog(10), 2.302585092994046)
Chk(FLog(100), 4.605170185988092)
Chk(FLog(1234.5), 7.118421308785234)
Chk(FLog(65536), 11.090354888959125)
Chk(FLog(1000000.0), 13.815510557964274)
Chk(FLog(3300000000.0), 21.917188305418847)
Chk(FLog(0.00000001), -18.420680743952367)
Chk(FLog(0.0000000000000000001), -43.74911676688687)
