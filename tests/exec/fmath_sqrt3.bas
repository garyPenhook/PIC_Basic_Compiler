' expect: SQ3_DIFF=0 SQ3_N=3000
Program Sq3
' Three Newton steps of FSqr give the same bits as four (the guess from halving the exponent is within 4 %): the loop of FMath.FSqr against one step more, 3000 values.
' devices: 18F27Q10
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "floatlib"
Dim x As Float
Dim xw As x.AsLongWord
Dim g3 As Float
Dim g3w As g3.AsLongWord
Dim g4 As Float
Dim g4w As g4.AsLongWord
Dim i As Byte
Dim k As Word
Dim diff As Word
Dim n As Word
diff = 0
n = 0
For k = 0 To 2999
    ' mantissa sweep over [1,4) in steps, exponent varied with k
    xw = $3F800000 + LongWord(k) * 2796 + (LongWord(k And 15) << 23) + (LongWord(k And 1) << 22)
    g3w = (xw >> 1) + $1FBD1DF5
    g4w = g3w
    For i = 1 To 3
        g3 = 0.5 * (g3 + x / g3)
    Next
    For i = 1 To 4
        g4 = 0.5 * (g4 + x / g4)
    Next
    If g3w <> g4w Then
        Inc(diff)
    End If
    Inc(n)
Next
