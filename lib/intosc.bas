Module IntOsc
' Internal oscillator set-up for the PIC18(L)F2x/4xQ10, DS40002043F chapter 5.
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
' HFINTOSC frequency codes: OSCFRQ.HFFRQ (Q10: 1, 2, 4, 8, 12, 16, 32, 48, 64 MHz = codes 0..8) or
' OSCFRQ.FRQ (PIC16F171xx: 1, 2, 4, 8, 16, 32 MHz = codes 0..5, DS40002343F 11.5.6).
#if _has(ADCON0.CHS) And Not _has(ADCON1.PREF)
#error "intosc is not ported to the PIC16F183xx: its HFFRQ codes differ from the Q10 (1, 2, -, 4, 8, 12, 16 MHz = 0..6, 32 MHz through the 2x PLL with NOSC = 000, DS40001839E Register 7-6 p.93) and the clock switch to 32 MHz needs its own sequence; set the speed with Config RSTOSC (HFINT32 = 32 MHz, HFINT1 = 1 MHz) and Clock to match, and check it with System.SysClockOk()"
#endif
#if _has(OSCFRQ.HFFRQ)
#elseif _has(OSCFRQ.FRQ)
#else
#error "intosc needs a part with an OSCFRQ register (HFFRQ or FRQ field)"
#endif

#if _has(ADCON1.PREF) And _clock < 1
#error "Clock is not an HFINTOSC speed of the PIC16F152xx, which has no clock divider: use 32, 16, 8, 4, 2 or 1"
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
    While OSCSTAT.HFOR = 0 And (OSCCON And 16) = 0 And n < 60000
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
    While (OSCCON3.ORDY = 0 Or OSCSTAT.HFOR = 0) And n < 60000
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
    If Settle() And first Then
        Result = (OSCCON2 = NoscHf + shift) And ((OSCFRQ And 15) = frq)
    Else
        Result = False
    End If
End Function
#endif

' The OSCFRQ code for `mhz` (Q10: 1, 2, 4, 8, 12, 16, 32, 48 or 64; PIC16F171xx: 1, 2, 4, 8, 16 or 32), or 255 for any other value.
Private Function FrqCode(ByVal mhz As Byte) As Byte
    Result = 255
    If mhz = 1 Then
        Result = 0
    ElseIf mhz = 2 Then
        Result = 1
    ElseIf mhz = 4 Then
        Result = 2
    ElseIf mhz = 8 Then
        Result = 3
#if _has(OSCFRQ.HFFRQ)
    ElseIf mhz = 12 Then
        Result = 4
    ElseIf mhz = 16 Then
        Result = 5
    ElseIf mhz = 32 Then
        Result = 6
    ElseIf mhz = 48 Then
        Result = 7
    ElseIf mhz = 64 Then
        Result = 8
#else
    ElseIf mhz = 16 Then
        Result = 4
    ElseIf mhz = 32 Then
        Result = 5
#endif
    End If
End Function

' Runs HFINTOSC at `mhz` divided by 2^shift (shift 0..9, so 1:1 to 1:512; the PIC16F152xx has no divider, shift must be 0). False, and nothing changed,
' for a `mhz` or `shift` the part does not have; False too when the clock did not switch.
Public Function SetClockDiv(ByVal mhz As Byte, ByVal shift As Byte) As Boolean
    Dim frq As Byte
    frq = FrqCode(mhz)
    Result = False
#if _has(ADCON1.PREF)
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
#if _has(ADCON1.PREF)
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
