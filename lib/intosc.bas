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

#if not(_device in (18F24Q10, 18F25Q10, 18F26Q10, 18F27Q10, 18F45Q10, 18F46Q10, 18F47Q10, 18LF24Q10, 18LF25Q10, 18LF26Q10, 18LF27Q10, 18LF45Q10, 18LF46Q10, 18LF47Q10))
#error "intosc supports the PIC18(L)F2x/4xQ10 only"
#endif

' OSCFRQ code (HFFRQ) and divider code (NDIV, a power of two: 0 = 1:1 .. 5 = 1:32) for `Clock`.
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

' NOSC = 110 (HFINTOSC) in OSCCON1 bits 6:4 [Table 5-2].
Const NoscHf As Byte = 96

' Waits for the switch to finish (ORDY) and for HFINTOSC to be ready (HFOR); gives up after a bounded
' number of polls and says whether both came true.
Private Function Settle() As Boolean
    Dim n As Word
    n = 0
    While (OSCCON3.ORDY = 0 Or OSCSTAT.HFOR = 0) And n < 60000
        Inc(n)
    Wend
    Result = OSCCON3.ORDY = 1 And OSCSTAT.HFOR = 1
End Function

' Puts HFINTOSC on OSCFRQ code `frq` divided by 2^shift. True when OSCCON2 and OSCFRQ read back as written.
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

' The OSCFRQ code for `mhz` (1, 2, 4, 8, 12, 16, 32, 48 or 64), or 255 for any other value.
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
    End If
End Function

' Runs HFINTOSC at `mhz` divided by 2^shift (shift 0..9, so 1:1 to 1:512). False, and nothing changed,
' for a `mhz` or `shift` the part does not have; False too when the clock did not switch.
Public Function SetClockDiv(ByVal mhz As Byte, ByVal shift As Byte) As Boolean
    Dim frq As Byte
    frq = FrqCode(mhz)
    Result = False
    If frq <> 255 And shift <= 9 Then
        Result = Apply(frq, shift)
    End If
End Function

' Runs HFINTOSC at `mhz` (1, 2, 4, 8, 12, 16, 32, 48 or 64) with no divider. False, and nothing
' changed, for any other value; False too when the clock did not switch (see the header).
Public Function SetClock(ByVal mhz As Byte) As Boolean
    Result = SetClockDiv(mhz, 0)
End Function

' Start-up: put the oscillator on `Clock`. The same steps as Apply with the constants written in, so a
' program that never calls SetClock or SetClockDiv does not carry Apply (nor its variables); the order
' rule is the same, and OSCCON2 is read because the reset divider depends on RSTOSC [Table 5-1].
If ClockDiv > (OSCCON2 And 15) Then
    OSCCON1 = NoscHf + ClockDiv
    Settle()
    OSCFRQ = ClockFrq
Else
    OSCFRQ = ClockFrq
    OSCCON1 = NoscHf + ClockDiv
End If
Settle()
