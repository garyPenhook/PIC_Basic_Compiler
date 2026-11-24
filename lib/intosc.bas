Module IntOsc
' Internal oscillator set-up for the PIC18(L)F2x/4xQ10, DS40002043F chapter 5 (and the parts listed below).
'
' `Clock` only tells the compiler what speed to expect (it times DelayMs, DelayUs and the library
' baud rates); it does not touch the hardware. This module is what makes the hardware match it:
' including it runs, before the main program, the register writes that put the high-frequency
' internal oscillator (HFINTOSC) on the speed named by `Clock`. Nothing else is needed:
'
'     Device = 18F27Q10
'     Clock = 16
'     Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
'     Include "intosc"
'
' Include it before the other modules so the clock is right as early as possible; module start-up
' code runs in include order.
'
' Clock values accepted (anything else is a compile-time error):
'   64, 48, 32, 16, 12, 8, 4, 2, 1 MHz     HFINTOSC at that setting, divider 1:1
'   0.5, 0.25, 0.125, 0.0625, 0.03125      HFINTOSC at 1 MHz, divider 1:2 .. 1:32 [5.6.1, Table 5-3]
'
' Configuration: `CSWEN = ON` is required for every speed except the one `RSTOSC` already gives
' (OSCCON1 is read-only while CSWEN = 0 [5.6.1 note 3]); `RSTOSC = HFINTOSC_64MHZ` with
' `FEXTOSC = OFF` is the usual choice. If a write is ignored, `System.SysClockOk()` is False.
'
' Register order: a write to OSCCON1 starts a clock switch and OSCCON3.ORDY reads 1 again when it
' is over (a divider-only change is ready almost at once) [5.3.1, 5.6.3]; OSCFRQ chooses the
' HFINTOSC frequency [5.6.5]. The data sheet gives no order between the two, so the divider is
' written first when it grows and OSCFRQ first otherwise: the clock then never runs faster than
' the faster of the old and the new setting. The routine then waits for ORDY and for
' OSCSTAT.HFOR (HFINTOSC ready) [5.6.4], each bounded so a part that never answers cannot hang
' the program. OSCTUNE is not touched. CSWHOLD must be clear (reset value) for a switch to finish.
'
' Limits: DelayMs, DelayUs and the serial/I2C/SPI/PWM libraries are timed from the compile-time
' `Clock`. A run-time SetClock changes the hardware but not that timing, so they are wrong
' until the clock is back at `Clock`. Use it for phases that need no timed library.

' PIC16F152xx (DS40002195E chapter 11; chosen with `_has(ADCON1.PREF)`): the part has no clock switching and no divider ("the system clock source cannot be changed", p.78): RSTOSC picks the
' source, and only when it is an HFINTOSC setting (RSTOSC = HFINTOSC_32MHZ or HFINTOSC_1MHZ, COSC = 00 or 10) does OSCFRQ.FRQ set the speed [Table 11-1 p.77, OSCFRQ p.85]. So only Clock = 32, 16, 8, 4, 2
' and 1 are accepted there, the module writes OSCFRQ (FRQ = 0..5) and waits, bounded, for OSCSTAT.HFOR; with another RSTOSC nothing waits and `System.SysClockOk()` is False.
'
' PIC16F18056/76 (DS40002325C chapter 11; chosen with `Not _has(OSCCON1)`, like the PIC16F152xx): the same model, no clock switching and no divider ("does not allow the system clock source to be changed through clock
' switching", p.81). RSTOSC picks the source (COSC in OSCCON2 bits 6:4, read-only: 000 and 110 are the HFINTOSC, Table 11-1 p.80) and only then does OSCFRQ.FRQ (1, 2, 4, 8, 16, 32 MHz = codes 0..5, p.93) set the
' speed. Only Clock = 32, 16, 8, 4, 2 and 1 are accepted; the module writes OSCFRQ and waits, bounded, for OSCSTAT.HFOR (bit 6, p.94).
'
' PIC16F153xx (DS40001897C, DS40001889E, DS40001865F, DS40001853E and DS40001866E, chapter 9; chosen with `_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)`): the same OSCCON1 / OSCCON2 / OSCCON3 / OSCFRQ / OSCSTAT
' as the Q10 [Registers 9-1 .. 9-6 p.110-114]: NOSC = 110 is the HFINTOSC at OSCFRQ.HFFRQ = 0..6 = 1, 2, 4, 8, 12, 16, 32 MHz (code 7 is reserved) and NDIV divides it by 1 to 512 [Tables 9-1, 9-2 p.111].
' So the Q10 sequence is used with 64 and 48 MHz refused; `CSWEN = ON` is needed for every speed but the one RSTOSC gives (OSCCON1 is read-only while CSWEN = 0, note 3 p.110).
'
' PIC18(L)F2x/4xK22 (DS40001412H chapter 2; chosen with `_has(OSCCON.IRCF)`): no OSCFRQ, OSCCON1 or clock divider. The 16 MHz HFINTOSC
' goes through a postscaler chosen by OSCCON.IRCF (bits 6:4): 111 = 16, 110 = 8, 101 = 4, 100 = 2, 011 = 1 MHz (the reset value),
' 010 = 500 kHz, 001 = 250 kHz and 000 = 31.25 kHz (from the HFINTOSC with OSCTUNE.INTSRC = 1 and OSCCON2.MFIOSEL = 0) [Register 2-1 p.30,
' Register 2-2 p.31, Register 2-3 p.35]. OSCCON.SCS = 1x runs the part from that internal block whatever FOSC says [2.2.1 p.27]. The 4x PLL
' (OSCTUNE.PLLEN) sits only on the primary clock path, and it multiplies the internal block only when FOSC = 100x (INTIO67 or INTIO7) makes
' it the primary clock; its input must be 4 to 16 MHz [Fig. 2-1 p.26, Table 2-1 p.28, 2.8.2 p.37]. So:
'   64, 32 MHz                       IRCF = 111 / 110, PLLEN = 1, SCS = 00: needs `Config FOSC = INTIO67` (or INTIO7)
'   16, 8, 4, 2, 1, 0.5, 0.25 MHz    IRCF, PLLEN = 0, SCS = 10 (any FOSC)
'   0.03125 (31.25 kHz)              IRCF = 000 from the HFINTOSC (INTSRC = 1, MFIOSEL = 0), SCS = 10
' Order: for a PLL speed IRCF is written (with SCS = 00) before PLLEN, so the PLL never sees an input below 4 MHz; otherwise PLLEN is cleared
' first, so the clock never runs above the faster of the old and the new speed. The routine then waits, bounded, for OSCCON.HFIOFS (HFINTOSC
' stable) and, for a PLL speed, OSCCON2.PLLRDY [Registers 2-1, 2-2]. The tuning bits OSCTUNE.TUN are kept. With another FOSC a PLL speed
' is refused: SetClock returns False and the start-up code runs the internal block without the PLL (`System.SysClockOk()` is False). SetClockDiv(mhz, shift) is
' SetClock(mhz >> shift) there (16 >> 5 = 0.5 MHz is not reachable that way, use Clock).
' dsPIC33CK64MC105 (DS70005399D chapter 9; chosen with `#if _has(PLLFBD)`): `Clock` is FOSC and the instruction clock is FOSC/2 [9.2 p.154]. The part starts on the 8 MHz FRC (FNOSC = FRCDIVN with FRCDIV = 1:1, or FRC). The module runs it
' either divided (FRCDIVN, FRC / 1, 2, 4, 8, 16, 32, 64 or 256 [CLKDIV p.160]) or through the PLL from FRC (FRCPLL): FVCO = 8 MHz * M / N1 with N1 = 1 (PLLPRE), FPLLO = FVCO / (N2 * N3) (POST1DIV, POST2DIV) and FOSC = FPLLO / 2
' [Equations 9-1, 9-2 p.152, Example 9-2 p.153]. The PLL limits are FPLLI 8 to 64 MHz, FPFD at least 8 MHz and FVCO 400 to 1600 MHz [9.1 p.151]; M is 16 to 200 [Register 9-3 p.162] and N2 >= N3 [Register 9-5 p.164]. Clock values accepted:
'   200 (M 100, N2 2), 160 (80, 2), 150 (150, 4), 120 (120, 4), 100 (100, 4), 80 (80, 4), 64 (64, 4), 60 (120, 4 x 2), 50 (100, 4 x 2), 40 (80, 4 x 2), 32 (64, 4 x 2),
'   25 (100, 4 x 4), 20 (80, 4 x 4), 16 (64, 4 x 4) MHz    FRCPLL (N3 is 1 unless shown)
'   8, 4, 2, 1, 0.5, 0.25, 0.125, 0.03125 MHz               FRCDIVN, FRCDIV = 0, 1, 2, 3, 4, 5, 6, 7
' `Config FCKSM = CSECMD` is required: with the default (clock switching disabled [Register 28-5 p.416]) the switch is ignored and `Clock` does not match the hardware (SetClock returns False). The switch is a write of OSCCON[15:8]
' and then OSCCON[7:0] (OSWEN) each after its unlock pair (0x78, 0x9A and 0x46, 0x57, back to back) [9.9 p.157]; the module masks interrupts (INTCON2.GIE) around the pairs and then waits, bounded, for OSWEN to clear and, for the PLL, LOCK.
' The PLL dividers may not change while the PLL runs and a PLL source cannot be switched to another PLL source directly [9.1 p.152]: when the part runs on a PLL the module goes through the plain FRC first.
' Start-up expects FNOSC = FRC or FRCDIVN (the default). SetClock(mhz) takes the whole-MHz speeds above (not 0.5 and below). Like the PIC modules, the timing of DelayMs, DelayUs and the libraries comes from the compile-time `Clock`.
#if _has(PLLFBD)
#if _clock = 200
Const ClockM As Byte = 100
Const ClockPost As Byte = 33
#elseif _clock = 160
Const ClockM As Byte = 80
Const ClockPost As Byte = 33
#elseif _clock = 150
Const ClockM As Byte = 150
Const ClockPost As Byte = 65
#elseif _clock = 120
Const ClockM As Byte = 120
Const ClockPost As Byte = 65
#elseif _clock = 100
Const ClockM As Byte = 100
Const ClockPost As Byte = 65
#elseif _clock = 80
Const ClockM As Byte = 80
Const ClockPost As Byte = 65
#elseif _clock = 64
Const ClockM As Byte = 64
Const ClockPost As Byte = 65
#elseif _clock = 60
Const ClockM As Byte = 120
Const ClockPost As Byte = 66
#elseif _clock = 50
Const ClockM As Byte = 100
Const ClockPost As Byte = 66
#elseif _clock = 40
Const ClockM As Byte = 80
Const ClockPost As Byte = 66
#elseif _clock = 32
Const ClockM As Byte = 64
Const ClockPost As Byte = 66
#elseif _clock = 25
Const ClockM As Byte = 100
Const ClockPost As Byte = 68
#elseif _clock = 20
Const ClockM As Byte = 80
Const ClockPost As Byte = 68
#elseif _clock = 16
Const ClockM As Byte = 64
Const ClockPost As Byte = 68
#elseif _clock = 8
Const ClockM As Byte = 0
Const ClockPost As Byte = 0
#elseif _clock = 4
Const ClockM As Byte = 0
Const ClockPost As Byte = 1
#elseif _clock = 2
Const ClockM As Byte = 0
Const ClockPost As Byte = 2
#elseif _clock = 1
Const ClockM As Byte = 0
Const ClockPost As Byte = 3
#elseif _clock = 0.5
Const ClockM As Byte = 0
Const ClockPost As Byte = 4
#elseif _clock = 0.25
Const ClockM As Byte = 0
Const ClockPost As Byte = 5
#elseif _clock = 0.125
Const ClockM As Byte = 0
Const ClockPost As Byte = 6
#elseif _clock = 0.03125
Const ClockM As Byte = 0
Const ClockPost As Byte = 7
#else
#error "Clock is not an oscillator speed of the dsPIC33CK64MC105 modules: use 200, 160, 150, 120, 100, 80, 64, 60, 50, 40, 32, 25, 20, 16 (PLL) or 8, 4, 2, 1, 0.5, 0.25, 0.125, 0.03125 (FRC divided)"
Const ClockM As Byte = 0
Const ClockPost As Byte = 0
#endif

' The new NOSC value for the Asm block of Switch.
Dim noscNew As Byte

' Switches the oscillator to NOSC = `nosc` (0 FRC, 1 FRCPLL, 7 FRCDIVN) and waits, bounded (59904 polls), for OSWEN to clear. The unlock pairs are
' back to back, so interrupts are masked meanwhile; the bit is put back as it was. W0 to W3 are scratch between statements.
Private Sub Switch(ByVal nosc As Byte)
    Dim n As Word
    Dim g As Boolean
    g = INTCON2.GIE = 1
    INTCON2.GIE = 0
    noscNew = nosc
    Asm
        mov #0x78, w0
        mov #0x9A, w1
        mov #0xF85, w2
        mov #INTOSC_NOSCNEW, w3
        mov.b [w3], w3
        mov.b w0, [w2]
        mov.b w1, [w2]
        mov.b w3, [w2]
        mov #0x46, w0
        mov #0x57, w1
        mov #0xF84, w2
        mov.b [w2], w3
        bset w3, #0
        mov.b w0, [w2]
        mov.b w1, [w2]
        mov.b w3, [w2]
    End Asm
    If g Then
        INTCON2.GIE = 1
    End If
    n = 0
    While OSCCON.OSWEN = 1 And n.Byte1 < 234
        Inc(n)
    Wend
End Sub

' Waits, bounded, for the PLL to lock.
Private Sub WaitLock()
    Dim n As Word
    n = 0
    While OSCCON.LOCK = 0 And n.Byte1 < 234
        Inc(n)
    Wend
End Sub

' COSC, the current source (OSCCON bits 14 to 12): the back end has no multi-bit fields yet, so the registers are masked by hand.
Private Function Cosc() As Byte
    Result = (OSCCON >> 12) And 7
End Function

' Runs the oscillator on `post` = N2 * 16 + N3 with feedback divider `m` (the PLL, from FRC) or, for m = 0, FRCDIV = `post` (FRC divided). True when the switch finished
' (COSC is FRCPLL with LOCK, or FRCDIVN).
Private Function Apply(ByVal m As Byte, ByVal post As Byte) As Boolean
    Dim w As Word
    If m = 0 Then
        w = post
        CLKDIV = (CLKDIV And 63743) Or (w << 8)
        Switch(7)
        Result = Cosc() = 7
    Else
        If Cosc() = 1 Or Cosc() = 3 Then
            Switch(0)
        End If
        CLKDIV = (CLKDIV And 65520) Or 1
        PLLFBD = m
        PLLDIV = post
        Switch(1)
        WaitLock()
        Result = Cosc() = 1 And OSCCON.LOCK = 1
    End If
End Function

' The speeds in MHz of the PLL entries and, in step, M and N2 * 16 + N3; then the FRC divided ones (M = 0, FRCDIV).
Const MhzTab(18) As Byte = (200, 160, 150, 120, 100, 80, 64, 60, 50, 40, 32, 25, 20, 16, 8, 4, 2, 1)
Const MTab(18) As Byte = (100, 80, 150, 120, 100, 80, 64, 120, 100, 80, 64, 100, 80, 64, 0, 0, 0, 0)
Const PostTab(18) As Byte = (33, 33, 65, 65, 65, 65, 65, 66, 66, 66, 66, 68, 68, 68, 0, 1, 2, 3)

' Runs the part at `mhz` MHz, one of the whole-MHz speeds of the header. False, and nothing changed, for any other value; False too when the switch did not finish (see the header).
Public Function SetClock(ByVal mhz As Byte) As Boolean
    Dim i As Byte
    Result = False
    For i = 0 To 17
        If MhzTab(i) = mhz Then
            Result = Apply(MTab(i), PostTab(i))
            Exit
        End If
    Next
End Function

' Start-up: the same steps with the constants of `Clock`.
Apply(ClockM, ClockPost)
#elseif _has(OSCCON.IRCF)
#if _clock = 64
Const ClockIrcf As Byte = 7
Const ClockPll As Boolean = True
#elseif _clock = 32
Const ClockIrcf As Byte = 6
Const ClockPll As Boolean = True
#elseif _clock = 16
Const ClockIrcf As Byte = 7
Const ClockPll As Boolean = False
#elseif _clock = 8
Const ClockIrcf As Byte = 6
Const ClockPll As Boolean = False
#elseif _clock = 4
Const ClockIrcf As Byte = 5
Const ClockPll As Boolean = False
#elseif _clock = 2
Const ClockIrcf As Byte = 4
Const ClockPll As Boolean = False
#elseif _clock = 1
Const ClockIrcf As Byte = 3
Const ClockPll As Boolean = False
#elseif _clock = 0.5
Const ClockIrcf As Byte = 2
Const ClockPll As Boolean = False
#elseif _clock = 0.25
Const ClockIrcf As Byte = 1
Const ClockPll As Boolean = False
#elseif _clock = 0.03125
Const ClockIrcf As Byte = 0
Const ClockPll As Boolean = False
#else
#error "Clock is not an internal oscillator speed of the PIC18(L)F2x/4xK22: use 64 or 32 (with Config FOSC = INTIO67), 16, 8, 4, 2, 1, 0.5, 0.25 or 0.03125"
Const ClockIrcf As Byte = 3
Const ClockPll As Boolean = False
#endif

' True when CONFIG1H FOSC is 100x (INTIO67 or INTIO7), the only primary clock the module may put through the PLL: with a crystal or an
' external clock PLLEN would multiply that instead (Table 2-1 p.28). CONFIG1H is read with TBLRD (TBLPTR and TABLAT are scratch, ABI.md).
Private Function IntioPrimary() As Boolean
    Dim c As Byte
    Asm
        movlw 0x30
        movwf TBLPTRU, c
        clrf TBLPTRH, c
        movlw 1
        movwf TBLPTRL, c
        tblrd*
        movff TABLAT, INTOSC_INTIOPRIMARY__C
    End Asm
    Result = (c And 14) = 8
End Function

' Waits, bounded (59904 polls: the count stops when its high byte reaches 234), for HFIOFS and, with the PLL, PLLRDY.
Private Sub WaitSettle(ByVal pll As Boolean)
    Dim n As Word
    n = 0
    While (OSCCON.HFIOFS = 0 Or (pll And OSCCON2.PLLRDY = 0)) And n.Byte1 < 234
        Inc(n)
    Wend
End Sub

' Puts the internal block on IRCF code `ircf`, through the PLL when `pll`. True when the clock reports ready (HFIOFS, and PLLRDY for the PLL);
' False, and nothing changed, for the PLL when FOSC is not INTIO67 or INTIO7.
Private Function Apply(ByVal ircf As Byte, ByVal pll As Boolean) As Boolean
    Result = False
    If pll And Not IntioPrimary() Then
        Exit
    End If
    OSCCON2.MFIOSEL = 0
    If pll Then
        OSCCON = ircf << 4
        OSCTUNE.PLLEN = 1
    Else
        OSCTUNE.PLLEN = 0
        OSCTUNE.INTSRC = 1
        OSCCON = (ircf << 4) Or 2
    End If
    WaitSettle(pll)
    Result = OSCCON.HFIOFS = 1 And (Not pll Or OSCCON2.PLLRDY = 1)
End Function

' The speeds in MHz by IRCF code (3..7; the PLL speeds are IRCF 110 and 111 times four).
Const MhzTab(8) As Byte = (0, 0, 0, 1, 2, 4, 8, 16)

' Runs the part at `mhz` MHz: 64 or 32 (through the PLL, needs FOSC = INTIO67 or INTIO7), 16, 8, 4, 2 or 1. False, and nothing changed, for
' any other value; False too when the clock did not report ready.
Public Function SetClock(ByVal mhz As Byte) As Boolean
    Dim i As Byte
    Result = False
    If mhz = 64 Or mhz = 32 Then
        Result = Apply((mhz >> 5) + 5, True)
        Exit
    End If
    For i = 3 To 7
        If MhzTab(i) = mhz Then
            Result = Apply(i, False)
            Exit
        End If
    Next
End Function

' SetClock(mhz >> shift): the K22 has no divider of its own (see the header).
Public Function SetClockDiv(ByVal mhz As Byte, ByVal shift As Byte) As Boolean
    Result = False
    If shift <= 7 Then
        Result = SetClock(mhz >> shift)
    End If
End Function

' Start-up: the same steps as Apply with the constants written in. For 64 or 32 MHz with a FOSC other than INTIO67/INTIO7 the PLL is left off
' and the internal block runs at IRCF (16 or 8 MHz), so the part is never clocked above 64 MHz; System.SysClockOk() is then False.
OSCCON2.MFIOSEL = 0
#if _clock >= 32
If IntioPrimary() Then
    OSCCON = ClockIrcf << 4
    OSCTUNE.PLLEN = 1
    WaitSettle(True)
Else
    OSCTUNE.PLLEN = 0
    OSCCON = (ClockIrcf << 4) Or 2
    WaitSettle(False)
End If
#else
OSCTUNE.PLLEN = 0
OSCTUNE.INTSRC = 1
OSCCON = (ClockIrcf << 4) Or 2
WaitSettle(False)
#endif
#else
' HFINTOSC frequency codes: OSCFRQ.HFFRQ (Q10: 1, 2, 4, 8, 12, 16, 32, 48, 64 MHz = codes 0..8) or
' OSCFRQ.FRQ (PIC16F171xx: 1, 2, 4, 8, 16, 32 MHz = codes 0..5, DS40002343F 11.5.6).
#if _has(ADCON0.CHS) And Not _has(ADCON1.PREF) And Not (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))
#error "intosc is not ported to the PIC16F183xx: its HFFRQ codes differ from the Q10 (1, 2, -, 4, 8, 12, 16 MHz = 0..6, 32 MHz through the 2x PLL with NOSC = 000, DS40001839E Register 7-6 p.93) and the clock switch to 32 MHz needs its own sequence; set the speed with Config RSTOSC (HFINT32 = 32 MHz, HFINT1 = 1 MHz) and Clock to match, and check it with System.SysClockOk()"
#endif
#if _has(OSCFRQ.HFFRQ)
#elseif _has(OSCFRQ.FRQ)
#else
#error "intosc needs a part with an OSCFRQ register (HFFRQ or FRQ field)"
#endif

#if _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF) And _clock > 32
#error "Clock is above the fastest HFINTOSC setting of the PIC16F153xx (32 MHz, OSCFRQ.HFFRQ = 110, DS40001897C Register 9-6 p.114): use 32, 16, 12, 8, 4, 2, 1 or a divided 1 MHz"
#endif

#if Not _has(OSCCON1) And _clock < 1
#error "Clock is not an HFINTOSC speed of this part (PIC16F152xx, PIC16F18056/76), which has no clock divider: use 32, 16, 8, 4, 2 or 1"
#endif

' OSCFRQ code and divider code (NDIV, a power of two: 0 = 1:1 .. 5 = 1:32) for `Clock`.
#if _has(OSCFRQ.HFFRQ)
#if _clock = 64
Const ClockFrq As Byte = 8
Const ClockDiv As Byte = 0
#elseif _clock = 48
Const ClockFrq As Byte = 7
Const ClockDiv As Byte = 0
#elseif _clock = 32
Const ClockFrq As Byte = 6
Const ClockDiv As Byte = 0
#elseif _clock = 16
Const ClockFrq As Byte = 5
Const ClockDiv As Byte = 0
#elseif _clock = 12
Const ClockFrq As Byte = 4
Const ClockDiv As Byte = 0
#elseif _clock = 8
Const ClockFrq As Byte = 3
Const ClockDiv As Byte = 0
#elseif _clock = 4
Const ClockFrq As Byte = 2
Const ClockDiv As Byte = 0
#elseif _clock = 2
Const ClockFrq As Byte = 1
Const ClockDiv As Byte = 0
#elseif _clock = 1
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 0
#elseif _clock = 0.5
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 1
#elseif _clock = 0.25
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 2
#elseif _clock = 0.125
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 3
#elseif _clock = 0.0625
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 4
#elseif _clock = 0.03125
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 5
#else
#error "Clock is not an internal oscillator speed: use 64, 48, 32, 16, 12, 8, 4, 2, 1, 0.5, 0.25, 0.125, 0.0625 or 0.03125"
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 0
#endif
#else
#if _clock = 32
Const ClockFrq As Byte = 5
Const ClockDiv As Byte = 0
#elseif _clock = 16
Const ClockFrq As Byte = 4
Const ClockDiv As Byte = 0
#elseif _clock = 8
Const ClockFrq As Byte = 3
Const ClockDiv As Byte = 0
#elseif _clock = 4
Const ClockFrq As Byte = 2
Const ClockDiv As Byte = 0
#elseif _clock = 2
Const ClockFrq As Byte = 1
Const ClockDiv As Byte = 0
#elseif _clock = 1
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 0
#elseif _clock = 0.5
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 1
#elseif _clock = 0.25
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 2
#elseif _clock = 0.125
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 3
#elseif _clock = 0.0625
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 4
#elseif _clock = 0.03125
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 5
#else
#error "Clock is not an internal oscillator speed: use 32, 16, 8, 4, 2, 1, 0.5, 0.25, 0.125, 0.0625 or 0.03125"
Const ClockFrq As Byte = 0
Const ClockDiv As Byte = 0
#endif
#endif

#if _has(ADCON1.PREF)
' Waits for HFINTOSC to be ready (HFOR) when it is the system clock (COSC = 00 or 10, OSCCON bit 4 clear); gives up after a bounded
' number of polls.
Private Sub WaitSettle()
    Dim n As Word
    n = 0
    While OSCSTAT.HFOR = 0 And (OSCCON And 16) = 0 And n.Byte1 < 234
        Inc(n)
    Wend
End Sub
#elseif Not _has(OSCCON1)
' True when the system clock is the HFINTOSC: COSC (OSCCON2 bits 6:4) = 000 or 110 [Table 11-1 p.80].
Private Function OnHf() As Boolean
    Dim c As Byte
    c = OSCCON2 And 112
    Result = c = 0 Or c = 96
End Function

' Waits for HFINTOSC to be ready (HFOR) when it is the system clock; gives up after a bounded number of polls.
Private Sub WaitSettle()
    Dim n As Word
    n = 0
    While OSCSTAT.HFOR = 0 And OnHf() And n.Byte1 < 234
        Inc(n)
    Wend
End Sub
#else
' NOSC = 110 (HFINTOSC) in OSCCON1 bits 6:4 [Table 5-2].
Const NoscHf As Byte = 96

' Waits for the switch to finish (ORDY) and for HFINTOSC to be ready (HFOR); gives up after a bounded
' number of polls.
Private Sub WaitSettle()
    Dim n As Word
    n = 0
    While (OSCCON3.ORDY = 0 Or OSCSTAT.HFOR = 0) And n.Byte1 < 234
        Inc(n)
    Wend
End Sub

' WaitSettle, then says whether both ORDY and HFOR came true.
Private Function Settle() As Boolean
    WaitSettle()
    Result = OSCCON3.ORDY = 1 And OSCSTAT.HFOR = 1
End Function
#endif

' Puts HFINTOSC on OSCFRQ code `frq` divided by 2^shift. True when OSCCON2 and OSCFRQ read back as written.
#if _has(ADCON1.PREF)
Private Function Apply(ByVal frq As Byte, ByVal shift As Byte) As Boolean
    OSCFRQ = frq
    WaitSettle()
    Result = (OSCFRQ And 7) = frq And (OSCCON And 16) = 0
End Function
#elseif Not _has(OSCCON1)
Private Function Apply(ByVal frq As Byte, ByVal shift As Byte) As Boolean
    OSCFRQ = frq
    WaitSettle()
    Result = (OSCFRQ And 7) = frq And OnHf()
End Function
#else
Private Function Apply(ByVal frq As Byte, ByVal shift As Byte) As Boolean
    Dim first As Boolean
    first = True
    If shift > (OSCCON2 And 15) Then
        OSCCON1 = NoscHf + shift
        first = Settle()
        OSCFRQ = frq
    Else
        OSCFRQ = frq
        OSCCON1 = NoscHf + shift
    End If
    Result = Settle() And first And (OSCCON2 = NoscHf + shift) And ((OSCFRQ And 15) = frq)
End Function
#endif

' The speeds in MHz by OSCFRQ code (the code is the index).
#if _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF) And _has(OSCFRQ.HFFRQ)
' PIC16F153xx: HFFRQ 0..6 = 1, 2, 4, 8, 12, 16, 32 MHz, 7 is reserved [Register 9-6 p.114 of DS40001897C].
Const MhzTab(7) As Byte = (1, 2, 4, 8, 12, 16, 32)
Const MhzN As Byte = 7
#elseif _has(OSCFRQ.HFFRQ)
Const MhzTab(9) As Byte = (1, 2, 4, 8, 12, 16, 32, 48, 64)
Const MhzN As Byte = 9
#else
Const MhzTab(6) As Byte = (1, 2, 4, 8, 16, 32)
Const MhzN As Byte = 6
#endif

' The OSCFRQ code for `mhz` (Q10: 1, 2, 4, 8, 12, 16, 32, 48 or 64; PIC16F171xx: 1, 2, 4, 8, 16 or 32), or 255 for any other value.
Private Function FrqCode(ByVal mhz As Byte) As Byte
    Dim i As Byte
    Result = 255
    For i = 0 To MhzN - 1
        If MhzTab(i) = mhz Then
            Result = i
            Exit
        End If
    Next
End Function

' Runs HFINTOSC at `mhz` divided by 2^shift (shift 0..9, so 1:1 to 1:512; the PIC16F152xx and PIC16F18056/76 have no divider, shift must be 0). False, and nothing changed,
' for a `mhz` or `shift` the part does not have; False too when the clock did not switch.
Public Function SetClockDiv(ByVal mhz As Byte, ByVal shift As Byte) As Boolean
    Dim frq As Byte
    frq = FrqCode(mhz)
    Result = False
#if Not _has(OSCCON1)
    If frq <> 255 And shift = 0 Then
#else
    If frq <> 255 And shift <= 9 Then
#endif
        Result = Apply(frq, shift)
    End If
End Function

' Runs HFINTOSC at `mhz` (see FrqCode) with no divider. False, and nothing
' changed, for any other value; False too when the clock did not switch (see the header).
Public Function SetClock(ByVal mhz As Byte) As Boolean
    Result = SetClockDiv(mhz, 0)
End Function

' Start-up: put the oscillator on `Clock`. The same steps as Apply with the constants written in, so a
' program that never calls SetClock or SetClockDiv does not carry Apply (nor its variables); the order
' rule is the same, and OSCCON2 is read because the reset divider depends on RSTOSC [Table 5-1].
#if Not _has(OSCCON1)
OSCFRQ = ClockFrq
#elseif _clock >= 1
' No divider: the new divider (0) can never exceed the current one, so OSCFRQ goes first.
OSCFRQ = ClockFrq
OSCCON1 = NoscHf
#else
If ClockDiv > (OSCCON2 And 15) Then
    OSCCON1 = NoscHf + ClockDiv
    WaitSettle()
    OSCFRQ = ClockFrq
Else
    OSCFRQ = ClockFrq
    OSCCON1 = NoscHf + ClockDiv
End If
#endif
WaitSettle()
#endif
