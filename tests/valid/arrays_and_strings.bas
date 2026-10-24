Program T
Device = 18F27Q10
Dim a(5) As Byte
Dim s As String(10)
Dim t As String
Dim i As Byte
Dim c As Char
Const Tbl(3) As Byte = (10, 20, 30)
For i = 0 To Bound(a)
    a(i) = Tbl(1) + i
Next
s = "hello"
t = s + " world"
c = s(0)
c = "x"
If s = "hello" Then
    i = 1
EndIf
If c = "x" Then
    i = 2
EndIf
