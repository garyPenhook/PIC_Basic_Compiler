' expect: E-UNDECLARED
' says: help: `SerialInit` is in the library module `serial`: add `Include "serial"` after `Device`
Program T
Device = 18F27Q10
SerialInit(9600)
End
