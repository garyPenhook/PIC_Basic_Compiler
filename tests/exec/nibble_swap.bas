' expect: NS_BAD=0 NS_DONE=1
' `(x And m) * 16` and `(x And m) << 4` with m below 16 (the high nibble is clear, so a swap alone is the product) and with
' m above (the mask must stay), for every byte x. Each result is checked against the same product computed in a Word.
Program Ns
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x As Byte
Dim i As Word
Dim r As Byte
Dim w As Word
Dim bad As Word
Dim done As Byte
For i = 0 To 255
    x = Byte(i)
    r = (x And 3) * 16
    w = x And 3
    w = w * 16
    If r <> Byte(w) Then
        bad = bad + 1
    End If
    r = (x And 15) * 16
    w = x And 15
    w = w * 16
    If r <> Byte(w) Then
        bad = bad + 1
    End If
    r = 16 * (x And 7)
    w = x And 7
    w = w * 16
    If r <> Byte(w) Then
        bad = bad + 1
    End If
    r = (x And 31) * 16
    w = x And 31
    w = w * 16
    If r <> Byte(w) Then
        bad = bad + 1
    End If
    r = (x And 240) * 16
    w = x And 240
    w = w * 16
    If r <> Byte(w) Then
        bad = bad + 1
    End If
    r = (x And 5) << 4
    w = x And 5
    w = w * 16
    If r <> Byte(w) Then
        bad = bad + 1
    End If
    r = (x And 63) << 4
    w = x And 63
    w = w * 16
    If r <> Byte(w) Then
        bad = bad + 1
    End If
    r = ((x And 3) << 4) Or 3
    w = x And 3
    w = w * 16 + 3
    If r <> Byte(w) Then
        bad = bad + 1
    End If
Next
done = 1
