' expect: E-FORWARD
Program T
Device = 18F27Q10
Declare Function F(ByVal n As Byte) As Byte
Function F(ByVal n As Byte) As Word
    Result = n
End Function
