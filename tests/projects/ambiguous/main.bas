' expect: E-AMBIG
Program Main
Device = 18F27Q10
Include "M1"
Include "M2"
Dim b As Byte
b = Value
b = M1.Value + M2.Value
