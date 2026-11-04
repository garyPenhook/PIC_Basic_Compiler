Module Buttons
Include "pinio"
' Counter and Button, counterparts of the Positron8 commands of the same names, on any pin numbered as in `Pinio`
' (RA0 = 0, RB0 = 8, RC0 = 16). A pin the part lacks reads as low. The pin is made an input. The module is not reentrant
' (it binds its pin once with `Pinio.BindData`, which `shift` and `pulse` share).
'
' Time is kept by polling and cycle-counted delays, as in `pulse`, so it follows `Clock` and interrupts lengthen it.

' Rising edges seen on pin in about `ms` milliseconds. The pin is looked at every 10 us plus the time of the read, so
' an edge shorter than that, and pulses faster than about 40 kHz, are missed, and the period is 10 to 40 per cent longer
' than `ms` (a longer time at a slow clock); calibrate against a known frequency when the number matters, or
' use a hardware timer (`Timer1StartGated`). A count of 65535 stops it.
Public Function Counter(ByVal pin As Byte, ByVal ms As Word) As Word
    Dim i As Byte
    Dim now As Boolean
    Dim was As Boolean
    Result = 0
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.PinInput(pin)
    was = Pinio.DataRead()
    While ms > 0
        For i = 1 To 100
            DelayUS(10)
            now = Pinio.DataRead()
            If now And Not was Then
                If Result < 65535 Then
                    Result = Result + 1
                End If
            End If
            was = now
        Next
        ms = ms - 1
    Wend
End Function

' One look at a push button on pin, which is down when it reads `down` (True = high). Call it again and again, from the
' main loop. It returns True when a press is to be acted on: at once for a new press (the pin is read again 10 ms
' later, so a bounce is ignored), and again, if `delay` is not 0 or 255, after `delay` more calls with the button held,
' then every `rate` calls (0 = every call). With `delay` 0 or 255 there is no repeat. `state` is the button's memory:
' a Byte of the caller's, one per button, that must be 0 at the start and must not be changed in between.
Public Function Button(ByVal pin As Byte, ByVal down As Boolean, ByVal delay As Byte, ByVal rate As Byte, ByRef state As Byte) As Boolean
    Result = False
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.PinInput(pin)
    If Pinio.DataRead() <> down Then
        state = 0
        Exit
    End If
    If state = 0 Then
        ' A new press: wait out the bounce.
        DelayMS(10)
        If Pinio.DataRead() <> down Then
            Exit
        End If
        Result = True
        If delay = 0 Then
            state = 255
        Else
            state = delay
        End If
    ElseIf state <> 255 Then
        state = state - 1
        If state = 0 Then
            Result = True
            If rate = 0 Then
                state = 1
            Else
                state = rate
            End If
        End If
    End If
End Function
