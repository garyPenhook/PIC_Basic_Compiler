Module Pwm
Include "pinio"
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
' The pin is made a digital input, then an output, and given back as an input, by the `Pinio` module (`Include "pinio"` above).
' Which channels run is kept in `pins`: a running channel holds its pin number plus one, an idle channel 0 (so no bit masks are shifted at run time).
' PIC18F0x/1xQ41 (chosen with `#if _has(PWMEN)`, DS40002214G chapter 30): the six outputs of the three 16-bit PWM modules
' replace the four Q10 channels: channel 1 = PWM1S1P1, 2 = PWM1S1P2, 3 = PWM2S1P1, 4 = PWM2S1P2, 5 = PWM3S1P1, 6 = PWM3S1P2
' (the CCP1 PWM is not offered). The modules run left aligned from FOSC (PWMxCLK = 2) with a prescale CPRE + 1 and a
' period PR + 1 = PwmSteps clocks, 2..65535, shared by all modules: f = FOSC / ((CPRE + 1) * (PR + 1)); the duty of an
' output is its parameter register P1 / P2, the number of clocks it is active at the start of the period (more than
' PR is full), so PwmSteps steps give 100 %. Outputs go to any pin of RA0..RA5 (not RA3), RB4..RB7, RC0..RC7 through
' RxyPPS = 9 + channel [Table 21-2]. Timer2 is not used. The buffered registers are copied when the module is
' enabled and by a reload (LD) at the end of the period; a new duty is written and LD is set [30.5].
' PIC16F13145 family (DS40002519D chapters 24 to 27; chosen with `#if _has(PWM1DCL)` in the Timer2 branch below): the Q10 design with CCP1 and CCP2
' (channels 1, 2) and the two 10-bit PWM modules PWM1 and PWM2 (channels 3, 4) on Timer2, one shared period. RxyPPS = 09h CCP1, 0Ah CCP2, 2Ch PWM1,
' 2Dh PWM2 [Table 18-2 p.187-188]; any pin of the part. Timer2 flag is TMR2IF = PIR2 bit 2. CCPxCON = EN | FMT | MODE 11xx and PWMxCON are as on the Q10;
' CCPTMRS0 and PWMTMRS0 reset to Timer2, so the module leaves them alone.
' PIC16F17126/46 (DS40002343F chapter 29): the same 16-bit PWM modules as the Q41 but two of them, so channels 1..4 (PWM1S1P1, PWM1S1P2, PWM2S1P1,
' PWM2S1P2) with RxyPPS = 10 + channel [Table 18-2: PWM1S1P1_OUT = 0Bh]; channels 5 and 6 are refused. Pins as on the Q41.
' PIC16F13214/15/24/25/44/45 (DS40002686B chapter 27; chosen with `#if _has(PWMEN)` like the PIC16F17126/46): the same two 16-bit PWM modules, so channels 1..4 with RxyPPS = 10 + channel
' [Table 18-2 p.207: PWM1S1P1_OUT = 0Bh .. PWM2S1P2_OUT = 0Eh]; PWMxCLK = 2 is FOSC, CPRE is n + 1, EN is PWMxCON bit 7 and LD bit 2, MODE 000 is left aligned [p.325-336]. Pins: any pin of the part
' (RA0..RA5 except RA3, RB4..RB7 on the 20-pin parts, RC0..RC5 on the 14- and 20-pin parts, RC6 and RC7 on the 20-pin parts).
' PIC16F183xx (DS40001799F, DS40001800E, DS40001795K, DS40001839E, chapters 18 and 29; chosen with `_has(PWM6DCL)` in the Timer2 branch below): the same four channels on Timer2 as the PIC16F13145
' family: channels 1 and 2 are CCP1 and CCP2 in PWM mode and channels 3 and 4 are the 10-bit modules PWM5 and PWM6 (CCP3, CCP4 and the other timers are not offered). RxyPPS = 0Ch CCP1, 0Dh CCP2,
' 02h PWM5, 03h PWM6 [Register 13-2]; any pin of the part. Timer2 is the old one: PR2, TMR2, T2CON = TMR2ON | T2CKPS with prescalers 1, 4, 16, 64 [Register 28-1] and no clock register (FOSC/4 only), so
' f = FOSC / (4 * prescale * (PR2 + 1)) [Equation 18-1, 29-1] and the duty steps are 1 / (4 * (PR2 + 1)) of the period [Equation 18-3]; PwmInit therefore tries the prescalers 1, 4, 16, 64.
' The flag is TMR2IF = PIR1 bit 1. CCPxCON = EN | FMT | MODE 11xx (156) and PWMxCON = EN | POL as before. CCPTMRS and PWMTMRS reset to 01 = Timer2 [Registers 29-5, 18-4]; they are written to
' 01 anyway where the part has them (not the 8- and 14-pin PIC16F18313/18323). The errata of the latest silicon show nothing for CCP or PWM.
' PIC16F152xx (DS40002195E chapters 22 and 23; chosen with `_has(PWM3CON) And _has(PIR1.TMR2IF)`): the Q10 channels and registers (channels 1 and 2 are CCP1 and CCP2, 3 and 4 are PWM3 and PWM4,
' Timer2 with T2CLKCON, T2PR and prescalers 1..128, CCPxCON and PWMxCON as above) with the PPS routing of the PIC16F13145 family: any pin of the part, RxyPPS = 01h CCP1, 02h CCP2, 03h PWM3, 04h PWM4
' [Table 18-2 p.148]. The Timer2 flag is TMR2IF = PIR1 bit 6 [12.9.6]; there is no CCPTMRS or PWMTMRS (CCP PWM and PWM3/4 always use Timer2, Table 22-1).
' PIC16F18056/76 (DS40002325C chapters 24 to 27; chosen with `_has(PWM5CON) And Not _has(PWM6CON)`): the Q10 channels and registers (channels 1 and 2 are CCP1 and CCP2, 3 and 4 are PWM3 and PWM4 (PWM5 is not offered),
' Timer2 with T2CLKCON, T2PR and prescalers 1..128, CCPxCON = EN | FMT | MODE 11xx (156) and PWMxCON = EN | POL [24.5.1 p.268, 26.11.1 p.280]). RxyPPS = 09h CCP1, 0Ah CCP2, 0Bh PWM3, 0Ch PWM4 [Table 18-2 p.170], so the
' code is 8 + channel. PPS offers CCP1 and CCP2 on port B or C on both parts, and PWM3 and PWM4 on port B and C on the 28-pin part but on port B and D on the 40-pin part [Table 18-2], so the pins accepted are RB0..RB7 and
' RC0..RC7 (pins 8..23) for channels 1 and 2 and RB0..RB7 for channels 3 and 4, plus RC0..RC7 where the part has no port D. The Timer2 flag is TMR2IF = PIR1 bit 7. CCPTMRS0 and PWMTMRS0 reset to Timer2
' [25.1.1, 27.1.1 p.273, 284], so they are left alone. The silicon errata (DS80001014D) show nothing for CCP or PWM. RB6 and RB7 are also the ICSP clock and data pins.
#if _has(PWMEN)
' Output channels: three modules of two on the PIC18-Q41, two modules of two on the PIC16F171xx.
#if _has(PWM3CON)
Const Channels = 6
Const PpsBase = 9
#else
Const Channels = 4
Const PpsBase = 10
#endif
Dim steps As Word
Dim cpre As Byte
Dim prv As Word
' A running channel has its pin number plus one in pins, an idle one 0; nact counts the running channels.
Dim nact As Byte
Dim freq As LongWord
Dim pins(Channels) As Byte
Dim polv(Channels) As Byte
Dim ready As Boolean

' Chooses the PWM clock prescale (CPRE, 1..256) and period (PR) for `hz` and returns 1, or 0 when no setting
' within 16 bits reaches it or a channel is running (the period is shared by all). Starts nothing.
' With q = floor(2 * fosc / hz) (one divide): floor(fosc / hz) = q >> 1 and the period count rounded to nearest,
' floor((fosc + p * hz / 2) / (p * hz)), is floor((q + p) / (2 * p)) (p * hz / 2 is only odd where the two agree).
Public Function PwmInit(ByVal hz As LongWord) As Byte
    Dim q As LongWord
    Dim hi As Word
    Dim p As Word
    Dim n As LongWord
    Result = 0
    If nact <> 0 Or hz = 0 Or hz > 1000000 Then
        Exit
    End If
    q = LongWord(_Clock * 1000000 * 2) / hz
    ' p = ceil(floor(fosc / hz) / 65535) = a + 1, plus one when the low 16 bits b of floor(fosc / hz) = 65536 * a + b are above 65535 - a.
    n = q >> 1
    hi = Word(n >> 16)
    p = hi + 1
    If Word(n) > 65535 - hi Then
        Inc(p)
    End If
    If p > 256 Then
        Exit
    End If
    n = (q + p) / (LongWord(p) << 1)
    If n < 2 Or n > 65535 Then
        Exit
    End If
    cpre = Byte(p - 1)
    prv = Word(n - 1)
    steps = Word(n)
    freq = LongWord(_Clock * 1000000) / (LongWord(p) * n)
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

' Pins that exist: RA0..RA5 except RA3 (input only), RB4..RB7 on the 20-pin parts, RC0..RC5 where there is a port C (not the 8-pin PIC16F13214/15), RC6 and RC7 on the 20-pin parts.
Function PinOk(ByVal pin As Byte) As Boolean
    Result = (pin <= 5 And pin <> 3)
#if _has(TRISC)
    If pin >= 16 And pin <= 21 Then
        Result = True
    End If
#endif
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

' RxyPPS = code for a pin the part has (code 0 gives the pin back to its LATxy bit).
#if _has(PRODL)
' The RxyPPS registers are contiguous from RA0PPS in the order of the pin numbers (RA0..RC7 = 0..23) on the PIC18-Q41
' [DS40002214G register summary: RA0PPS 0x0201 .. RC7PPS 0x0218] and the PIC18F27Q10 [DS40002043F: 0x0EE2 .. 0x0EF9], so one write
' through FSR2 replaces a chain of one comparison per pin. Callers pass a pin PinOk accepted. FSR2 is saved and put back
' (it is the stack pointer under the reentrant software stack); the Asm block names the parameters and save bytes so the
' compiler keeps them.
Sub SetPps(ByVal pin As Byte, ByVal code As Byte)
    Dim sl As Byte
    Dim sh As Byte
    sl = 0
    sh = 0
    Asm
        movff FSR2L, PWM_SETPPS__SL
        movff FSR2H, PWM_SETPPS__SH
        lfsr 2, RA0PPS
        movf PWM_SETPPS__PIN, w, c
        addwf FSR2L, f, c
        movf PWM_SETPPS__CODE, w, c
        movwf INDF2, c
        movff PWM_SETPPS__SL, FSR2L
        movff PWM_SETPPS__SH, FSR2H
    End Asm
End Sub
#else
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
#if _has(RC0PPS)
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
#endif
#if _has(RC6PPS)
    ElseIf pin = 22 Then
        RC6PPS = code
    ElseIf pin = 23 Then
        RC7PPS = code
#endif
    End If
End Sub
#endif

' The PWM module of channel 1..6: PWM1 for channels 1, 2; PWM2 for 3, 4; PWM3 for 5, 6.
Function Inst(ByVal ch As Byte) As Byte
    Result = (ch + 1) >> 1
End Function

Sub SetCon(ByVal m As Byte, ByVal v As Byte)
    If m = 1 Then
        PWM1CON = v
#if _has(PWM3CON)
    ElseIf m = 2 Then
        PWM2CON = v
    Else
        PWM3CON = v
#else
    Else
        PWM2CON = v
#endif
    End If
End Sub

Function GetCon(ByVal m As Byte) As Byte
    If m = 1 Then
        Result = PWM1CON
#if _has(PWM3CON)
    ElseIf m = 2 Then
        Result = PWM2CON
    Else
        Result = PWM3CON
#else
    Else
        Result = PWM2CON
#endif
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
#if _has(PWM3CON)
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
#else
    Else
        PWM2CLK = 2
        PWM2CPRE = cpre
        PWM2PR = prv
        PWM2S1CFG = cfg
#endif
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
#if _has(PWM3CON)
    ElseIf ch = 4 Then
        PWM2S1P2 = d
    ElseIf ch = 5 Then
        PWM3S1P1 = d
    Else
        PWM3S1P2 = d
#else
    Else
        PWM2S1P2 = d
#endif
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
    Dim i As Byte
    i = m * 2 - 2
    Result = (pins(i) Or pins(i + 1)) <> 0
End Function

' Stops a channel: the pin becomes an input again and returns to its LATxy bit. The module is disabled with its
' last channel.
Public Sub PwmStop(ByVal ch As Byte)
    Dim m As Byte
    If ch >= 1 And ch <= Channels Then
        If pins(ch - 1) <> 0 Then
            m = Inst(ch)
            Pinio.PinInput(pins(ch - 1) - 1)
            SetPps(pins(ch - 1) - 1, 0)
            pins(ch - 1) = 0
            Dec(nact)
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
    Dim m As Byte
    Dim c As Byte
    Result = 0
    If Not ready Or ch < 1 Or ch > Channels Or Not PinOk(pin) Then
        Exit
    End If
    c = Channels
    While c > 0
        If c <> ch And pins(c - 1) = pin + 1 Then
            Exit
        End If
        Dec(c)
    Wend
    If pins(ch - 1) <> 0 Then
        PwmStop(ch)
    End If
    m = Inst(ch)
    Pinio.PinInput(pin)
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
    SetPps(pin, ch + PpsBase)
    Pinio.PinOutput(pin)
    pins(ch - 1) = pin + 1
    Inc(nact)
    Result = 1
End Function

' Duty cycle in steps (0..PwmSteps); no effect on a stopped channel. It takes effect at the next period.
Public Sub PwmDuty(ByVal ch As Byte, ByVal duty As Word)
    If ch >= 1 And ch <= Channels Then
        If pins(ch - 1) <> 0 Then
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
    If ch < 1 Or ch > Channels Then
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
#if _has(PWM6DCL) And Not (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))
Dim Tmr2If As PIR1.1
#elseif _has(PWM1DCL)
Dim Tmr2If As PIR2.2
#elseif _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)
Dim Tmr2If As PIR4.1
#elseif _has(PWM5CON)
Dim Tmr2If As PIR1.7
#elseif (_has(PWM3CON) And _has(PIR1.TMR2IF))
Dim Tmr2If As PIR1.6
#else
Dim Tmr2If As PIR4.1
#endif
Dim steps As Word
Dim period As Byte
Dim ckps As Byte
' A running channel has its pin number plus one in pins, an idle one 0; nact counts the running channels.
Dim nact As Byte
Dim freq As LongWord
Dim pins(4) As Byte
Dim polv(4) As Byte
Dim ready As Boolean

' Chooses the Timer2 prescale and T2PR for `hz` (1..1000000) and returns 1, or 0 when no prescale
' of 1..128 (1, 4, 16, 64 on the PIC16F183xx) reaches it or a channel is running (the period is shared). Timer2 is started by PwmStart.
' The period count n = round(FOSC / (4 * hz * prescale)) is floor((t + 1) / 2) with t = floor(FOSC / (2 * hz * prescale)), and t for the
' next prescale is t shifted right (floor of a floor): one divide for all of them.
Public Function PwmInit(ByVal hz As LongWord) As Byte
    Dim t As LongWord
    Dim n As Word
    Dim e As Byte
    Result = 0
    If nact <> 0 Or hz = 0 Or hz > 1000000 Then
        Exit
    End If
    t = LongWord(_Clock * 1000000) / (hz << 1)
    e = 0
    ' n = (t + 1) >> 1 is at most 256 for t <= 512; a larger t takes the next prescale
#if _has(PWM6DCL) And Not (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))
    ' Prescalers 1, 4, 16, 64: the prescale is 4 ^ e, the T2CKPS code.
    While t > 512 And e < 3
        t = t >> 2
#else
    While t > 512 And e < 7
        t = t >> 1
#endif
        Inc(e)
    Wend
    If t >= 1 And t <= 512 Then
        ckps = e
        n = (Word(t) + 1) >> 1
        period = Byte(n - 1)
        steps = n << 2
#if _has(PWM6DCL) And Not (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))
        freq = LongWord(_Clock * 1000000) / (LongWord(n) << (e * 2 + 2))
#else
        freq = LongWord(_Clock * 1000000) / (LongWord(n) << (e + 2))
#endif
        ready = True
        Result = 1
    End If
End Function

' The achieved frequency in Hz (0 before a successful PwmInit): FOSC / (prescale * steps).
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
' PIC16F13145 family: any pin of the part (PPS has no port restriction [Table 18-2]): RA0..RA2, RA4, RA5, RB4..RB7 (20-pin parts), RC0..RC7
' (RC6, RC7 on the 20-pin parts; port C is missing on the 8-pin part).
#if _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)
' PIC16F153xx (DS40001866E Tables 15-5 to 15-7 p.241-243, DS40001853E Table 15-3 p.200, DS40001889E p.199, DS40001865F p.200, DS40001897C p.190): on the 8- to 20-pin parts every output reaches every pin of the part; on the 28-pin and larger
' parts each reaches two ports only. Bit 0 of the masks is port A .. bit 5 port F. CCP1 and CCP2: ports B and C (28- and 40-pin parts), C and F (the PIC16(L)F15385/86); PWM3 and PWM4: B and C (28-pin), B and D (40- to 48-pin).
#if _has(RF0PPS)
Const PortsCcp As Byte = 36
Const PortsPwm As Byte = 10
#elseif _has(RD0PPS)
Const PortsCcp As Byte = 6
Const PortsPwm As Byte = 10
#elseif _has(RB0PPS)
Const PortsCcp As Byte = 6
Const PortsPwm As Byte = 6
#else
Const PortsCcp As Byte = 63
Const PortsPwm As Byte = 63
#endif
' The pins each port has as outputs (RA3 and RE3 are input only).
#if _has(RA6PPS)
Const ExA As Byte = 247
#else
Const ExA As Byte = 55
#endif
#if _has(RB0PPS)
Const ExB As Byte = 255
#elseif _has(RB4PPS)
Const ExB As Byte = 240
#else
Const ExB As Byte = 0
#endif
#if _has(RC6PPS)
Const ExC As Byte = 255
#elseif _has(RC0PPS)
Const ExC As Byte = 63
#else
Const ExC As Byte = 0
#endif
#if _has(RD0PPS)
Const ExD As Byte = 255
#else
Const ExD As Byte = 0
#endif
#if _has(RE0PPS)
Const ExE As Byte = 7
#else
Const ExE As Byte = 0
#endif
#if _has(RF0PPS)
Const ExF As Byte = 255
#else
Const ExF As Byte = 0
#endif
#endif
Function PinOk(ByVal ch As Byte, ByVal pin As Byte) As Boolean
#if _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)
    Dim port As Byte
    Dim ex As Byte
    Dim ok As Byte
#endif
    Result = False
#if _has(PWM5CON) And Not _has(PWM6CON)
    ' PIC16F18056/76: port B or C for the CCP channels, port B (and C without port D) for the PWM channels (see the top).
    If ch = 1 Or ch = 2 Then
        If pin >= 8 And pin < 24 Then
            Result = True
        End If
    ElseIf ch = 3 Or ch = 4 Then
        If pin >= 8 And pin < 16 Then
            Result = True
        End If
#if Not _has(TRISD)
        If pin >= 16 And pin < 24 Then
            Result = True
        End If
#endif
    End If
#elseif _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)
    ' PIC16F153xx: the ports the signal reaches (PortsCcp, PortsPwm) and the pins the part has (ExA .. ExF), see the top.
    If ch >= 1 And ch <= 4 And pin < 48 Then
        port = pin >> 3
        ex = 0
        If port = 0 Then
            ex = ExA
        ElseIf port = 1 Then
            ex = ExB
        ElseIf port = 2 Then
            ex = ExC
        ElseIf port = 3 Then
            ex = ExD
        ElseIf port = 4 Then
            ex = ExE
        Else
            ex = ExF
        End If
        ok = PortsPwm
        If ch <= 2 Then
            ok = PortsCcp
        End If
        If ((ok >> port) And 1) = 1 And ((ex >> (pin And 7)) And 1) = 1 Then
            Result = True
        End If
    End If
#elseif _has(PWM1DCL) Or (_has(PWM6DCL) And Not (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))) Or (_has(PWM3CON) And _has(PIR1.TMR2IF))
    If ch >= 1 And ch <= 4 Then
        Result = pin <= 5 And pin <> 3
#if _has(RB4PPS)
        If pin >= 12 And pin <= 15 Then
            Result = True
        End If
#endif
#if _has(RC0PPS)
        If pin >= 16 And pin <= 21 Then
            Result = True
        End If
#endif
#if _has(RC6PPS)
        If pin = 22 Or pin = 23 Then
            Result = True
        End If
#endif
    End If
#else
    If ch = 1 Or ch = 2 Then
        If pin >= 8 And pin < 24 Then
            Result = True
        End If
    ElseIf ch = 3 Or ch = 4 Then
        If pin < 8 Or (pin >= 16 And pin < 24) Then
            Result = True
        End If
    End If
#endif
End Function

' RxyPPS = code for pin 0..23 (code 0 gives the pin back to its LATxy bit).
#if _has(PWM5CON) And Not _has(PWM6CON) Or _has(PWM1DCL) Or _has(PWM6DCL) Or (_has(PWM3CON) And _has(PIR1.TMR2IF))
' The RxyPPS registers are contiguous in the order of the pin numbers on every supported part (RA0PPS + pin: RB4PPS = RA0PPS + 12, RC0PPS = RA0PPS + 16,
' RC7PPS = RA0PPS + 23, read from the device files; the low byte of RA0PPS is 16, 140, 144 or 226 on every part, so the sum stays in the low byte), so the
' register is reached through FSR0 (compiler-owned, nothing live in it across a statement; the block clobbers W, STATUS and BSR, and the two parameters may be in
' different banks, so each is selected). Callers pass a pin PinOk accepted.
Sub SetPps(ByVal pin As Byte, ByVal code As Byte)
#if _has(RF0PPS)
    ' Port F (PIC16(L)F15385/86): RF0PPS is not next to RE7PPS, so these eight are written by name.
    If pin >= 40 Then
        If pin = 40 Then
            RF0PPS = code
        ElseIf pin = 41 Then
            RF1PPS = code
        ElseIf pin = 42 Then
            RF2PPS = code
        ElseIf pin = 43 Then
            RF3PPS = code
        ElseIf pin = 44 Then
            RF4PPS = code
        ElseIf pin = 45 Then
            RF5PPS = code
        ElseIf pin = 46 Then
            RF6PPS = code
        Else
            RF7PPS = code
        End If
        Exit
    End If
#endif
    Asm
        banksel PWM_SETPPS__PIN
        movf PWM_SETPPS__PIN, w
        addlw low(RA0PPS)
        movwf FSR0L
        movlw high(RA0PPS)
        movwf FSR0H
        banksel PWM_SETPPS__CODE
        movf PWM_SETPPS__CODE, w
        movwf INDF0
    End Asm
End Sub
#else
' The RxyPPS registers are contiguous from RA0PPS in the order of the pin numbers (RA0..RC7 = 0..23) on the PIC18-Q41
' [DS40002214G register summary: RA0PPS 0x0201 .. RC7PPS 0x0218] and the PIC18F27Q10 [DS40002043F: 0x0EE2 .. 0x0EF9], so one write
' through FSR2 replaces a chain of one comparison per pin. Callers pass a pin PinOk accepted. FSR2 is saved and put back
' (it is the stack pointer under the reentrant software stack); the Asm block names the parameters and save bytes so the
' compiler keeps them.
Sub SetPps(ByVal pin As Byte, ByVal code As Byte)
    Dim sl As Byte
    Dim sh As Byte
    sl = 0
    sh = 0
    Asm
        movff FSR2L, PWM_SETPPS__SL
        movff FSR2H, PWM_SETPPS__SH
        lfsr 2, RA0PPS
        movf PWM_SETPPS__PIN, w, c
        addwf FSR2L, f, c
        movf PWM_SETPPS__CODE, w, c
        movwf INDF2, c
        movff PWM_SETPPS__SL, FSR2L
        movff PWM_SETPPS__SH, FSR2H
    End Asm
End Sub
#endif

' Writes the module control register: CCPxCON for channels 1, 2, PWMxCON for 3, 4.
Sub SetCon(ByVal ch As Byte, ByVal v As Byte)
    If ch = 1 Then
        CCP1CON = v
    ElseIf ch = 2 Then
        CCP2CON = v
#if _has(PWM6DCL) And Not (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))
    ElseIf ch = 3 Then
        PWM5CON = v
    Else
        PWM6CON = v
#elseif _has(PWM1DCL)
    ElseIf ch = 3 Then
        PWM1CON = v
    Else
        PWM2CON = v
#else
    ElseIf ch = 3 Then
        PWM3CON = v
    Else
        PWM4CON = v
#endif
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
    hi = (d.Byte1 << 6) Or (d.Byte0 >> 2)
    lo = d.Byte0 << 6
    If ch = 1 Then
        CCPR1L = lo
        CCPR1H = hi
    ElseIf ch = 2 Then
        CCPR2L = lo
        CCPR2H = hi
#if _has(PWM6DCL) And Not (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))
    ElseIf ch = 3 Then
        PWM5DCL = lo
        PWM5DCH = hi
    Else
        PWM6DCL = lo
        PWM6DCH = hi
#elseif _has(PWM1DCL)
    ElseIf ch = 3 Then
        PWM1DCL = lo
        PWM1DCH = hi
    Else
        PWM2DCL = lo
        PWM2DCH = hi
#else
    ElseIf ch = 3 Then
        PWM3DCL = lo
        PWM3DCH = hi
    Else
        PWM4DCL = lo
        PWM4DCH = hi
#endif
    End If
End Sub

' Stops a channel: the pin becomes an input again and returns to its LATxy bit, the module is
' disabled. Timer2 is stopped when the last channel stops.
Public Sub PwmStop(ByVal ch As Byte)
    If ch >= 1 And ch <= 4 Then
        If pins(ch - 1) <> 0 Then
            Pinio.PinInput(pins(ch - 1) - 1)
            SetCon(ch, 0)
            SetPps(pins(ch - 1) - 1, 0)
            pins(ch - 1) = 0
            Dec(nact)
            If nact = 0 Then
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
    Dim old As Byte
    Dim c As Byte
    Result = 0
    If Not ready Or Not PinOk(ch, pin) Then
        Exit
    End If
    ' Another running channel may not use the pin.
    c = 4
    While c > 0
        If c <> ch And pins(c - 1) = pin + 1 Then
            Exit
        End If
        Dec(c)
    Wend
    ' A running channel is restarted: only a pin it leaves goes back to its LATxy bit, the rest is written again below
    ' (the module and Timer2 keep running, so the period is not cut short).
    old = pins(ch - 1)
    If old <> 0 And old <> pin + 1 Then
        Pinio.PinInput(old - 1)
        SetPps(old - 1, 0)
    End If
    Pinio.PinInput(pin)
#if _has(PWM6DCL) And Not (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))
    ' RxyPPS: CCP1 0Ch, CCP2 0Dh, PWM5 02h, PWM6 03h [Register 13-2]. CxTSEL and PxTSEL = 01 select Timer2 (their reset value) where the part has them.
    If ch <= 2 Then
        SetPps(pin, ch + 11)
    Else
        SetPps(pin, ch - 1)
    End If
#if _has(CCPTMRS)
    CCPTMRS = (CCPTMRS And 240) Or 5
    PWMTMRS = (PWMTMRS And 240) Or 5
#endif
#elseif _has(PWM1DCL)
    ' RxyPPS: CCP1 09h, CCP2 0Ah, PWM1 2Ch, PWM2 2Dh [Table 18-2]. Timer2 is the only PWM timer and the reset selection of CCPTMRS0 and PWMTMRS0
    ' [25.1.1, 27.1.1], so they are not written.
    If ch <= 2 Then
        SetPps(pin, ch + 8)
    Else
        SetPps(pin, ch + 41)
    End If
#elseif _has(PWM5CON)
    ' RxyPPS: CCP1 09h, CCP2 0Ah, PWM3 0Bh, PWM4 0Ch [Table 18-2 p.170]. Timer2 is the reset selection of CCPTMRS0 and PWMTMRS0, so they are not written.
    SetPps(pin, ch + 8)
#elseif (_has(PWM3CON) And _has(PIR1.TMR2IF))
    ' RxyPPS: CCP1 01h, CCP2 02h, PWM3 03h, PWM4 04h [Table 18-2 p.148]. Timer2 is the only PWM timer; there is no CCPTMRS.
    SetPps(pin, ch)
#else
    SetPps(pin, ch + 4)
    ' CCPTMRS: CnTSEL / PnTSEL = 01 selects Timer2 for PWM; all four fields reset to 01 (CCPTMRS = 55h) [DS40002043F 22.6.4
    ' p.359, 23.12.2 p.367], so it is left alone, as on the other parts. A program that gives a channel another timer has to
    ' give it back before PwmStart.
#endif
    If ch <= 2 Then
        ' EN = 1, FMT = 1, MODE = 11xx (PWM) [22.6.1]
        SetCon(ch, 156)
    Else
        SetCon(ch, polv(ch - 1))
    End If
    SetDuty(ch, duty)
    If nact = 0 Then
        T2CON = 0
#if _has(PWM6DCL) And Not (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))
        PR2 = period
        TMR2 = 0
        Tmr2If = 0
        T2CON = 4 + ckps
#else
        T2CLKCON = 1
        T2HLT = 0
        T2RST = 0
        T2PR = period
        T2TMR = 0
        Tmr2If = 0
        T2CON = 128 + ckps * 16
#endif
    Else
        Tmr2If = 0
    End If
    While Tmr2If = 0
    Wend
    Tmr2If = 0
    pins(ch - 1) = pin + 1
    If old = 0 Then
        Inc(nact)
    End If
    Pinio.PinOutput(pin)
    If ch > 2 Then
        SetCon(ch, 128 + polv(ch - 1))
    End If
    Result = 1
End Function

' Duty cycle in steps (0..PwmSteps, at most 1023 are representable); no effect on a stopped channel.
Public Sub PwmDuty(ByVal ch As Byte, ByVal duty As Word)
    If ch >= 1 And ch <= 4 Then
        If pins(ch - 1) <> 0 Then
            SetDuty(ch, duty)
        End If
    End If
End Sub

' Duty cycle as a percentage 0..100 of the period (rounded down to a step; 100 gives the highest
' duty, see the header).
Public Sub PwmPercent(ByVal ch As Byte, ByVal pct As Byte)
    Dim d As Word
    If pct > 100 Then
        pct = 100
    End If
    ' steps is 4 * n with n at most 256 (PwmInit), so steps * pct / 100 is n * pct / 25 to the last bit, and n * pct is at
    ' most 25600: a Word, where steps * pct (up to 102400) is a LongWord and links the 32-bit multiply and divide.
    d = (steps >> 2) * pct / 25
    PwmDuty(ch, d)
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
        If pins(ch - 1) <> 0 Then
            SetCon(ch, 128 + polv(ch - 1))
        End If
        Result = 1
    End If
End Function
#endif
