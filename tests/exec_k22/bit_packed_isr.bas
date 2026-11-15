' expect: BPI_HITS=200 BPI_OK=1 BPI_MAIN=4
' A packed bit array whose neighbouring elements are written by main-line code (run-time index)
' and by an interrupt handler. The run-time write is a read-modify-write of a shared byte, so it
' runs with interrupts off; without that, a handler write landing between the read and the
' write is lost. Reaching 200 hits also shows interrupts come back on after each write.
' PIC18(L)F2x/4xK22 version of tests/exec/bit_packed_isr.bas: Timer0's flag, enable and priority are INTCON bits 2, 5 and INTCON2 bit 2, the
' software-raised interrupt is INT0 (INTCON bits 1 and 4, always high priority), and Timer0 has no period register, so TMR0L is reloaded
' (DS40001412H Registers 9-1, 9-2 p.109-110, 11-1 p.154). T0CON = 192: on, 8-bit, FOSC/4, 1:2.
Program BPI
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Dim T0If As INTCON.2
Dim T0Ie As INTCON.5
Dim T0Ip As INTCON2.2
Dim pk(16) As Bit
Dim hits As Word
Dim ok As Byte
Dim main As Byte
Dim i As Byte
Dim j As Byte

Interrupt Tick()
    T0If = 0
    Inc(hits)
    If (hits And 1) = 1 Then
        pk(1) = 1
    Else
        pk(1) = 0
    End If
    If (hits And 2) = 2 Then
        pk(3) = 1
    Else
        pk(3) = 0
    End If
    If hits < 200 Then
        TMR0L = 5 - Byte(hits And 3)
    Else
        T0CON = 0
    End If
End Interrupt

T0Ie = 1
Enable(Tick)
T0CON = 192
While hits < 200
    For i = 0 To 3
        j = i * 2
        pk(j) = 1
        pk(j + 8) = 1
        pk(j + 8) = 0
    Next
Wend
Disable(Tick)
ok = 1
If pk(1) <> Byte(hits And 1) Then
    ok = 0
End If
If pk(3) <> Byte((hits >> 1) And 1) Then
    ok = 0
End If
main = 0
For i = 0 To 3
    j = i * 2
    If pk(j) = 1 Then
        Inc(main)
    End If
Next
