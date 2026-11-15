' expect: E-SYNTAX
' `==` compares; it does not assign.
Program T
Device = 18F27Q10
Dim a As Byte
a == 5
