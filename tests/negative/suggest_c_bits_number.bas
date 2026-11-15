' expect: E-UNDECLARED
' says: write `INTCON.7`
Program T
Device = 18F27Q10
INTCONbits.7 = 1
End
