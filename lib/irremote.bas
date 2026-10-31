Module Irremote
Include "pinio"
Include "pulse"
' Decoders for two infrared remote-control codes, from the output of a 38 kHz / 36 kHz receiver module (TSOP17xx
' type), which idles high and goes low while a burst is received. Pins are numbered 0..23 as in `Pinio`.
'
' Both functions return a Word: the command in the low byte and the system (address) in the high byte, or 65535
' ($FFFF, command and system 255) when no frame, or no valid frame, came in. They wait up to about 0.65 s for the
' frame to start. The pin is made an input. Interrupts during a frame lengthen its timing and spoil the decode.

' Number of 10 us polls (plus loop time) that pin stays at `level`, counting to at most `limit`; limit + 1 when it
' stayed that long. A step is about 10 to 14 us at 16 MHz and above.
Function Width(ByVal pin As Byte, ByVal level As Boolean, ByVal limit As Word) As Word
    Dim n As Word
    n = 0
    While Pinio.PinGet(pin) = level
        If n > limit Then
            Result = n
            Exit
        End If
        DelayUS(10)
        n = n + 1
    Wend
    Result = n
End Function

' Sony SIRC, 12 bit frames: a 2.4 ms burst, then 12 bits LSB first (7 command bits, 5 system bits), each a burst of
' 0.6 ms (0) or 1.2 ms (1) followed by a 0.6 ms gap. The pulse widths are judged against the width of the header,
' so the result does not depend on the exact poll time.
Public Function SonyIn(ByVal pin As Byte) As Word
    Dim header As Word
    Dim w As Word
    Dim v As Word
    Dim i As Byte
    Result = 65535
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.PinInput(pin)
    ' idle high, then the header burst
    If Width(pin, False, 1000) > 1000 Then
        Exit
    End If
    If Width(pin, True, 65000) > 65000 Then
        Exit
    End If
    header = Width(pin, False, 1000)
    ' 2.4 ms is 240 polls of 10 us; allow 0.6 to 1.5 times that
    If header < 140 Or header > 360 Then
        Exit
    End If
    v = 0
    For i = 0 To 11
        If Width(pin, True, 200) > 200 Then
            Exit
        End If
        w = Width(pin, False, 1000)
        ' 1.2 ms against 0.6 ms: the threshold is 0.9 ms, 3/8 of the 2.4 ms header
        If w * 8 > header * 3 Then
            v = v Or (1 << i)
        End If
    Next
    Result = ((v >> 7) << 8) Or (v And 127)
End Function

' Philips RC5, 14 bits Manchester coded at 1.778 ms per bit: two start bits (the second is the inverse of command
' bit 6, so commands run 0..127), a toggle bit, 5 system bits and 6 command bits, most significant first. The line is
' sampled in the second half of each bit, a low level being a 1. The toggle bit is not returned. The sample points drift by
' the time of the loop (a few us at 16 MHz and above), so use a clock of 16 MHz or more.
Public Function RC5In(ByVal pin As Byte) As Word
    Dim v As Word
    Dim i As Byte
    Result = 65535
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.PinInput(pin)
    If Width(pin, False, 1000) > 1000 Then
        Exit
    End If
    ' the line has to be idle (high), then fall in the middle of the first start bit
    If Width(pin, True, 65000) > 65000 Then
        Exit
    End If
    ' The edge is the middle of the first start bit. A bit is 1.778 ms, so the second half of the next bit is centred
    ' 1.25 bits (2.222 ms) after the edge; the delay is a little short to allow for the poll and the calls.
    Pulse.WaitUs(2150)
    v = 0
    For i = 1 To 13
        v = v << 1
        If Not Pinio.PinGet(pin) Then
            v = v Or 1
        End If
        Pulse.WaitUs(1770)
    Next
    ' v: bit 12 = start 2, bit 11 = toggle, bits 10..6 = system, bits 5..0 = command
    Result = (((v >> 6) And 31) << 8) Or (v And 63)
    If (v And 4096) = 0 Then
        Result = Result Or 64
    End If
End Function
