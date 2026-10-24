Module Pwm
' Four PWM outputs on Timer2: channel 1 = CCP1 and 2 = CCP2 (CCP modules in PWM mode, chapter 22)
' and 3 = PWM3 and 4 = PWM4 (the 10-bit PWM modules, chapter 23), DS40002043F. All channels share
' the Timer2 period (the frequency); each has its own duty cycle. The module owns Timer2 while a
' channel runs: do not use `Timer` Timer2 routines or a Timer2 interrupt at the same time (the start
' waits for TMR2IF and clears it). `Clock` must be FOSC in MHz.
'
' Frequency [Equation 22-1, 23-1]: f = FOSC / (4 * prescale * (T2PR + 1)), the timer clock must be
' FOSC/4 [22.4.1, 23.3] (T2CLKCON = 1). PwmInit picks the smallest prescale (1..128) with
' T2PR + 1 <= 256 and rounds T2PR to the nearest value. The duty cycle is a number of steps of
' 1/(4 * (T2PR + 1)) of the period [Equation 23-3]: PwmSteps. The resolution is 10 bits (1024 steps)
' only when T2PR = 255; a larger frequency gives fewer steps [Equation 23-4]. A duty of 1023 steps
' in 1024 is the highest 10-bit value, so with T2PR = 255 the output cannot reach 100 %.
' For fewer steps a duty of PwmSteps or more keeps PWM3/PWM4 high [23.1]; the CCP chapter does not say.
'
' Duty cycle registers are double buffered and copied at the period match [22.4.4, 23.1]. They can
' be written at any time, but if the match falls between the two byte writes of one update, one
' period can use a mixed value.
'
' Pins: PwmStart takes a pin number 0..23 (RA0..RA7 = 0..7, RB0..RB7 = 8..15, RC0..RC7 = 16..23, as
' the Adc channels). On the 28-pin device CCP1 and CCP2 can output on ports B and C, PWM3 and
' PWM4 on ports A and C [Table 18-2]. The pin is routed through RxyPPS = 5 + channel - 1 (CCP1 5,
' CCP2 6, PWM3 7, PWM4 8) and made a digital output.
' The module is not reentrant: do not call it from a handler and from the main program.
Dim Tmr2If As PIR4.1
Dim steps As Word
Dim period As Byte
Dim ckps As Byte
Dim active As Byte
Dim freq As LongWord
Dim pins(4) As Byte
Dim polv(4) As Byte
Dim ready As Boolean

' Chooses the Timer2 prescale and T2PR for `hz` (1..1000000) and returns 1, or 0 when no prescale
' of 1..128 reaches it or a channel is running (the period is shared). Timer2 is started by PwmStart.
Public Function PwmInit(ByVal hz As LongWord) As Byte
    Dim fosc As LongWord
    Dim n As LongWord
    Dim d As LongWord
    Dim e As Byte
    Dim found As Boolean
    Result = 0
    If active <> 0 Or hz = 0 Or hz > 1000000 Then
        Exit
    End If
    fosc = LongWord(_Clock * 1000000)
    found = False
    e = 0
    While e < 8 And Not found
        d = (LongWord(4) * hz) << e
        n = (fosc + d / 2) / d
        If n >= 1 And n <= 256 Then
            found = True
        Else
            Inc(e)
        End If
    Wend
    If found Then
        ckps = e
        period = Byte(n - 1)
        steps = Word(n * 4)
        freq = fosc / ((LongWord(4) << e) * n)
        ready = True
        Result = 1
    End If
End Function

' The achieved frequency in Hz (0 before a successful PwmInit).
Public Function PwmFrequency() As LongWord
    Result = 0
    If ready Then
        Result = freq
    End If
End Function

' Number of duty cycle steps in one period: 4 * (T2PR + 1), at most 1024.
Public Function PwmSteps() As Word
    Result = 0
    If ready Then
        Result = steps
    End If
End Function

' Valid outputs: channels 1, 2 on ports B and C (pins 8..23); channels 3, 4 on ports A and C.
Function PinOk(ByVal ch As Byte, ByVal pin As Byte) As Boolean
    Result = False
    If ch = 1 Or ch = 2 Then
        If pin >= 8 And pin < 24 Then
            Result = True
        End If
    ElseIf ch = 3 Or ch = 4 Then
        If pin < 8 Or (pin >= 16 And pin < 24) Then
            Result = True
        End If
    End If
End Function

' Makes the pin an input (the output driver off) or an output.
Sub PinInput(ByVal pin As Byte, ByVal asInput As Boolean)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 8 Then
        If asInput Then
            TRISA = TRISA Or m
        Else
            TRISA = TRISA And (m Xor 255)
        End If
    ElseIf pin < 16 Then
        If asInput Then
            TRISB = TRISB Or m
        Else
            TRISB = TRISB And (m Xor 255)
        End If
    Else
        If asInput Then
            TRISC = TRISC Or m
        Else
            TRISC = TRISC And (m Xor 255)
        End If
    End If
End Sub

Sub PinDigital(ByVal pin As Byte)
    Dim m As Byte
    m = (1 << (pin And 7)) Xor 255
    If pin < 8 Then
        ANSELA = ANSELA And m
    ElseIf pin < 16 Then
        ANSELB = ANSELB And m
    Else
        ANSELC = ANSELC And m
    End If
End Sub

' RxyPPS = code for pin 0..23 (code 0 gives the pin back to its LATxy bit).
Sub SetPps(ByVal pin As Byte, ByVal code As Byte)
    If pin = 0 Then
        RA0PPS = code
    ElseIf pin = 1 Then
        RA1PPS = code
    ElseIf pin = 2 Then
        RA2PPS = code
    ElseIf pin = 3 Then
        RA3PPS = code
    ElseIf pin = 4 Then
        RA4PPS = code
    ElseIf pin = 5 Then
        RA5PPS = code
    ElseIf pin = 6 Then
        RA6PPS = code
    ElseIf pin = 7 Then
        RA7PPS = code
    ElseIf pin = 8 Then
        RB0PPS = code
    ElseIf pin = 9 Then
        RB1PPS = code
    ElseIf pin = 10 Then
        RB2PPS = code
    ElseIf pin = 11 Then
        RB3PPS = code
    ElseIf pin = 12 Then
        RB4PPS = code
    ElseIf pin = 13 Then
        RB5PPS = code
    ElseIf pin = 14 Then
        RB6PPS = code
    ElseIf pin = 15 Then
        RB7PPS = code
    ElseIf pin = 16 Then
        RC0PPS = code
    ElseIf pin = 17 Then
        RC1PPS = code
    ElseIf pin = 18 Then
        RC2PPS = code
    ElseIf pin = 19 Then
        RC3PPS = code
    ElseIf pin = 20 Then
        RC4PPS = code
    ElseIf pin = 21 Then
        RC5PPS = code
    ElseIf pin = 22 Then
        RC6PPS = code
    ElseIf pin = 23 Then
        RC7PPS = code
    End If
End Sub

' Writes the module control register: CCPxCON for channels 1, 2, PWMxCON for 3, 4.
Sub SetCon(ByVal ch As Byte, ByVal v As Byte)
    If ch = 1 Then
        CCP1CON = v
    ElseIf ch = 2 Then
        CCP2CON = v
    ElseIf ch = 3 Then
        PWM3CON = v
    Else
        PWM4CON = v
    End If
End Sub

' Duty cycle registers of a channel: the 8 most significant bits and bits 7:6 hold the 2 least
' significant bits (CCPxCON.FMT = 1, left-aligned [22.6.3]; PWMxDC [23.12.3]).
Sub SetDuty(ByVal ch As Byte, ByVal d As Word)
    Dim hi As Byte
    Dim lo As Byte
    If d > 1023 Then
        d = 1023
    End If
    hi = Byte(d >> 2)
    lo = Byte((d And 3) << 6)
    If ch = 1 Then
        CCPR1L = lo
        CCPR1H = hi
    ElseIf ch = 2 Then
        CCPR2L = lo
        CCPR2H = hi
    ElseIf ch = 3 Then
        PWM3DCL = lo
        PWM3DCH = hi
    Else
        PWM4DCL = lo
        PWM4DCH = hi
    End If
End Sub

' Stops a channel: the pin becomes an input again and returns to its LATxy bit, the module is
' disabled. Timer2 is stopped when the last channel stops.
Public Sub PwmStop(ByVal ch As Byte)
    Dim msk As Byte
    If ch >= 1 And ch <= 4 Then
        msk = 1 << (ch - 1)
        If (active And msk) <> 0 Then
            PinInput(pins(ch - 1), True)
            SetCon(ch, 0)
            SetPps(pins(ch - 1), 0)
            active = active And (msk Xor 255)
            If active = 0 Then
                T2CON = 0
            End If
        End If
    End If
End Sub

' Starts a channel (1..4) on a pin (see the header) at `duty` steps of PwmSteps, following the
' set-up order of 22.4.2 and 23.9: output driver off, routing and timer selection, duty cycle,
' Timer2 on, wait for its first overflow, then the driver on, so that the first period is complete.
' Returns 0 (and does nothing) without a successful PwmInit, for a channel or pin that cannot be
' used, or for a pin already used by another running channel; a running channel is restarted.
Public Function PwmStart(ByVal ch As Byte, ByVal pin As Byte, ByVal duty As Word) As Byte
    Dim sh As Byte
    Dim msk As Byte
    Dim c As Byte
    Result = 0
    If Not ready Or Not PinOk(ch, pin) Then
        Exit
    End If
    msk = 1 << (ch - 1)
    ' Another running channel may not use the pin.
    c = 1
    While c <= 4
        If c <> ch And (active And (1 << (c - 1))) <> 0 And pins(c - 1) = pin Then
            Exit
        End If
        Inc(c)
    Wend
    If (active And msk) <> 0 Then
        PwmStop(ch)
    End If
    pins(ch - 1) = pin
    PinInput(pin, True)
    PinDigital(pin)
    SetPps(pin, ch + 4)
    ' CCPTMRS: CnTSEL / PnTSEL = 01 selects Timer2 for PWM [22.6.4, 23.12.2].
    sh = (ch - 1) * 2
    CCPTMRS = (CCPTMRS And ((3 << sh) Xor 255)) Or (1 << sh)
    If ch <= 2 Then
        ' EN = 1, FMT = 1, MODE = 11xx (PWM) [22.6.1]
        SetCon(ch, 156)
    Else
        SetCon(ch, polv(ch - 1))
    End If
    SetDuty(ch, duty)
    If active = 0 Then
        T2CON = 0
        T2CLKCON = 1
        T2HLT = 0
        T2RST = 0
        T2PR = period
        T2TMR = 0
        Tmr2If = 0
        T2CON = 128 + ckps * 16
    Else
        Tmr2If = 0
    End If
    While Tmr2If = 0
    Wend
    Tmr2If = 0
    active = active Or msk
    PinInput(pin, False)
    If ch > 2 Then
        SetCon(ch, 128 + polv(ch - 1))
    End If
    Result = 1
End Function

' Duty cycle in steps (0..PwmSteps, at most 1023 are representable); no effect on a stopped channel.
Public Sub PwmDuty(ByVal ch As Byte, ByVal duty As Word)
    If ch >= 1 And ch <= 4 Then
        If (active And (1 << (ch - 1))) <> 0 Then
            SetDuty(ch, duty)
        End If
    End If
End Sub

' Duty cycle as a percentage 0..100 of the period (rounded down to a step; 100 gives the highest
' duty, see the header).
Public Sub PwmPercent(ByVal ch As Byte, ByVal pct As Byte)
    Dim d As LongWord
    If pct > 100 Then
        pct = 100
    End If
    d = LongWord(pct) * steps / 100
    PwmDuty(ch, Word(d))
End Sub

' Output polarity of PWM3 or PWM4 [PWMxCON.POL, 23.2]; on a running channel it applies at once.
' Returns 0 for the CCP channels 1 and 2, which have no polarity bit.
Public Function PwmInvert(ByVal ch As Byte, ByVal inverted As Boolean) As Byte
    Result = 0
    If ch = 3 Or ch = 4 Then
        If inverted Then
            polv(ch - 1) = 16
        Else
            polv(ch - 1) = 0
        End If
        If (active And (1 << (ch - 1))) <> 0 Then
            SetCon(ch, 128 + polv(ch - 1))
        End If
        Result = 1
    End If
End Function
