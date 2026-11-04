Module Pinio
' Test double for `Pinio` with a model of an ST7920, graphic RAM of 32 rows x 16 words (the folded 128 x 64 module): the pins and
' the port are followed, instructions and data run on the falling edge of E and a read is prepared on the rising edge, as in
' the Sitronix V4.0 data sheet: function set with DL, RE and G, the two-byte graphic address (vertical then horizontal), two data
' bytes per word with the address advancing after the second, and a dummy read after an address is set. Never busy.
' Three interfaces, chosen with `SetMode` before the init call: 0 = 8-bit parallel; 1 = 4-bit parallel (the controller starts
' in the 8-bit mode, a function set with DL = 0 moves it to the 4-bit mode, then every byte is two E pulses, upper nibble
' first, on DB7..DB4); 2 = serial (CS = the RS pin, SID = R/W, SCLK = E: a start byte 11111 RW RS 0, then the upper and the
' lower nibble each in a byte of its own, bits sampled on the rising edge of SCLK, CS low resets the counter).
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
Dim mode As Byte
Dim dl4 As Byte
Dim nibs As Byte
Dim hold As Byte
Dim rnib As Byte
Dim rbyte As Byte
Dim sbits As Byte
Dim sreg As Byte
Dim sstage As Byte
Dim sync As Byte
Dim shi As Byte
Dim execCount As Word
Dim badSync As Byte

Public Sub Wire(ByVal rs As Byte, ByVal rw As Byte, ByVal e As Byte)
    wRs = rs
    wRw = rw
    wE = e
End Sub

Public Sub SetMode(ByVal m As Byte)
    mode = m
    re = 0
    gon = 0
    stage = 0
    vy = 0
    hx = 0
    bsel = 0
    ob = 0
    dl4 = 0
    nibs = 0
    rnib = 0
    sbits = 0
    sstage = 0
    fcount = 0
    execCount = 0
    badSync = 0
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

' 0 = RE, 1 = G, 2 = last function set, 3 = number of function sets, 4 = 1 when the controller is in the 4-bit mode,
' 5 = serial frames that were not well formed (start byte 11111 RW RS 0, four zero bits after each nibble),
' 6 = instructions and data bytes executed (low byte).
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
    ElseIf which = 4 Then
        Result = dl4
    ElseIf which = 5 Then
        Result = badSync
    ElseIf which = 6 Then
        Result = Byte(execCount And 255)
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

' One instruction (`isData` False) or data byte.
Sub Execute(ByVal isData As Boolean, ByVal v As Byte)
    Inc(execCount)
    If Not isData Then
        If (v And 224) = 32 Then
            If (v And 16) = 0 Then
                dl4 = 1
            Else
                dl4 = 0
            End If
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

Sub WriteCycle()
    If lv(wRw) <> 0 Then
        Exit
    End If
    If mode = 1 And dl4 <> 0 Then
        ' 4-bit mode: the upper nibble comes first.
        If nibs = 0 Then
            hold = lat And 240
            nibs = 1
        Else
            nibs = 0
            Execute(lv(wRs) <> 0, hold Or (lat >> 4))
        End If
    ElseIf mode = 1 Then
        ' Still in the 8-bit mode: only DB7..DB4 are wired, so a write is an instruction made of the upper nibble alone.
        If lv(wRs) = 0 Then
            Execute(False, lat And 240)
        End If
    Else
        Execute(lv(wRs) <> 0, lat)
    End If
End Sub

Sub ReadCycle()
    If lv(wRw) = 0 Then
        Exit
    End If
    If mode = 1 And dl4 <> 0 Then
        If rnib = 0 Then
            If lv(wRs) = 0 Then
                rbyte = 0
            Else
                rbyte = ob
                ob = mem(Cell())
                Advance()
            End If
            outv = rbyte And 240
            rnib = 1
        Else
            outv = (rbyte << 4) And 240
            rnib = 0
        End If
    ElseIf lv(wRs) = 0 Then
        outv = 0
    Else
        outv = ob
        ob = mem(Cell())
        Advance()
    End If
End Sub

' Serial: a rising edge of SCLK with CS high shifts in one bit.
Sub SerialClock()
    If lv(wRs) = 0 Then
        Exit
    End If
    sreg = (sreg << 1) Or lv(wRw)
    Inc(sbits)
    If sbits = 8 Then
        sbits = 0
        If sstage = 0 Then
            sync = sreg
            If (sreg And 249) <> 248 Then
                Inc(badSync)
            End If
            sstage = 1
        ElseIf sstage = 1 Then
            shi = sreg
            sstage = 2
        Else
            sstage = 0
            If (sreg And 15) <> 0 Or (shi And 15) <> 0 Then
                Inc(badSync)
            End If
            Execute((sync And 2) <> 0, (shi And 240) Or (sreg >> 4))
        End If
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
    If mode = 2 Then
        If pin = wRs And Not level Then
            sbits = 0
            sstage = 0
        End If
        If pin = wE And level And old = 0 Then
            SerialClock()
        End If
        Exit
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

Public Sub PortDigital(ByVal base As Byte)
End Sub

Public Sub PortWriteHigh(ByVal base As Byte, ByVal v As Byte)
    lat = v And 240
End Sub

Public Function PortReadHigh(ByVal base As Byte) As Byte
    Result = outv And 240
End Function

Public Sub PortDirectionHigh(ByVal base As Byte, ByVal isInput As Boolean)
End Sub

Public Sub PortDigitalHigh(ByVal base As Byte)
End Sub
