' expect: E-ISR-CALL
Program T
Device = 18F27Q10
Type TCb = Event()
Dim Cb As TCb
Event H()
End Event
Interrupt I()
    Cb()
End Interrupt
