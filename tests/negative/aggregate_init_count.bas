' expect: E-DIM-ARRAY E-DIM-ARRAY
Program T
Device = 18F27Q10
Structure Pt
    x As Byte
    tab(2) As Byte
End Structure
Dim p As Pt = (1, 2)
Dim names(2) As String(4) = ("a", "b", "c")
