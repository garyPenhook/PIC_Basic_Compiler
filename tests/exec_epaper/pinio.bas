Module Pinio
' Test double for `Pinio` with a model of an SSD1680 (Rev 0.14) e-paper driver on 4-wire SPI: D/C# says command or data (sampled at
' each byte), CS# must be low for it (when wired), a command's data bytes are decoded by command (01h 11h 44h 45h 4Eh 4Fh 3Ch 21h
' 18h 22h 10h), 12h and 20h raise BUSY for three polls, and writes to RAM 24h / 26h follow the window and the address counter as in
' 8.3 - 8.6 with the data entry mode of the init code (X increment, Y decrement). Only the RAM rows Y 295..256 are kept (40 rows of 16
' bytes per plane); writes elsewhere are counted in `lost`.
Dim lv(24) As Byte
Dim wDc As Byte
Dim wCs As Byte
Dim wRes As Byte
Dim wBusy As Byte
Dim memBw(640) As Byte
Dim memRd(640) As Byte
Dim cmd As Byte
Dim argN As Byte
Dim reg(8) As Byte
Dim xs As Byte
Dim xe As Byte
Dim ysL As Byte
Dim ysH As Byte
Dim yeL As Byte
Dim yeH As Byte
Dim xc As Byte
Dim yc As Word
Dim drv0 As Byte
Dim drv1 As Byte
Dim drv2 As Byte
Dim entry As Byte
Dim border As Byte
Dim duc0 As Byte
Dim duc1 As Byte
Dim temp As Byte
Dim upd As Byte
Dim lastUpd As Byte
Dim sleepMode As Byte
Dim swres As Byte
Dim hwres As Byte
Dim busyLeft As Byte
Dim nBw As Word
Dim nRd As Word
Dim lost As Word
Dim badCs As Byte
Dim cmds As Word

Public Sub Wire(ByVal dc As Byte, ByVal cs As Byte, ByVal res As Byte, ByVal busy As Byte)
    Dim i As Byte
    wDc = dc
    wCs = cs
    wRes = res
    wBusy = busy
    i = 0
    While i < 24
        lv(i) = 1
        Inc(i)
    Wend
    cmd = 0
    nBw = 0
    nRd = 0
    lost = 0
    badCs = 0
    cmds = 0
    swres = 0
    hwres = 0
    upd = 0
    sleepMode = 0
    busyLeft = 0
End Sub

Public Sub Fill()
    Dim i As Word
    i = 0
    While i < 640
        memBw(i) = 0
        memRd(i) = 0
        Inc(i)
    Wend
End Sub

' RAM byte of plane `plane` at RAM Y `ry` (256..295) and X byte `xb`.
Public Function Ram(ByVal plane As Byte, ByVal ry As Word, ByVal xb As Byte) As Byte
    Dim i As Word
    i = (295 - ry) * 16 + xb
    If plane = 0 Then
        Result = memBw(i)
    Else
        Result = memRd(i)
    End If
End Function

' 0 drv0, 1 drv1, 2 drv2, 3 entry, 4 xs, 5 xe, 6 ys low, 7 ys high, 8 ye low, 9 ye high, 10 border, 11 duc0, 12 duc1, 13 temp,
' 14 updates, 15 last 22h argument, 16 sleep mode, 17 software resets, 18 hardware resets, 19 bytes to plane 0 (low), 20 bytes to
' plane 1 (low), 21 bytes lost (low), 22 bad CS count, 23 commands, 24 x counter, 25 bytes to plane 0 (high), 26 bytes to plane 1
' (high), 27 y counter low
Public Function State(ByVal which As Byte) As Byte
    Result = 0
    If which = 0 Then
        Result = drv0
    ElseIf which = 1 Then
        Result = drv1
    ElseIf which = 2 Then
        Result = drv2
    ElseIf which = 3 Then
        Result = entry
    ElseIf which = 4 Then
        Result = xs
    ElseIf which = 5 Then
        Result = xe
    ElseIf which = 6 Then
        Result = ysL
    ElseIf which = 7 Then
        Result = ysH
    ElseIf which = 8 Then
        Result = yeL
    ElseIf which = 9 Then
        Result = yeH
    ElseIf which = 10 Then
        Result = border
    ElseIf which = 11 Then
        Result = duc0
    ElseIf which = 12 Then
        Result = duc1
    ElseIf which = 13 Then
        Result = temp
    ElseIf which = 14 Then
        Result = upd
    ElseIf which = 15 Then
        Result = lastUpd
    ElseIf which = 16 Then
        Result = sleepMode
    ElseIf which = 17 Then
        Result = swres
    ElseIf which = 18 Then
        Result = hwres
    ElseIf which = 19 Then
        Result = Byte(nBw And 255)
    ElseIf which = 20 Then
        Result = Byte(nRd And 255)
    ElseIf which = 21 Then
        Result = Byte(lost And 255)
    ElseIf which = 22 Then
        Result = badCs
    ElseIf which = 23 Then
        Result = Byte(cmds And 255)
    ElseIf which = 24 Then
        Result = xc
    ElseIf which = 25 Then
        Result = Byte(nBw >> 8)
    ElseIf which = 26 Then
        Result = Byte(nRd >> 8)
    ElseIf which = 27 Then
        Result = Byte(yc And 255)
    End If
End Function

Sub Store(ByVal plane As Byte, ByVal v As Byte)
    Dim i As Word
    If yc >= 256 And yc <= 295 And xc < 16 Then
        i = (295 - yc) * 16 + xc
        If plane = 0 Then
            memBw(i) = v
        Else
            memRd(i) = v
        End If
    Else
        Inc(lost)
    End If
    If plane = 0 Then
        Inc(nBw)
    Else
        Inc(nRd)
    End If
    If xc >= xe Then
        xc = xs
        yc = yc - 1
    Else
        Inc(xc)
    End If
End Sub

Sub Data(ByVal v As Byte)
    If cmd = 1 Then
        If argN = 0 Then
            drv0 = v
        ElseIf argN = 1 Then
            drv1 = v
        Else
            drv2 = v
        End If
    ElseIf cmd = 17 Then
        entry = v
    ElseIf cmd = 68 Then
        If argN = 0 Then
            xs = v
        Else
            xe = v
        End If
    ElseIf cmd = 69 Then
        If argN = 0 Then
            ysL = v
        ElseIf argN = 1 Then
            ysH = v
        ElseIf argN = 2 Then
            yeL = v
        Else
            yeH = v
        End If
    ElseIf cmd = 78 Then
        xc = v
    ElseIf cmd = 79 Then
        If argN = 0 Then
            yc = v
        Else
            yc = yc + Word(v) * 256
        End If
    ElseIf cmd = 60 Then
        border = v
    ElseIf cmd = 33 Then
        If argN = 0 Then
            duc0 = v
        Else
            duc1 = v
        End If
    ElseIf cmd = 24 Then
        temp = v
    ElseIf cmd = 34 Then
        lastUpd = v
    ElseIf cmd = 16 Then
        sleepMode = v
    ElseIf cmd = 36 Then
        Store(0, v)
    ElseIf cmd = 38 Then
        Store(1, v)
    End If
    If argN < 255 Then
        Inc(argN)
    End If
End Sub

Public Sub Send(ByVal v As Byte)
    If wCs <> 255 Then
        If lv(wCs) <> 0 Then
            Inc(badCs)
        End If
    End If
    If lv(wDc) = 0 Then
        cmd = v
        argN = 0
        Inc(cmds)
        If v = 18 Then
            Inc(swres)
            busyLeft = 3
        ElseIf v = 32 Then
            Inc(upd)
            busyLeft = 3
        End If
    Else
        Data(v)
    End If
End Sub

Public Function PinOk(ByVal pin As Byte) As Boolean
    Result = pin < 24
End Function

Public Sub PinSet(ByVal pin As Byte, ByVal level As Boolean)
    If pin = wRes And pin < 24 Then
        If lv(pin) <> 0 And Not level Then
            Inc(hwres)
        End If
    End If
    If level Then
        lv(pin) = 1
    Else
        lv(pin) = 0
    End If
End Sub

Public Sub PinOutput(ByVal pin As Byte)
End Sub

Public Sub PinInput(ByVal pin As Byte)
End Sub

Public Function PinGet(ByVal pin As Byte) As Boolean
    Result = False
    If pin = wBusy Then
        If busyLeft > 0 Then
            Dec(busyLeft)
            Result = True
        End If
    End If
End Function
