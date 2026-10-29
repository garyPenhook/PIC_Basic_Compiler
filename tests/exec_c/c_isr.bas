' expect: T_OK=1 T_HITS=200
' A Timer0 handler (one level, no priorities) runs while the main program is inside C routines that use
' FSR0, FSR1, PROD, TBLPTR and TABLAT. The result of C must not change because interrupts came.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
CFile "c_isr.c"
#if _has(PIR3.TMR0IF)
Dim T0If As PIR3.7
Dim T0Ie As PIE3.7
#else
Dim T0If As PIR0.5
Dim T0Ie As PIE0.5
#endif
Extern Function scramble(x As Word, n As Byte) As LongWord
Dim hits As Word
Dim ok As Byte
Dim r1 As LongWord
Dim r2 As LongWord
Dim k As Byte
Dim v(4) As Word

Interrupt Tick()
    T0If = 0
    Inc(hits)
    v(hits And 3) = hits * 5
    If hits < 200 Then
        TMR0H = 200 + (hits And 31)
    Else
        T0CON0 = 0
    End If
End Interrupt

T0Ie = 1
Enable(Tick)
r1 = scramble(1234, 20)
T0CON1 = 65
T0CON0 = 128
For k = 1 To 60
    r2 = scramble(1234, 20)
    If r2 <> r1 Then
        ok = 2
    End If
Next
While T0CON0 <> 0
Wend
Disable(Tick)
If ok = 0 Then
    ok = 1
End If
