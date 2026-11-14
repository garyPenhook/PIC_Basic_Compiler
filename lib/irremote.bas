Module Irremote
Include "pinio"
Include "pulse"
' Decoders for two infrared remote-control codes, from the output of a 38 kHz / 36 kHz receiver module (TSOP17xx
' type), which idles high and goes low while a burst is received. Pins are numbered as in `Pinio` (RA0 = 0, RB0 = 8, RC0 = 16; up to 47 on the parts with ports D to F).
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

' Makes the pin an input and waits for the start of a frame: False for a bad pin, a line stuck low (more than about 10 ms)
' or no falling edge within about 0.65 s. On True the line has just gone low.
Function Begin(ByVal pin As Byte) As Boolean
    Result = False
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.PinInput(pin)
    If Width(pin, False, 1000) > 1000 Then
        Exit
    End If
    ' the line has to be idle (high), then fall
    If Width(pin, True, 65000) > 65000 Then
        Exit
    End If
    Result = True
End Function

' Sony SIRC, 12 bit frames: a 2.4 ms burst, then 12 bits LSB first (7 command bits, 5 system bits), each a burst of
' 0.6 ms (0) or 1.2 ms (1) followed by a 0.6 ms gap. The pulse widths are judged against the width of the header,
' so the result does not depend on the exact poll time.
Public Function SonyIn(ByVal pin As Byte) As Word
    Dim header As Word
    Dim w As Word
    Dim t As Word
    Dim v As Word
    Dim i As Byte
    Result = 65535
    If Not Begin(pin) Then
        Exit
    End If
    header = Width(pin, False, 1000)
    ' 2.4 ms is 240 polls of 10 us; allow 0.6 to 1.5 times that
    If header < 140 Or header > 360 Then
        Exit
    End If
    ' 1.2 ms against 0.6 ms: the threshold is 0.9 ms, 3/8 of the 2.4 ms header (w * 8 > header * 3 is w > this)
    t = (header * 3) >> 3
    v = 0
    For i = 0 To 11
        If Width(pin, True, 200) > 200 Then
            Exit
        End If
        w = Width(pin, False, 1000)
        v = v >> 1
        If w > t Then
            v = v Or 2048
        End If
    Next
    ' v: bit 0 is the first bit received; command bits 0..6, system bits 7..11
    Result.Byte0 = Byte(v) And 127
    Result.Byte1 = (Byte(v >> 8) << 1) Or (Byte(v) >> 7)
End Function

' Philips RC5, 14 bits Manchester coded at 1.778 ms per bit: two start bits (the second is the inverse of command
' bit 6, so commands run 0..127), a toggle bit, 5 system bits and 6 command bits, most significant first. The line is
' sampled in the second half of each bit, a low level being a 1. The toggle bit is not returned. The sample points drift by
' the time of the loop (a few us at 16 MHz and above), so use a clock of 16 MHz or more.
Public Function RC5In(ByVal pin As Byte) As Word
    Dim v As Word
    Dim i As Byte
    Result = 65535
    If Not Begin(pin) Then
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
    Result.Byte0 = Byte(v) And 63
    Result.Byte1 = ((Byte(v >> 8) << 2) Or (Byte(v) >> 6)) And 31
    If (v And 4096) = 0 Then
        Result = Result Or 64
    End If
End Function
