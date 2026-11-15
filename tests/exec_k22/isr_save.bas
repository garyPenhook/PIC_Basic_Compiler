' expect: ISS_HITS=1 ISS_A=8 ISS_B=55 ISS_KEEP=77
' Save … Restore: a saved variable comes back whichever way the block is left (end, Continue,
' Break, Exit), and a routine the handler calls inside Save leaves the frame it shares with a
' main-line routine (Bump's `y` and Other's `z` overlay) as it found it.
' PIC18(L)F2x/4xK22 version of tests/exec/isr_save.bas: Timer0's flag, enable and priority are INTCON bits 2, 5 and INTCON2 bit 2, the
' software-raised interrupt is INT0 (INTCON bits 1 and 4, always high priority), and Timer0 has no period register, so TMR0L is reloaded
' (DS40001412H Registers 9-1, 9-2 p.109-110, 11-1 p.154). T0CON = 192: on, 8-bit, FOSC/4, 1:2.
Program Iss
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Dim SwIf As INTCON.1
Dim SwIe As INTCON.4
Dim hits As Byte
Dim a As Byte
Dim b As Byte
Dim keep As Byte

Function Bump(ByVal x As Byte) As Byte
    Dim y As Byte
    y = x + 1
    Result = y
End Function

Function Other() As Byte
    Dim z As Byte
    z = 55
    SwIf = 1
    While hits < 1
    Wend
    Result = z
End Function

Interrupt H()
    Dim i As Byte
    SwIf = 0
    Inc(hits)
    keep = 77
    For i = 1 To 3
        Save(keep)
            keep = 1
            If i = 1 Then
                Continue
            End If
            If i = 2 Then
                Break
            End If
        Restore
    Next
    Save(0, Bump)
        a = Bump(7)
    Restore
    Save(keep)
        keep = 5
        If hits > 0 Then
            Exit
        End If
    Restore
    keep = 99
End Interrupt

SwIe = 1
Enable(H)
b = Other()
Disable(H)
