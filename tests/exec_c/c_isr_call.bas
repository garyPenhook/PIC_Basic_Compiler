' expect: T_OK=1 T_BAD=0 T_RAN=1
' A Timer0 handler calls the C routine `scramble` (inside Save) while the main program calls it in a loop.
' Every call, in either context, must give the result of an undisturbed call: C is never entered twice.
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
Dim bad As Byte
Dim ok As Byte
Dim ref As LongWord
Dim r1 As LongWord
Dim r2 As LongWord
Dim hr As LongWord
Dim k As Byte
Dim ran As Byte

Interrupt Tick()
    T0If = 0
    Inc(hits)
    Save(0, scramble)
        hr = scramble(1234, 20)
    Restore
    If hr <> ref Then
        Inc(bad)
    End If
    If hits < 25 Then
        TMR0H = 250 + (hits And 3)
    Else
        T0CON0 = 0
    End If
End Interrupt

ref = scramble(1234, 20)
T0Ie = 1
Enable(Tick)
T0CON1 = 72
T0CON0 = 128
For k = 1 To 30
    r2 = scramble(1234, 20)
    If r2 <> ref Then
        ok = 2
    End If
Next
While (T0CON0 And 128) <> 0
Wend
Disable(Tick)
If ok = 0 Then
    ok = 1
End If
If hits >= 25 Then
    ran = 1
End If
