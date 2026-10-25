Module System
' Reset cause and clock check, DS40002043F chapters 5 and 9 (PIC16F17126/46: DS40002343F
' sections 10.14.2 and 11.5; PCON0 and OSCCON1/2 have the same layout).
'
' Reset cause: PCON0 flags [9.12, 9.14.2]. Hardware sets one to its active state on a Reset and never
' clears it again, so the program should read the cause at start and then call SysClearResetFlags.
' Active states: POR, BOR, RMCLR, RWDT, WDTWV, RI = 0; STKOVF, STKUNF = 1. A flag not caused by
' the current Reset keeps its earlier value (Table 9-3), so a flag left over from an earlier Reset
' is reported until it is cleared. The BOR flag is unknown after a power-on Reset (Table 9-3,
' "x"); POR is therefore tested first.
'
' Clock check: the library modules and DelayUs/DelayMs compute from the compile-time `Clock`; the
' module does not change the clock at run time (that would make every one of them wrong), it
' reads what the oscillator really does and compares it with `Clock`.

' The cause of the latest Reset not yet cleared, tested in this order:
'   1 power-on, 2 brown-out, 7 stack overflow, 8 stack underflow, 5 watchdog window violation,
'   4 watchdog time-out, 3 MCLR pin, 6 RESET instruction, 0 none (all flags cleared).
Public Function SysResetCause() As Byte
    Dim f As Byte
    f = PCON0
    Result = 0
    If (f And 2) = 0 Then
        Result = 1
    ElseIf (f And 1) = 0 Then
        Result = 2
    ElseIf (f And 128) <> 0 Then
        Result = 7
    ElseIf (f And 64) <> 0 Then
        Result = 8
    ElseIf (f And 32) = 0 Then
        Result = 5
    ElseIf (f And 16) = 0 Then
        Result = 4
    ElseIf (f And 8) = 0 Then
        Result = 3
    ElseIf (f And 4) = 0 Then
        Result = 6
    End If
End Function

' The raw PCON0 value.
Public Function SysResetFlags() As Byte
    Result = PCON0
End Function

' Puts every PCON0 flag to its inactive state (so the next Reset shows only its own cause).
Public Sub SysClearResetFlags()
    PCON0 = 63
End Sub

' The system clock in Hz for a source `cosc` (OSCCON2 bits 6:4), divider code `cdiv` (OSCCON2 bits 3:0)
' and HFINTOSC frequency code `hffrq` (OSCFRQ bits 3:0) [5.6.2, 5.6.5, Table 5-1]: HFINTOSC (cosc = 6) at
' 1, 2, 4, 8, 12, 16, 32, 48 or 64 MHz (codes 0..8) divided by 1..512 (codes 0..9). 0 for any other source (the
' external and low-frequency sources have no frequency the module knows) or a reserved code. The HFINTOSC
' frequency is the nominal one (OSCTUNE is not applied).
Public Function SysClockFrom(ByVal cosc As Byte, ByVal cdiv As Byte, ByVal hffrq As Byte) As LongWord
    Dim mhz As Byte
    Result = 0
    If cosc <> 6 Or cdiv > 9 Then
        Exit
    End If
    mhz = 0
    If hffrq = 0 Then
        mhz = 1
    ElseIf hffrq = 1 Then
        mhz = 2
    ElseIf hffrq = 2 Then
        mhz = 4
    ElseIf hffrq = 3 Then
        mhz = 8
#if _has(OSCFRQ.HFFRQ)
    ElseIf hffrq = 4 Then
        mhz = 12
    ElseIf hffrq = 5 Then
        mhz = 16
    ElseIf hffrq = 6 Then
        mhz = 32
    ElseIf hffrq = 7 Then
        mhz = 48
    ElseIf hffrq = 8 Then
        mhz = 64
#else
    ElseIf hffrq = 4 Then
        mhz = 16
    ElseIf hffrq = 5 Then
        mhz = 32
#endif
    End If
    If mhz <> 0 Then
        Result = (LongWord(mhz) * 1000000) >> cdiv
    End If
End Function

' The system clock in Hz as the oscillator is set now (SysClockFrom of OSCCON2 and OSCFRQ).
Public Function SysClockHz() As LongWord
    Result = SysClockFrom((OSCCON2 >> 4) And 7, OSCCON2 And 15, OSCFRQ And 15)
End Function

' True when the oscillator runs at the frequency the program was compiled for (`Clock`).
Public Function SysClockOk() As Boolean
    Result = SysClockHz() = LongWord(_Clock * 1000000)
End Function
