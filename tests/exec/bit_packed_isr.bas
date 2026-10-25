' expect: BPI_HITS=200 BPI_OK=1 BPI_MAIN=4
' A packed bit array whose neighbouring elements are written by main-line code (run-time index)
' and by an interrupt handler. The run-time write is a read-modify-write of a shared byte, so it
' runs with interrupts off; without that, a handler write landing between the read and the
' write is lost. Reaching 200 hits also shows interrupts come back on after each write.
Program BPI
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim pk(16) As Bit
Dim hits As Word
Dim ok As Byte
Dim main As Byte
Dim i As Byte
Dim j As Byte

Interrupt Tick()
    PIR0.5 = 0
    Inc(hits)
    If (hits And 1) = 1 Then
        pk(1) = 1
    Else
        pk(1) = 0
    End If
    If (hits And 2) = 2 Then
        pk(3) = 1
    Else
        pk(3) = 0
    End If
    If hits < 200 Then
        TMR0H = 250 + Byte(hits And 3)
    Else
        T0CON0 = 0
    End If
End Interrupt

PIE0.5 = 1
Enable(Tick)
T0CON1 = 65
T0CON0 = 128
While hits < 200
    For i = 0 To 3
        j = i * 2
        pk(j) = 1
        pk(j + 8) = 1
        pk(j + 8) = 0
    Next
Wend
Disable(Tick)
ok = 1
If pk(1) <> Byte(hits And 1) Then
    ok = 0
End If
If pk(3) <> Byte((hits >> 1) And 1) Then
    ok = 0
End If
main = 0
For i = 0 To 3
    j = i * 2
    If pk(j) = 1 Then
        Inc(main)
    End If
Next
