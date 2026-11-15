' expect: E-SYNTAX
' says: `End` found while the `For` on line 7 is still open
' says: note: this `For` needs its `Next` before the `End`
Program T
Device = 18F27Q10
Dim i As Byte
For i = 0 To 5
    PORTB = i
End
