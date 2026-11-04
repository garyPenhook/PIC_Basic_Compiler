Module Pinio
' Test double for `Pinio` with a model of an ST7920 in 8-bit parallel mode, graphic RAM of 32 rows x 16 words (the folded 128 x 64
' module): the pins and the 8-bit port are followed, instructions and data run on the falling edge of E and a read is
' prepared on the rising edge, as in the Sitronix V4.0 data sheet: function set with RE and G, the two-byte graphic address
' (vertical then horizontal), two data bytes per word with the address advancing after the second, and a dummy read after
' an address is set. Never busy.
Dim lv(24) As Byte
Dim lat As Byte
Dim outv As Byte
Dim mem(1024) As Byte
Dim re As Byte
Dim gon As Byte
Dim stage As Byte
Dim vy As Byte
Dim hx As Byte
Dim bsel As Byte
Dim ob As Byte
Dim fcount As Byte
Dim lastFn As Byte
Dim wRs As Byte
Dim wRw As Byte
Dim wE As Byte

Public Sub Wire(ByVal rs As Byte, ByVal rw As Byte, ByVal e As Byte)
    wRs = rs
    wRw = rw
    wE = e
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

' 0 = RE, 1 = G, 2 = last function set, 3 = number of function sets.
Public Function State(ByVal which As Byte) As Byte
    Result = 0
    If which = 0 Then
        Result = re
    ElseIf which = 1 Then
        Result = gon
    ElseIf which = 2 Then
        Result = lastFn
    ElseIf which = 3 Then
        Result = fcount
    End If
End Function

Function Cell() As Word
    Result = Word(vy) * 32 + Word(hx) * 2 + bsel
End Function

Sub Advance()
    If bsel = 0 Then
        bsel = 1
    Else
        bsel = 0
        hx = (hx + 1) And 15
    End If
End Sub

Sub WriteCycle()
    Dim v As Byte
    If lv(wRw) <> 0 Then
        Exit
    End If
    v = lat
    If lv(wRs) = 0 Then
        If (v And 248) = 48 Then
            re = (v >> 2) And 1
            If re = 1 Then
                gon = (v >> 1) And 1
            End If
            lastFn = v
            Inc(fcount)
        ElseIf re = 1 And (v And 128) <> 0 Then
            If stage = 0 Then
                vy = v And 31
                stage = 1
            Else
                hx = v And 15
                bsel = 0
                stage = 0
            End If
        End If
    Else
        mem(Cell()) = v
        Advance()
    End If
End Sub

Sub ReadCycle()
    If lv(wRw) = 0 Then
        Exit
    End If
    If lv(wRs) = 0 Then
        outv = 0
    Else
        outv = ob
        ob = mem(Cell())
        Advance()
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
    If pin = wE Then
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
