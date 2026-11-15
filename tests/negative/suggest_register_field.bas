' expect: E-NOMEMBER
' says: register `INTCON` has no bit or field `GIEE`
' says: help: did you mean `GIE`?
' says: note: the fields of T0CON0 are
Program T
Device = 18F27Q10
INTCON.GIEE = 1
T0CON0.XYZ = 1
End
