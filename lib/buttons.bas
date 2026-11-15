Module Buttons
Include "pinio"
' Counter and Button, counterparts of the classic commands of the same names, on any pin numbered as in `Pinio`
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
    ' The state is worked on in `s` and written back once: `state` is reached through a pointer.
    Dim s As Byte
    Result = False
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.PinInput(pin)
    s = 0
    If Pinio.DataRead() = down Then
        s = state
        If s = 0 Then
            ' A new press: wait out the bounce (a bounce leaves the state 0).
            DelayMS(10)
            If Pinio.DataRead() = down Then
                Result = True
                s = delay
                If s = 0 Then
                    s = 255
                End If
            End If
        ElseIf s <> 255 Then
            s = s - 1
            If s = 0 Then
                Result = True
                s = rate
                If s = 0 Then
                    s = 1
                End If
            End If
        End If
    End If
    state = s
End Function

' Button without the wait: a non-blocking push button on pin, down when it reads `down` (True = high). Call it again
' and again, from the main loop, at a steady rate. A new press counts once `settle` calls in a row have found the button
' down (0 or 1 = the first one), so a bounce shorter than `settle` calls is ignored; then it returns True, and again, if
' `delay` is not 0 or 255, after `delay` more calls with the button held, then every `rate` calls (0 = every call). Any
' call that finds the button up starts over. `state` is the button's memory: a Word of the caller's, one per button, that
' must be 0 at the start and must not be changed in between (its low byte counts the repeat, its high byte the settle).
Public Function ButtonPoll(ByVal pin As Byte, ByVal down As Boolean, ByVal settle As Byte, ByVal delay As Byte, ByVal rate As Byte, ByRef state As Word) As Boolean
    ' The state is worked on in `s` and written back once: `state` is reached through a pointer.
    Dim s As Word
    Dim r As s.Byte0
    Dim n As s.Byte1
    Result = False
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.PinInput(pin)
    s = 0
    If Pinio.DataRead() = down Then
        s = state
        If r = 0 Then
            ' Settling: count the calls that found it down.
            n = n + 1
            If n >= settle Then
                Result = True
                n = 0
                r = delay
                If r = 0 Then
                    r = 255
                End If
            End If
        ElseIf r <> 255 Then
            r = r - 1
            If r = 0 Then
                Result = True
                r = rate
                If r = 0 Then
                    r = 1
                End If
            End If
        End If
    End If
    state = s
End Function
