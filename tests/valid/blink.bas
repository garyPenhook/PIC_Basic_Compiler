Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim LED As PORTB.0
Const cDelay = 500
Sub Pulse(ByVal n As Byte, ByVal ms As Word = 100)
    Dim i As Byte
    For i = 1 To n
        High(LED)
        DelayMS(ms)
        Low(LED)
        DelayMS(ms)
    Next
End Sub
Output(LED)
Pulse(3)
Do
    Toggle(LED)
    DelayMS(cDelay)
Loop
