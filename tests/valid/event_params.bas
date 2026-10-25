Program T
Device = 18F27Q10
Type TCb = Event(ByVal v As Byte, ByVal w As Word)
Dim Cb As TCb
Dim Tbl(2) As TCb
Event H(ByVal a As Byte, ByVal b As Word)
End Event
Cb = H
Cb(1, 2)
Tbl(1) = H
Tbl(1)(3, 4)
