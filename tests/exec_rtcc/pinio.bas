Module Pinio
' Test double for `Pinio` used with the SPI chip model: every pin exists, and a falling edge on the pin given to
' PinSet is recorded so the chip model can see the start of each chip select cycle.
Dim fell As Boolean

Public Function PinOk(ByVal pin As Byte) As Boolean
    Result = pin < 24
End Function

Public Sub PinSet(ByVal pin As Byte, ByVal level As Boolean)
    If Not level Then
        fell = True
    End If
End Sub

Public Sub PinOutput(ByVal pin As Byte)
End Sub

Public Sub PinInput(ByVal pin As Byte)
End Sub

Public Function PinGet(ByVal pin As Byte) As Boolean
    Result = False
End Function

' True once after each falling edge (the start of a chip select cycle).
Public Function TakeFall() As Boolean
    Result = fell
    fell = False
End Function
