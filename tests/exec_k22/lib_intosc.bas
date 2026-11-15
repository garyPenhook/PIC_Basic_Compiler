' engine: sim
' expect: KO_C0=124 KO_T0=64 KO_HZ0=64000000 KO_OK0=1 KO_S8=1 KO_C8=102 KO_T8=0 KO_HZ8=8000000 KO_S32=1 KO_HZ32=32000000 KO_BAD=0 KO_DIV=1 KO_HZD=4000000 KO_CAUSE=1 KO_FL=28
' Internal oscillator on the PIC18(L)F2x/4xK22 (DS40001412H chapter 2): Clock = 64 with FOSC = INTIO67 is IRCF = 111 (16 MHz), SCS = 00
' and the 4x PLL; OSTS (bit 3) and HFIOFS (bit 2) read 1, so OSCCON = 0111 1100 = 124 (Registers 2-1, 2-3 p.30, 35). SetClock(8) is IRCF = 110 with SCS = 10 and no PLL: OSCCON = 0110 0110 = 102 (HFIOFS 1, OSTS 0). 32 MHz is
' IRCF 110 through the PLL; 12 MHz is not a speed of the part. SetClockDiv(16, 2) is SetClock(4). System.SysClockHz reads the clock back
' (CONFIG1H FOSC through TBLRD, IRCF, SCS, PLLRDY). Reset cause after power-up: 1 (POR); RCON | STKPTR flags = 0001 1100 = 28 (RI, TO, PD
' set; POR and BOR clear after a power-on Reset, Table 4-3 p.62).
' MDB does not model OSTS, HFIOFS or PLLRDY (they read as written), so this runs in basil-sim.
Program Ko
Device = 18F25K22
Clock = 64
Config FOSC = INTIO67, WDTEN = OFF, LVP = ON
Include "intosc"
Include "system"
Dim c0 As Byte
Dim t0 As Byte
Dim hz0 As LongWord
Dim ok0 As Byte
Dim s8 As Byte
Dim c8 As Byte
Dim t8 As Byte
Dim hz8 As LongWord
Dim s32 As Byte
Dim hz32 As LongWord
Dim bad As Byte
Dim div As Byte
Dim hzd As LongWord
Dim cause As Byte
Dim fl As Byte
cause = System.SysResetCause()
fl = System.SysResetFlags()
c0 = OSCCON
t0 = OSCTUNE And 64
hz0 = System.SysClockHz()
If System.SysClockOk() Then
    ok0 = 1
End If
If IntOsc.SetClock(8) Then
    s8 = 1
End If
c8 = OSCCON
t8 = OSCTUNE And 64
hz8 = System.SysClockHz()
If IntOsc.SetClock(32) Then
    s32 = 1
End If
hz32 = System.SysClockHz()
If IntOsc.SetClock(12) Then
    bad = 1
End If
If IntOsc.SetClockDiv(16, 2) Then
    div = 1
End If
hzd = System.SysClockHz()
