' expect: BB_BAD=0 BB_DONE=1
' A Boolean built from a bit test or a flag test (`r = (b = 1)`, `r = (x = 3)`, `r = (x < 5)`, with Not, And and Or) against the same test written as an If. BB_BAD counts the differences.
Program Bb
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim f As Byte
Dim b0 As f.0
Dim b5 As f.5
Dim x As Byte
Dim r As Boolean
Dim e As Boolean
Dim bad As Byte
Dim i As Byte
Dim vals(5) As Byte
Dim done As Byte
vals(0) = 3
vals(1) = 5
vals(2) = 200
vals(3) = 0
vals(4) = 255
For i = 0 To 4
    x = vals(i)
    f = x
    r = (b0 = 1)
    e = False
    If b0 = 1 Then
        e = True
    End If
    If r <> e Then
        bad = bad + 1
    End If
    r = (b0 = 0)
    e = False
    If b0 = 0 Then
        e = True
    End If
    If r <> e Then
        bad = bad + 1
    End If
    r = (b5 <> 0)
    e = False
    If b5 <> 0 Then
        e = True
    End If
    If r <> e Then
        bad = bad + 1
    End If
    r = Not (b5 = 1)
    e = True
    If b5 = 1 Then
        e = False
    End If
    If r <> e Then
        bad = bad + 1
    End If
    r = (x = 3)
    e = False
    If x = 3 Then
        e = True
    End If
    If r <> e Then
        bad = bad + 1
    End If
    r = (x <> 3)
    e = False
    If x <> 3 Then
        e = True
    End If
    If r <> e Then
        bad = bad + 1
    End If
    r = (x < 5)
    e = False
    If x < 5 Then
        e = True
    End If
    If r <> e Then
        bad = bad + 1
    End If
    r = (x >= 5)
    e = False
    If x >= 5 Then
        e = True
    End If
    If r <> e Then
        bad = bad + 1
    End If
    r = (b0 = 1) And (x > 4)
    e = False
    If b0 = 1 Then
        If x > 4 Then
            e = True
        End If
    End If
    If r <> e Then
        bad = bad + 1
    End If
    r = (b0 = 1) Or (b5 = 1)
    e = False
    If b0 = 1 Then
        e = True
    End If
    If b5 = 1 Then
        e = True
    End If
    If r <> e Then
        bad = bad + 1
    End If
Next
done = 1
