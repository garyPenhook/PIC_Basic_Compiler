' expect: EVI_HITS=1 EVI_GOT=9 EVI_B=55 EVI_CMP=1
' An event called from an interrupt handler needs no Save: the call saves the working registers and
' every frame it reaches. The handler's local `k` shares storage with the main-line `z` (they are
' never live together by the call graph), and `z` must come back unharmed.
Program Evi
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
    SwIf = 0
    Inc(hits)
    Cb(9)
End Interrupt

Cb = OnHit
If Cb = OnHit Then
    cmp = 1
EndIf
SwIe = 1
Enable(H)
b = Other()
Disable(H)
