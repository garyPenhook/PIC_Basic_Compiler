' expect: GSI_HITS=1 GSI_GOT=9 GSI_B=55 GSI_CMP=1 GSI_Q=7
' An event called from an interrupt handler needs no Save: the call saves the working registers and
' every frame it reaches. The handler's local `k` shares storage with the main-line `z` (they are
' never live together by the call graph), and `z` must come back unharmed.
Program Gsi
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#if _has(PIR3.TMR1IF)
Dim SwIf As PIR3.4
Dim SwIe As PIE3.4
#else
Dim SwIf As PIR0.0
Dim SwIe As PIE0.0
#endif
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
