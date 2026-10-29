' expect: T_OK=1 T_LH=150
' Two priorities (IPEN = 1): a low-priority Timer0 handler kicks a high-priority software-interrupt
' handler while the main program is inside C routines (see c_isr.c).
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
CFile "c_isr.c"
#if _has(PIR3.TMR0IF)
Dim T0If As PIR3.7
Dim T0Ie As PIE3.7
Dim T0Ip As IPR3.7
#else
Dim T0If As PIR0.5
Dim T0Ie As PIE0.5
Dim T0Ip As IPR0.5
#endif
#if _has(PIR3.TMR1IF)
Dim SwIf As PIR3.4
Dim SwIe As PIE3.4
Dim SwIp As IPR3.4
#else
Dim SwIf As PIR0.0
Dim SwIe As PIE0.0
Dim SwIp As IPR0.0
#endif
Extern Function scramble(x As Word, n As Byte) As LongWord
Dim hh As Word
Dim lh As Word
Dim ok As Byte
Dim r1 As LongWord
Dim r2 As LongWord
Dim k As Byte

Interrupt Hi(ipHigh)
    SwIf = 0
    Inc(hh)
    If hh < 150 Then
        SwIf = 1
    End If
End Interrupt

Interrupt Lo(ipLow)
    T0If = 0
    SwIf = 1
    Inc(lh)
    If lh < 150 Then
        TMR0H = 200 + (lh And 31)
    Else
        T0CON0 = 0
    End If
End Interrupt

T0Ip = 0
SwIp = 1
T0Ie = 1
SwIe = 1
Enable(Hi)
Enable(Lo)
r1 = scramble(1234, 20)
T0CON1 = 65
T0CON0 = 128
For k = 1 To 60
    r2 = scramble(1234, 20)
    If r2 <> r1 Then
        ok = 2
    End If
Next
While hh < 150 Or lh < 150
Wend
Disable(Lo)
Disable(Hi)
If ok = 0 Then
    ok = 1
End If
