Module Pinio
' Test double for `Pinio` with a model of a T6963C (display RAM of 1152 bytes, the rest of its address space only counted): the
' pins and the 8-bit port are followed, a bus cycle runs on the falling edge of CE (WR low = write, RD low = read), and
' commands execute as in the Toshiba data sheet (2002-01-07): data first then the command, Address Pointer, Control Words,
' Mode Set, Display Mode, Data Auto Write, Data Write / Read, Bit Set / Reset. The status is always ready.
Dim lv(24) As Byte
Dim lat As Byte
Dim outv As Byte
Dim mem(1152) As Byte
Dim d1 As Byte
Dim d2 As Byte
Dim n As Byte
Dim adp As Word
Dim auto As Byte
Dim lastRead As Byte
Dim ghome As Word
Dim garea As Byte
Dim thome As Word
Dim tarea As Byte
Dim offs As Byte
Dim modeset As Byte
Dim disp As Byte
Dim curx As Byte
Dim cury As Byte
Dim lastCmd As Byte
Dim hiCnt As Byte
Dim hiMin As Word
Dim hiSum As Word
Dim wCd As Byte
Dim wWr As Byte
Dim wRd As Byte
Dim wCe As Byte

Public Sub Wire(ByVal cd As Byte, ByVal wr As Byte, ByVal rd As Byte, ByVal ce As Byte)
    wCd = cd
    wWr = wr
    wRd = rd
    wCe = ce
    hiMin = 65535
End Sub

Public Sub Fill(ByVal v As Byte)
    Dim i As Word
    i = 0
    While i < 1152
        mem(i) = v
        Inc(i)
    Wend
End Sub

Public Function Ram(ByVal i As Word) As Byte
    Result = mem(i)
End Function

' Set bits in the graphic area (0..1023).
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

Public Function Reg(ByVal which As Byte) As Word
    Result = 0
    If which = 0 Then
        Result = ghome
    ElseIf which = 1 Then
        Result = garea
    ElseIf which = 2 Then
        Result = thome
    ElseIf which = 3 Then
        Result = tarea
    ElseIf which = 4 Then
        Result = offs
    ElseIf which = 5 Then
        Result = modeset
    ElseIf which = 6 Then
        Result = disp
    ElseIf which = 7 Then
        Result = curx
    ElseIf which = 8 Then
        Result = cury
    ElseIf which = 9 Then
        Result = lastCmd
    ElseIf which = 10 Then
        Result = hiCnt
    ElseIf which = 11 Then
        Result = hiMin
    ElseIf which = 12 Then
        Result = hiSum
    ElseIf which = 13 Then
        Result = adp
    End If
End Function

Sub Store(ByVal v As Byte)
    If adp < 1152 Then
        mem(adp) = v
    Else
        Inc(hiCnt)
        hiSum = hiSum + v
        If adp < hiMin Then
            hiMin = adp
        End If
    End If
End Sub

Sub Command(ByVal c As Byte)
    Dim b As Byte
    lastCmd = c
    If c = 36 Then
        adp = Word(d1) + Word(d2) * 256
    ElseIf c = 33 Then
        curx = d1
        cury = d2
    ElseIf c = 34 Then
        offs = d1
    ElseIf c = 64 Then
        thome = Word(d1) + Word(d2) * 256
    ElseIf c = 65 Then
        tarea = d1
    ElseIf c = 66 Then
        ghome = Word(d1) + Word(d2) * 256
    ElseIf c = 67 Then
        garea = d1
    ElseIf c >= 128 And c < 144 Then
        modeset = c
    ElseIf c >= 144 And c < 160 Then
        disp = c
    ElseIf c = 176 Then
        auto = 1
    ElseIf c = 178 Then
        auto = 0
    ElseIf c = 192 Then
        Store(d1)
        adp = adp + 1
    ElseIf c = 196 Then
        Store(d1)
    ElseIf c = 197 Then
        lastRead = 197
    ElseIf c >= 240 Then
        b = 1 << (c And 7)
        If adp < 1152 Then
            If (c And 8) <> 0 Then
                mem(adp) = mem(adp) Or b
            Else
                mem(adp) = mem(adp) And (b Xor 255)
            End If
        End If
    End If
    n = 0
End Sub

Sub DataIn(ByVal v As Byte)
    If auto = 1 Then
        Store(v)
        adp = adp + 1
    ElseIf n = 0 Then
        d1 = v
        n = 1
    ElseIf n = 1 Then
        d2 = v
        n = 2
    End If
End Sub

Sub Cycle()
    If lv(wWr) = 0 Then
        If lv(wCd) = 1 Then
            Command(lat)
        Else
            DataIn(lat)
        End If
    ElseIf lv(wRd) = 0 Then
        If lv(wCd) = 1 Then
            outv = 15
        Else
            outv = 0
            If adp < 1152 Then
                outv = mem(adp)
            End If
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
    If pin = wCe And Not level And old = 1 Then
        Cycle()
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
