Module Util
Public Dim Counter As Byte
Private Dim hidden As Byte
Public Function Twice(ByVal x As Byte) As Word
    Result = x * 2
End Function
Public Sub Bump()
    Inc(Counter)
End Sub
Public Sub Bump2()
    hidden = hidden + 1
End Sub
hidden = 5
