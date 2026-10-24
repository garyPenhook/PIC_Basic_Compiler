Module Timer
' Timer0 helpers (DS40002043F, chapter 19). The module only configures the timer and reads its
' flag. It declares no interrupt handler, so it never claims a vector: to be interrupted, call
' Timer0EnableInterrupt, write your own `Interrupt` and call Timer0Ack in it (flags are not
' cleared by hardware).
'
' Clock source is FOSC/4 [Table 19-1, T0CS = 010]. In 8-bit mode the timer counts 0..period and
' then restarts, so one overflow takes (period + 1) * 2^prescale instruction cycles
' (prescale 0..15 selects 1:1 to 1:32768 [T0CON1]).
Dim Tmr0If As PIR0.5
Dim Tmr0Ie As PIE0.5

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
