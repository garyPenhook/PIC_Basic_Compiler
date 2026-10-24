' expect: E-ISR-CALL
Program T
Device = 18F27Q10
Sub S()
End Sub
Interrupt I(ipHigh)
    S()
End Interrupt
