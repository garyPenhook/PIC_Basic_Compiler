Program T
Device = 18F27Q10
Type TCb = Event()
Dim Cb As TCb
Event H()
End Event
Interrupt I()
    Save(0)
        Cb()
    Restore
End Interrupt
Cb = H
Enable(I)
