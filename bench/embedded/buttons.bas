' expect: K_SINK=2652
Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim sink As LongWord

' A 1 ms cooperative tick: debounce active-high input and service periodic jobs.
Dim tick As Word
Dim raw, stable, count, previous, led, fastTimer, slowTimer As Byte
Dim presses, fastRuns, slowRuns As Word
fastTimer = 10
slowTimer = 100
For tick = 0 To 999
    raw = 0
    If (tick >= 100 And tick < 300) Or (tick >= 500 And tick < 800) Then
        raw = 1
    End If
    If (tick >= 100 And tick < 106) Or (tick >= 300 And tick < 306) Or (tick >= 500 And tick < 506) Or (tick >= 800 And tick < 806) Then
        raw = Byte(tick And 1)
    End If
    If raw = previous Then
        If count < 5 Then
            count = count + 1
        End If
    Else
        previous = raw
        count = 1
    End If
    If count = 5 And stable <> raw Then
        stable = raw
        If stable <> 0 Then
            presses = presses + 1
            led = led Xor 1
        End If
    End If
    fastTimer = fastTimer - 1
    If fastTimer = 0 Then
        fastTimer = 10
        fastRuns = fastRuns + 1
        sink = sink + stable + led
    End If
    slowTimer = slowTimer - 1
    If slowTimer = 0 Then
        slowTimer = 100
        slowRuns = slowRuns + 1
        sink = sink + fastRuns
    End If
Next
sink = sink + LongWord(presses) * 1000 + slowRuns
