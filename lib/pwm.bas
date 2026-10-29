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
' PIC18F0x/1xQ41 (chosen with `#if _has(PWMEN)`, DS40002214G chapter 30): the six outputs of the three 16-bit PWM modules
' replace the four Q10 channels: channel 1 = PWM1S1P1, 2 = PWM1S1P2, 3 = PWM2S1P1, 4 = PWM2S1P2, 5 = PWM3S1P1, 6 = PWM3S1P2
' (the CCP1 PWM is not offered). The modules run left aligned from FOSC (PWMxCLK = 2) with a prescale CPRE + 1 and a
' period PR + 1 = PwmSteps clocks, 2..65535, shared by all modules: f = FOSC / ((CPRE + 1) * (PR + 1)); the duty of an
' output is its parameter register P1 / P2, the number of clocks it is active at the start of the period (more than
' PR is full), so PwmSteps steps give 100 %. Outputs go to any pin of RA0..RA5 (not RA3), RB4..RB7, RC0..RC7 through
' RxyPPS = 9 + channel [Table 21-2]. Timer2 is not used. The buffered registers are copied when the module is
' enabled and by a reload (LD) at the end of the period; a new duty is written and LD is set [30.5].
#if Not _has(PRODL)
#error "pwm: not ported to the enhanced mid-range core (PIC16F171xx) yet"
#endif

#if _has(PWMEN)
Dim steps As Word
Dim cpre As Byte
Dim prv As Word
Dim active As Byte
Dim freq As LongWord
Dim pins(6) As Byte
Dim polv(6) As Byte
Dim ready As Boolean

' Chooses the PWM clock prescale (CPRE, 1..256) and period (PR) for `hz` and returns 1, or 0 when no setting
' within 16 bits reaches it or a channel is running (the period is shared by all). Starts nothing.
Public Function PwmInit(ByVal hz As LongWord) As Byte
    Dim fosc As LongWord
    Dim n As LongWord
    Dim p As LongWord
    Result = 0
    If active <> 0 Or hz = 0 Or hz > 1000000 Then
        Exit
    End If
    fosc = LongWord(_Clock * 1000000)
    ' smallest prescale p = CPRE + 1 with fosc / (p * hz) <= 65535
    p = (fosc / hz + 65534) / 65535
    If p < 1 Then
        p = 1
    End If
    If p > 256 Then
        Exit
    End If
    n = (fosc + p * hz / 2) / (p * hz)
    If n < 2 Or n > 65535 Then
        Exit
    End If
    cpre = Byte(p - 1)
    prv = Word(n - 1)
    steps = Word(n)
    freq = fosc / (p * n)
    ready = True
    Result = 1
End Function

' The achieved frequency in Hz (0 before a successful PwmInit).
Public Function PwmFrequency() As LongWord
    Result = 0
    If ready Then
        Result = freq
    End If
End Function

' Number of duty cycle steps in one period: PR + 1 (the PWM clocks in a period).
Public Function PwmSteps() As Word
    Result = 0
    If ready Then
        Result = steps
    End If
End Function

' Pins that exist: RA0..RA5 except RA3 (input only), RB4..RB7 on the 20-pin parts, RC0..RC7.
Function PinOk(ByVal pin As Byte) As Boolean
    Result = (pin <= 5 And pin <> 3) Or (pin >= 16 And pin <= 21)
#if _has(RC6PPS)
    If pin = 22 Or pin = 23 Then
        Result = True
    End If
#endif
#if _has(TRISB)
    If pin >= 12 And pin <= 15 Then
        Result = True
    End If
#endif
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
#if _has(TRISB)
    ElseIf pin < 16 Then
        If asInput Then
            TRISB = TRISB Or m
        Else
            TRISB = TRISB And (m Xor 255)
        End If
#endif
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
#if _has(TRISB)
    ElseIf pin < 16 Then
        ANSELB = ANSELB And m
#endif
    Else
        ANSELC = ANSELC And m
    End If
End Sub

' RxyPPS = code for a pin the part has (code 0 gives the pin back to its LATxy bit).
Sub SetPps(ByVal pin As Byte, ByVal code As Byte)
    If pin = 0 Then
        RA0PPS = code
    ElseIf pin = 1 Then
        RA1PPS = code
    ElseIf pin = 2 Then
        RA2PPS = code
    ElseIf pin = 4 Then
        RA4PPS = code
    ElseIf pin = 5 Then
        RA5PPS = code
#if _has(RB4PPS)
    ElseIf pin = 12 Then
        RB4PPS = code
    ElseIf pin = 13 Then
        RB5PPS = code
    ElseIf pin = 14 Then
        RB6PPS = code
    ElseIf pin = 15 Then
        RB7PPS = code
#endif
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
#if _has(RC6PPS)
    ElseIf pin = 22 Then
        RC6PPS = code
    ElseIf pin = 23 Then
        RC7PPS = code
#endif
    End If
End Sub

' The PWM module of channel 1..6: PWM1 for channels 1, 2; PWM2 for 3, 4; PWM3 for 5, 6.
Function Inst(ByVal ch As Byte) As Byte
    Result = (ch + 1) >> 1
End Function

Sub SetCon(ByVal m As Byte, ByVal v As Byte)
    If m = 1 Then
        PWM1CON = v
    ElseIf m = 2 Then
        PWM2CON = v
    Else
        PWM3CON = v
    End If
End Sub

Function GetCon(ByVal m As Byte) As Byte
    If m = 1 Then
        Result = PWM1CON
    ElseIf m = 2 Then
        Result = PWM2CON
    Else
        Result = PWM3CON
    End If
End Function

' Waits (bounded) until a requested reload has finished: LD is cleared by hardware, and nothing may be
' written until then [30.5].
Sub WaitLoad(ByVal m As Byte)
    Dim n As Word
    n = 0
    While (GetCon(m) And 4) <> 0 And n < 60000
        Inc(n)
    Wend
End Sub

' Period, prescale and clock of module m; the slice "a" configuration (both outputs high true or low true by
' polv) is written with the module disabled [30.9.10 note].
Sub Setup(ByVal m As Byte)
    Dim cfg As Byte
    cfg = polv(m * 2 - 2) * 64 + polv(m * 2 - 1) * 128
    If m = 1 Then
        PWM1CLK = 2
        PWM1CPRE = cpre
        PWM1PR = prv
        PWM1S1CFG = cfg
    ElseIf m = 2 Then
        PWM2CLK = 2
        PWM2CPRE = cpre
        PWM2PR = prv
        PWM2S1CFG = cfg
    Else
        PWM3CLK = 2
        PWM3CPRE = cpre
        PWM3PR = prv
        PWM3S1CFG = cfg
    End If
End Sub

' Parameter register of channel ch (P1 for the odd channels, P2 for the even ones).
Sub SetDuty(ByVal ch As Byte, ByVal d As Word)
    If ch = 1 Then
        PWM1S1P1 = d
    ElseIf ch = 2 Then
        PWM1S1P2 = d
    ElseIf ch = 3 Then
        PWM2S1P1 = d
    ElseIf ch = 4 Then
        PWM2S1P2 = d
    ElseIf ch = 5 Then
        PWM3S1P1 = d
    Else
        PWM3S1P2 = d
    End If
End Sub

' Writes the duty of a channel and asks for the reload at the next period.
Sub LoadDuty(ByVal ch As Byte, ByVal d As Word)
    Dim m As Byte
    m = Inst(ch)
    If d > steps Then
        d = steps
    End If
    WaitLoad(m)
    SetDuty(ch, d)
    SetCon(m, GetCon(m) Or 4)
End Sub

' True when module m has a running channel.
Function ModuleActive(ByVal m As Byte) As Boolean
    Result = (active And (3 << (m * 2 - 2))) <> 0
End Function

' Stops a channel: the pin becomes an input again and returns to its LATxy bit. The module is disabled with its
' last channel.
Public Sub PwmStop(ByVal ch As Byte)
    Dim msk As Byte
    Dim m As Byte
    If ch >= 1 And ch <= 6 Then
        msk = 1 << (ch - 1)
        If (active And msk) <> 0 Then
            m = Inst(ch)
            PinInput(pins(ch - 1), True)
            SetPps(pins(ch - 1), 0)
            active = active And (msk Xor 255)
            If ModuleActive(m) Then
                LoadDuty(ch, 0)
            Else
                SetCon(m, 0)
            End If
        End If
    End If
End Sub

' Starts a channel (1..6: PWM1S1P1, PWM1S1P2, PWM2S1P1, PWM2S1P2, PWM3S1P1, PWM3S1P2) on a pin (see the header)
' at `duty` steps of PwmSteps. A module is set up while disabled (clock FOSC, prescale, period, left aligned mode),
' the duty and the pin routing are written, and the module is enabled, which copies the registers to the buffers
' [30.5]; a channel of a module that already runs gets its duty by the reload request. Returns 0 (and does nothing)
' without a successful PwmInit, for a channel or pin that cannot be used, or for a pin already used by another
' running channel; a running channel is restarted.
Public Function PwmStart(ByVal ch As Byte, ByVal pin As Byte, ByVal duty As Word) As Byte
    Dim msk As Byte
    Dim m As Byte
    Dim c As Byte
    Result = 0
    If Not ready Or ch < 1 Or ch > 6 Or Not PinOk(pin) Then
        Exit
    End If
    msk = 1 << (ch - 1)
    c = 1
    While c <= 6
        If c <> ch And (active And (1 << (c - 1))) <> 0 And pins(c - 1) = pin Then
            Exit
        End If
        Inc(c)
    Wend
    If (active And msk) <> 0 Then
        PwmStop(ch)
    End If
    m = Inst(ch)
    pins(ch - 1) = pin
    PinInput(pin, True)
    PinDigital(pin)
    If ModuleActive(m) Then
        LoadDuty(ch, duty)
    Else
        SetCon(m, 0)
        Setup(m)
        SetDuty(m * 2 - 1, 0)
        SetDuty(m * 2, 0)
        If duty > steps Then
            duty = steps
        End If
        SetDuty(ch, duty)
        SetCon(m, 128)
    End If
    SetPps(pin, ch + 9)
    PinInput(pin, False)
    active = active Or msk
    Result = 1
End Function

' Duty cycle in steps (0..PwmSteps); no effect on a stopped channel. It takes effect at the next period.
Public Sub PwmDuty(ByVal ch As Byte, ByVal duty As Word)
    If ch >= 1 And ch <= 6 Then
        If (active And (1 << (ch - 1))) <> 0 Then
            LoadDuty(ch, duty)
        End If
    End If
End Sub

' Duty cycle as a percentage 0..100 of the period (rounded down to a step).
Public Sub PwmPercent(ByVal ch As Byte, ByVal pct As Byte)
    Dim d As LongWord
    If pct > 100 Then
        pct = 100
    End If
    d = LongWord(pct) * steps / 100
    PwmDuty(ch, Word(d))
End Sub

' Output polarity (POL1 / POL2 of the slice configuration): inverted = low true. The configuration may only be
' written with the module disabled [30.9.10], so on a running module this restarts it: both outputs of the module
' stop for a moment and its period begins again. Always returns 1.
Public Function PwmInvert(ByVal ch As Byte, ByVal inverted As Boolean) As Byte
    Dim m As Byte
    Result = 1
    If ch < 1 Or ch > 6 Then
        Result = 0
        Exit
    End If
    If inverted Then
        polv(ch - 1) = 1
    Else
        polv(ch - 1) = 0
    End If
    m = Inst(ch)
    If ModuleActive(m) Then
        SetCon(m, 0)
        Setup(m)
        SetCon(m, 128)
    End If
End Function
#else
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
#endif
