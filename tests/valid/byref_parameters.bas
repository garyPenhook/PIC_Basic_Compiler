Program T
Device = 18F27Q10
Sub Fill(ByRef a() As Byte, ByVal v As Byte)
    Dim i As Word
    For i = 0 To Bound(a)
        a(i) = v
    Next
End Sub
Sub Swap(ByRef x As Byte, ByRef y As Byte)
    Dim t As Byte
    t = x
    x = y
    y = t
End Sub
Sub Show(ByRefConst msg As String)
End Sub
Const Names(2) As Byte = (1, 2)
Dim buf(8) As Byte
Dim p As Byte
Dim q As Byte
Fill(buf, 0)
Swap(p, q)
Show("hello")
