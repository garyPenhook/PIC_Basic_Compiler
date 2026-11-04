Module Pinio
' Test double for `Pinio` with a model of two KS0108 / S6B0108 chips (128 x 64): the pins, the 8-bit port and the edges of E are
' followed, instructions and data are executed as the S6B0108 data sheet describes them (read = dummy read first, Y address
' advances after every read and write). Everything is never busy.
Dim lv(24) As Byte
Dim lat As Byte
Dim outv As Byte
Dim mem(1024) As Byte
Dim yp(2) As Byte
Dim pg(2) As Byte
Dim ob(2) As Byte
Dim dsp(2) As Byte
Dim wRs As Byte
Dim wRw As Byte
Dim wEn As Byte
Dim wC1 As Byte
Dim wC2 As Byte
Dim wHigh As Byte

' The pins glcd will be told to use.
Public Sub Wire(ByVal rs As Byte, ByVal rw As Byte, ByVal en As Byte, ByVal c1 As Byte, ByVal c2 As Byte, ByVal act As Byte)
    wRs = rs
    wRw = rw
    wEn = en
    wC1 = c1
    wC2 = c2
    wHigh = act
End Sub

Public Sub Fill(ByVal v As Byte)
    Dim i As Word
    i = 0
    While i < 1024
        mem(i) = v
        Inc(i)
    Wend
End Sub

Public Function Ram(ByVal i As Word) As Byte
    Result = mem(i)
End Function

Public Function DispOn(ByVal c As Byte) As Byte
    Result = dsp(c)
End Function

' Number of set bits in the display memory.
Public Function Ones() As Word
    Dim i As Word
    Dim v As Byte
    Result = 0
    i = 0
    While i < 1024
        v = mem(i)
        While v <> 0
            Result = Result + (v And 1)
            v = v >> 1
        Wend
        Inc(i)
    Wend
End Function

' Chip selected by the CS lines: 0, 1, or 2 for none.
Function Sel() As Byte
    Result = 2
    If lv(wC1) = wHigh Then
        Result = 0
    ElseIf lv(wC2) = wHigh Then
        Result = 1
    End If
End Function

Function Cell(ByVal c As Byte) As Word
    Result = Word(c) * 512 + Word(pg(c)) * 64 + yp(c)
End Function

Sub WriteCycle()
    Dim c As Byte
    Dim v As Byte
    c = Sel()
    If c = 2 Or lv(wRw) <> 0 Then
        Exit
    End If
    v = lat
    If lv(wRs) = 0 Then
        If v >= 62 And v < 64 Then
            dsp(c) = v And 1
        ElseIf v >= 64 And v < 128 Then
            yp(c) = v And 63
        ElseIf v >= 184 And v < 192 Then
            pg(c) = v And 7
        End If
    Else
        mem(Cell(c)) = v
        yp(c) = (yp(c) + 1) And 63
    End If
End Sub

Sub ReadCycle()
    Dim c As Byte
    c = Sel()
    If c = 2 Or lv(wRw) = 0 Then
        Exit
    End If
    If lv(wRs) = 0 Then
        outv = 0
    Else
        outv = ob(c)
        ob(c) = mem(Cell(c))
        yp(c) = (yp(c) + 1) And 63
    End If
End Sub

Public Function PinOk(ByVal pin As Byte) As Boolean
    Result = pin < 24
End Function

Public Sub PinSet(ByVal pin As Byte, ByVal level As Boolean)
    Dim old As Byte
    old = lv(pin)
    If level Then
        lv(pin) = 1
    Else
        lv(pin) = 0
    End If
    If pin = wEn Then
        If level And old = 0 Then
            ReadCycle()
        End If
        If Not level And old = 1 Then
            WriteCycle()
        End If
    End If
End Sub

Public Sub PinOutput(ByVal pin As Byte)
End Sub

Public Sub PinInput(ByVal pin As Byte)
End Sub

Public Function PinGet(ByVal pin As Byte) As Boolean
    Result = lv(pin) <> 0
End Function

Public Sub PortWrite(ByVal base As Byte, ByVal v As Byte)
    lat = v
End Sub

Public Function PortRead(ByVal base As Byte) As Byte
    Result = outv
End Function

Public Sub PortDirection(ByVal base As Byte, ByVal isInput As Boolean)
End Sub

Public Sub PortDigital(ByVal base As Byte)
End Sub

Public Sub PortDigitalHigh(ByVal base As Byte)
End Sub

Public Sub PortDirectionHigh(ByVal base As Byte, ByVal isInput As Boolean)
End Sub

Public Sub PortWriteHigh(ByVal base As Byte, ByVal v As Byte)
End Sub

Public Function PortReadHigh(ByVal base As Byte) As Byte
    Result = 0
End Function
