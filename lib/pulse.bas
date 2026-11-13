Module Pulse
Include "pinio"
' Bit-banged pulse measurement and generation on any pin: PulseIn, PulseOut, RCin, Pot, Servo, PwmPin, Sound,
' Sound2. Pins are numbered 0..23 as in `Pinio` (RA0 = 0, RB0 = 8, RC0 = 16). A pin the part lacks, or a
' zero count, stops a routine at once (a measurement returns 0).
'
' Time is kept by polling and cycle-counted delays, so it follows `Clock`. One "unit" of PulseIn, PulseOut and
' RCin is one poll of 10 us plus the time of the pin read and the loop (a few us at 64 MHz, more on a slow clock),
' so a unit is 10 to 14 us at 16 MHz and above and the results are not exact: calibrate against a known pulse
' when the number matters, or use a hardware timer (`Timer1StartGated`, `Timer1StartPulse`). Interrupts
' lengthen every time here. Each routine binds its pin(s) once (`Pinio.BindData` / `BindClk`), so the bound state is shared
' with `shift` and the module is not reentrant.

' Delay of us microseconds, in steps of 100, 10 and 1 us so the loop overhead is small against the total.
Public Sub WaitUs(ByVal us As Word)
    While us >= 100
        DelayUS(100)
        us = us - 100
    Wend
    While us >= 10
        DelayUS(10)
        us = us - 10
    Wend
    While us > 0
        DelayUS(1)
        us = us - 1
    Wend
End Sub

' Half period, in 10 us ticks, of f Hz (50000 / f, at most 255); 0 below 197 Hz, which is silent.
Private Function HalfTicks(ByVal f As Word) As Byte
    Result = 0
    If f >= 197 Then
        Result = Byte(50000 / f)
        If Result = 0 Then
            Result = 1
        End If
    End If
End Function

' Two square waves from one 10 us time base for `ms` milliseconds: f1 on the data pin and f2 on the clock pin, or with `mix` both
' exclusive-or'ed on the data pin.
Private Sub TwoTone(ByVal ms As Word, ByVal f1 As Word, ByVal f2 As Word, ByVal mix As Boolean)
    Dim h1 As Byte
    Dim h2 As Byte
    Dim c1 As Byte
    Dim c2 As Byte
    Dim l1 As Boolean
    Dim l2 As Boolean
    Dim ticks As LongWord
    h1 = HalfTicks(f1)
    h2 = HalfTicks(f2)
    c1 = 0
    c2 = 0
    l1 = False
    l2 = False
    ticks = ms
    ticks = ticks * 100
    While ticks > 0
        DelayUS(10)
        If h1 > 0 Then
            c1 = c1 + 1
            If c1 >= h1 Then
                c1 = 0
                l1 = Not l1
                Pinio.DataPut(l1 Xor (mix And l2))
            End If
        End If
        If h2 > 0 Then
            c2 = c2 + 1
            If c2 >= h2 Then
                c2 = 0
                l2 = Not l2
                If mix Then
                    Pinio.DataPut(l1 Xor l2)
                Else
                    Pinio.ClkPut(l2)
                End If
            End If
        End If
        ticks = ticks - 1
    Wend
    Pinio.DataPut(False)
End Sub

' Pulse of `period` units on pin, ending at the opposite of `level` (True = a high pulse). The pin is made an output.
Public Sub PulseOut(ByVal pin As Byte, ByVal period As Word, ByVal level As Boolean)
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.DataPut(level)
    Pinio.PinOutput(pin)
    While period > 0
        DelayUS(10)
        period = period - 1
    Wend
    Pinio.DataPut(Not level)
End Sub

' Pulse of `period` units that is the opposite of the level the pin has now (two toggles).
Public Sub PulseOut(ByVal pin As Byte, ByVal period As Word)
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    PulseOut(pin, period, Not Pinio.DataRead())
End Sub

' Width, in units, of the next pulse at `level` on pin. The pin is made an input. The clock starts at the edge into
' `level` (a pin already at `level` has to leave it first); 0 when no complete pulse comes in 65535 units
' (a wait of about 0.65 s for each of the three phases).
Public Function PulseIn(ByVal pin As Byte, ByVal level As Boolean) As Word
    Dim n As Word
    Dim phase As Byte
    Result = 0
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.PinInput(pin)
    ' phase 0 waits out a pin already at `level`, phase 1 waits for it, phase 2 measures it
    For phase = 0 To 2
        n = 0
        While Pinio.DataRead() = (level Xor (phase = 1))
            DelayUS(10)
            n = n + 1
            If n = 0 Then
                Exit
            End If
        Wend
    Next
    Result = n
End Function

' Time, in units, that pin stays at `level`: 1 when it is not at `level` at the call, 0 when it stays there for
' 65535 units. Used to time an R-C network: charge or discharge the capacitor first. The pin is left an input.
Public Function RCin(ByVal pin As Byte, ByVal level As Boolean) As Word
    Dim n As Word
    Result = 0
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.PinInput(pin)
    n = 1
    While Pinio.DataRead() = level
        DelayUS(10)
        n = n + 1
        If n = 0 Then
            Exit
        End If
    Wend
    Result = n
End Function

' Reads a variable resistor (with a capacitor to ground on the pin): the capacitor is discharged for about 1 ms,
' then the time for the pin to rise to a high level is measured with `RCin` and scaled: the result is
' (units * scale) / 256, at most 255. Find `scale` by reading once with scale = 255 at the largest resistance.
Public Function Pot(ByVal pin As Byte, ByVal scale As Byte) As Byte
    Dim t As Word
    Dim h As Word
    Result = 0
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.DataPut(False)
    Pinio.PinOutput(pin)
    DelayMS(1)
    t = RCin(pin, False)
    ' (t * scale) >> 8 from the two bytes of t, so no 32-bit product
    h = (t >> 8) * scale + (((t And 255) * scale) >> 8)
    If h > 255 Then
        h = 255
    End If
    Result = Byte(h)
End Function

' One servo pulse: pin high for `width` microseconds (500..2500, 1500 is centre), then low. The pin is made an
' output. Call it about every 20 ms with a `DelayMS`, as the servo needs a stream of pulses to hold a position.
Public Sub Servo(ByVal pin As Byte, ByVal width As Word)
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.DataPut(False)
    Pinio.PinOutput(pin)
    Pinio.DataPut(True)
    WaitUs(width)
    Pinio.DataPut(False)
End Sub

' Pulse-width modulation by software, for an R-C filter: `cycles` periods of 256 steps of 10 us, high for `duty`
' steps in each (duty 0 is low all the time, 255 high all the time). The pin is an output while it runs and an
' input afterwards. The analogue level at the capacitor is duty / 255 of the supply.
Public Sub PwmPin(ByVal pin As Byte, ByVal duty As Byte, ByVal cycles As Byte)
    Dim i As Byte
    Dim c As Byte
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.PinOutput(pin)
    For c = 1 To cycles
        If duty > 0 Then
            Pinio.DataPut(True)
            For i = 1 To duty
                DelayUS(10)
            Next
        End If
        If duty < 255 Then
            Pinio.DataPut(False)
            For i = duty To 254
                DelayUS(10)
            Next
        End If
    Next
    Pinio.PinInput(pin)
End Sub

' Tone or noise on pin for `duration` * 10 ms. note 0 is silence, 1..127 a tone of about 78.74 * note Hz (note 1
' about 79 Hz, note 127 about 10 kHz), 128..255 noise at the pitch of note - 127. The pin is made an output.
Public Sub Sound(ByVal pin As Byte, ByVal note As Byte, ByVal duration As Byte)
    Dim half As Word
    Dim count As LongWord
    Dim lfsr As Word
    Dim n As Byte
    Dim level As Boolean
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.DataPut(False)
    Pinio.PinOutput(pin)
    If note = 0 Then
        For n = 1 To duration
            DelayMS(10)
        Next
        Exit
    End If
    n = note And 127
    If note >= 128 Then
        n = note - 127
    End If
    ' half period in us = 1e6 / (2 * 78.74 * n); half periods in the duration = duration * 10 ms / half period
    half = 6350 / n
    count = duration
    count = (count * n * 63) / 40
    lfsr = 1
    level = False
    While count > 0
        If note >= 128 Then
            ' 16-bit Galois LFSR, taps 16, 14, 13, 11: a new random level for each half period
            level = (lfsr And 1) <> 0
            lfsr = lfsr >> 1
            If level Then
                lfsr = lfsr Xor 46080
            End If
        Else
            level = Not level
        End If
        Pinio.DataPut(level)
        WaitUs(half)
        count = count - 1
    Wend
    Pinio.DataPut(False)
End Sub

' Two tones at once, f1 on pin1 and f2 on pin2, for `ms` milliseconds (frequencies 0..16000 Hz, 0 is silent).
' The two pins are driven from one 10 us time base, so the frequencies are rounded to a multiple of 10 us
' half periods and are exact only to about 10 %.
Public Sub Sound2(ByVal pin1 As Byte, ByVal pin2 As Byte, ByVal f1 As Word, ByVal f2 As Word, ByVal ms As Word)
    If Not (Pinio.PinOk(pin1) And Pinio.PinOk(pin2)) Or pin1 = pin2 Then
        Exit
    End If
    Pinio.BindClk(pin2)
    Pinio.ClkPut(False)
    Pinio.PinOutput(pin2)
    Pinio.BindData(pin1)
    Pinio.DataPut(False)
    Pinio.PinOutput(pin1)
    TwoTone(ms, f1, f2, False)
    Pinio.ClkPut(False)
End Sub

' Square wave of f Hz on pin for `ms` milliseconds (8..32767 Hz; a lower or higher frequency or a zero time is silence, the pin is
' still made an output and ends low). The half period is a whole number of microseconds, so the pitch is exact to
' about 1 us per half period plus the loop time (a few us), which matters above a few kHz.
Public Sub Freqout(ByVal pin As Byte, ByVal ms As Word, ByVal f As Word)
    Dim count As LongWord
    Dim half As Word
    Dim level As Boolean
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.DataPut(False)
    Pinio.PinOutput(pin)
    If f < 8 Or f > 32767 Then
        Exit
    End If
    half = Word(500000 / f)
    count = f
    count = (count * ms) / 500
    level = False
    While count > 0
        level = Not level
        Pinio.DataPut(level)
        WaitUs(half)
        count = count - 1
    Wend
    Pinio.DataPut(False)
End Sub

' Two square waves, f1 and f2 Hz, added (exclusive-or) on one pin for `ms` milliseconds. Both run from one 10 us
' time base like `Sound2`: frequencies 197..32767 Hz are rounded to a whole number of 10 us half periods (exact only
' to about 10 %); a frequency below 197 Hz or 0 is silent.
Public Sub Freqout(ByVal pin As Byte, ByVal ms As Word, ByVal f1 As Word, ByVal f2 As Word)
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    Pinio.BindData(pin)
    Pinio.DataPut(False)
    Pinio.PinOutput(pin)
    TwoTone(ms, f1, f2, True)
End Sub
