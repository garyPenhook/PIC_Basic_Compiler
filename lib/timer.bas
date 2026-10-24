Module Timer
' Timer0, Timer1 and Timer2 helpers (DS40002043F, chapters 19, 20, 21). The module only configures the timer and reads its
' flag. It declares no interrupt handler, so it never claims a vector: to be interrupted, call
' Timer0EnableInterrupt, write your own `Interrupt` and call Timer0Ack in it (flags are not
' cleared by hardware).
'
' Clock source is FOSC/4 [Table 19-1, T0CS = 010]. In 8-bit mode the timer counts 0..period and
' then restarts, so one overflow takes (period + 1) * 2^prescale instruction cycles
' (prescale 0..15 selects 1:1 to 1:32768 [T0CON1]).
Dim Tmr0If As PIR0.5
Dim Tmr0Ie As PIE0.5
Dim Tmr1If As PIR4.0
Dim Tmr1Ie As PIE4.0
Dim Tmr2If As PIR4.1
Dim Tmr2Ie As PIE4.1

' 8-bit periodic timer. period = 0..255.
Public Sub Timer0Start(ByVal prescale As Byte, ByVal period As Byte)
    T0CON0 = 0
    T0CON1 = 64 + (prescale And 15)
    TMR0H = period
    TMR0L = 0
    Tmr0If = 0
    T0CON0 = 128
End Sub

' 16-bit free-running timer, read with Timer0Read.
Public Sub Timer0Start16(ByVal prescale As Byte)
    T0CON0 = 0
    T0CON1 = 64 + (prescale And 15)
    TMR0L = 0
    TMR0H = 0
    Tmr0If = 0
    T0CON0 = 144
End Sub

Public Sub Timer0Stop()
    T0CON0 = 0
End Sub

' 16-bit count. TMR0L is read first, which latches TMR0H [19.1.2].
Public Function Timer0Read() As Word
    Dim lo As Byte
    lo = TMR0L
    Result = TMR0H * 256 + lo
End Function

' True once per overflow; clears the flag when it reports it.
Public Function Timer0Expired() As Boolean
    Result = False
    If Tmr0If = 1 Then
        Tmr0If = 0
        Result = True
    End If
End Function

Public Sub Timer0Ack()
    Tmr0If = 0
End Sub

Public Sub Timer0EnableInterrupt()
    Tmr0If = 0
    Tmr0Ie = 1
End Sub

Public Sub Timer0DisableInterrupt()
    Tmr0Ie = 0
End Sub

' Timer1: 16-bit, FOSC/4 clock [Table 20-2, T1CLK CS = 00001], T1CON = CKPS[5:4] | RD16 | ON
' [20.14.1]; no gate [T1GCON = 0]. It overflows every 65536 * 2^prescale instruction cycles
' (prescale 0..3 selects 1:1 to 1:8). With RD16 set, reading TMR1L latches TMR1H.
Public Sub Timer1Start(ByVal prescale As Byte)
    T1CON = 0
    T1CLK = 1
    T1GCON = 0
    TMR1L = 0
    TMR1H = 0
    Tmr1If = 0
    T1CON = (prescale And 3) * 16 + 3
End Sub

Public Sub Timer1Stop()
    T1CON = 0
End Sub

Public Function Timer1Read() As Word
    Dim lo As Byte
    lo = TMR1L
    Result = TMR1H * 256 + lo
End Function

' True once per overflow; clears the flag when it reports it.
Public Function Timer1Expired() As Boolean
    Result = False
    If Tmr1If = 1 Then
        Tmr1If = 0
        Result = True
    End If
End Function

Public Sub Timer1Ack()
    Tmr1If = 0
End Sub

Public Sub Timer1EnableInterrupt()
    Tmr1If = 0
    Tmr1Ie = 1
End Sub

Public Sub Timer1DisableInterrupt()
    Tmr1Ie = 0
End Sub

' Timer2: 8-bit, FOSC/4 clock [Table 21-1, T2CLKCON CS = 00001], free-running period mode
' [T2HLT MODE = 00000, Table 21-3], T2CON = ON | CKPS[6:4] | OUTPS[3:0] [21.9.3]. T2TMR counts
' 0..period and restarts; the flag is set on every (postscale + 1)th match, so it is set every
' (period + 1) * 2^prescale * (postscale + 1) instruction cycles (prescale 0..7 selects 1:1 to
' 1:128, postscale 0..15 selects 1:1 to 1:16). T2TMR is not cleared by a T2CON write [21.1].
Public Sub Timer2Start(ByVal prescale As Byte, ByVal postscale As Byte, ByVal period As Byte)
    T2CON = 0
    T2CLKCON = 1
    T2HLT = 0
    T2RST = 0
    T2PR = period
    T2TMR = 0
    Tmr2If = 0
    T2CON = 128 + (prescale And 7) * 16 + (postscale And 15)
End Sub

' Turning the timer off also resets its counters [21.9.3].
Public Sub Timer2Stop()
    T2CON = 0
End Sub

Public Function Timer2Read() As Byte
    Result = T2TMR
End Function

' True once per period; clears the flag when it reports it.
Public Function Timer2Expired() As Boolean
    Result = False
    If Tmr2If = 1 Then
        Tmr2If = 0
        Result = True
    End If
End Function

Public Sub Timer2Ack()
    Tmr2If = 0
End Sub

Public Sub Timer2EnableInterrupt()
    Tmr2If = 0
    Tmr2Ie = 1
End Sub

Public Sub Timer2DisableInterrupt()
    Tmr2Ie = 0
End Sub
