' expect: ISS_HITS=1 ISS_A=8 ISS_B=55 ISS_KEEP=77
' Save … Restore: a saved variable comes back whichever way the block is left (end, Continue,
' Break, Exit), and a routine the handler calls inside Save leaves the frame it shares with a
' main-line routine (Bump's `y` and Other's `z` overlay) as it found it.
Program Iss
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
