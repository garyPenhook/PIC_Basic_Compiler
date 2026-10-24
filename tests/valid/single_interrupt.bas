Program T
Device = 18F27Q10
Dim ticks As Word
Interrupt Only()
    Inc(ticks)
End Interrupt
Enable(Only)
