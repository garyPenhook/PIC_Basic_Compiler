Program T
Device = 18F27Q10
Function Add(ByVal x As Byte, ByVal y As Byte) As Word
    Add = x + y
End Function
Function Sq(ByVal x As Byte) As Word
    Result = x * x
End Function
Private Sub Hello()
    Exit
End Sub
Inline Function Zero() As Byte
    Result = 0
End Function
Dim w As Word
Dim b As Byte
w = Add(1, 2) + Sq(3)
b = Zero
Hello
Hello()
