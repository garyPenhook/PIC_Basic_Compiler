' expect: E-UNDECLARED
' says: write `INTCON.GIE`, not `INTCONbits.GIE`
Program T
Device = 18F27Q10
INTCONbits.GIE = 1
End
