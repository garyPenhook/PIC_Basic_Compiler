' expect: GSI_HITS=1 GSI_GOT=9 GSI_B=55 GSI_CMP=1 GSI_Q=7
' An event called from an interrupt handler needs no Save: the call saves the working registers and
' every frame it reaches. The handler's local `k` shares storage with the main-line `z` (they are
' never live together by the call graph), and `z` must come back unharmed.
' PIC18(L)F2x/4xK22 version of tests/exec/gosub_isr.bas: Timer0's flag, enable and priority are INTCON bits 2, 5 and INTCON2 bit 2, the
' software-raised interrupt is INT0 (INTCON bits 1 and 4, always high priority), and Timer0 has no period register, so TMR0L is reloaded
' (DS40001412H Registers 9-1, 9-2 p.109-110, 11-1 p.154). T0CON = 192: on, 8-bit, FOSC/4, 1:2.
Program Gsi
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Dim SwIf As INTCON.1
Dim SwIe As INTCON.4
Type TCb = Event(ByVal v As Byte)
Dim Cb As TCb
Volatile Dim hits As Byte
Volatile Dim got As Byte
Volatile Dim q As Byte
Volatile Dim b As Byte
Volatile Dim cmp As Byte

Event OnHit(ByVal v As Byte)
    Dim k As Byte
    k = v + v
    got = k - v
End Event

Function Other() As Byte
    Dim z As Byte
    z = 55
    SwIf = 1
    While hits < 1
    Wend
    Result = z
End Function

Interrupt H()
    Dim j As Byte
    SwIf = 0
    j = 1
    GoSub Add3
    GoSub Add3
    q = j
    Inc(hits)
    Cb(9)
    Exit
Add3:
    j = j + 3
    Return
End Interrupt

Cb = OnHit
If Cb = OnHit Then
    cmp = 1
EndIf
SwIe = 1
Enable(H)
b = Other()
Disable(H)
