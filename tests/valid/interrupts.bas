Program T
Device = 18F27Q10
Dim ticks As Word
Dim flag As Boolean
Sub Helper()
    flag = True
End Sub
Interrupt Timer(ipHigh)
    Inc(ticks)
    Save(0, Helper)
        Helper()
    Restore
End Interrupt
Interrupt Serial(ipLow)
    flag = False
End Interrupt
Enable(Timer)
Enable(Serial)
Disable(Serial)
