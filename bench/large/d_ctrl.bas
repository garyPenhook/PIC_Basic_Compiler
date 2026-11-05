' expect: K_SINK=67006
Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Const CMDS(32) As Byte = (1, 5, 10, 2, 3, 200, 4, 0, 1, 7, 33, 2, 1, 4, 99, 3, 9, 8, 2, 250, 5, 6, 1, 3, 200, 9, 1, 2, 77, 4, 4, 0)
Dim ring(16) As Byte
Dim head, tail, cnt As Byte
Dim ma(16) As Byte
Dim mb(16) As Byte
Dim mc(16) As Word
Dim rle(48) As Byte
Dim src(32) As Byte
Dim dst(32) As Byte
Dim regs(8) As Byte
Dim state, mode As Byte
Dim accum As Word
Dim sink As LongWord

Sub Push(ByVal b As Byte)
    If cnt < 16 Then
        ring(head) = b
        head = (head + 1) And 15
        cnt = cnt + 1
    End If
End Sub

Function Pop() As Byte
    Result = 0
    If cnt > 0 Then
        Result = ring(tail)
        tail = (tail + 1) And 15
        cnt = cnt - 1
    End If
End Function

Sub MatMul()
    Dim i, j, k As Byte
    Dim s As Word
    For i = 0 To 3
        For j = 0 To 3
            s = 0
            For k = 0 To 3
                s = s + ma(i * 4 + k) * mb(k * 4 + j)
            Next
            mc(i * 4 + j) = s
        Next
    Next
End Sub

Sub InitMat()
    Dim i As Byte
    For i = 0 To 15
        ma(i) = i * 3 + 1
        mb(i) = 17 - i
    Next
End Sub

Function Trace() As Word
    Dim i As Byte
    Dim t As Word
    t = 0
    For i = 0 To 3
        t = t + mc(i * 5)
    Next
    Result = t
End Function

Function Encode(ByVal n As Byte) As Byte
    Dim i, o, run, cur As Byte
    o = 0
    i = 0
    While i < n
        cur = src(i)
        run = 1
        While i + run < n
            If src(i + run) <> cur Then
                Break
            End If
            If run = 255 Then
                Break
            End If
            run = run + 1
        Wend
        rle(o) = run
        rle(o + 1) = cur
        o = o + 2
        i = i + run
    Wend
    Result = o
End Function

Function Decode(ByVal n As Byte) As Byte
    Dim i, o, k As Byte
    o = 0
    i = 0
    While i < n
        For k = 1 To rle(i)
            dst(o) = rle(i + 1)
            o = o + 1
        Next
        i = i + 2
    Wend
    Result = o
End Function

Sub MakeSrc()
    Dim i, v As Byte
    v = 3
    For i = 0 To 31
        If (i And 7) = 0 Then
            v = v + 5
        End If
        If (i And 3) = 3 Then
            v = v + 1
        End If
        src(i) = v
    Next
End Sub

Sub Exec(ByVal op As Byte, ByVal a As Byte)
    Select op
        Case 1
            regs(a And 7) = regs(a And 7) + 1
        Case 2
            regs(a And 7) = regs(a And 7) - 1
        Case 3
            regs(0) = regs(a And 7)
        Case 4
            regs(a And 7) = regs(0)
        Case 5
            regs(0) = regs(0) + a
        Case 6
            regs(0) = regs(0) Xor a
        Case 7
            regs(0) = regs(0) << 1
        Case 8
            regs(0) = regs(0) >> 1
        Case Else
            accum = accum + a
    End Select
End Sub

Sub Machine(ByVal b As Byte)
    Select state
        Case 0
            If b = 1 Then
                state = 1
            ElseIf b = 2 Then
                state = 3
            End If
        Case 1
            mode = b
            state = 2
        Case 2
            Exec(mode, b)
            state = 0
        Case 3
            accum = accum + b
            If b > 100 Then
                state = 0
            Else
                state = 4
            End If
        Case 4
            accum = accum Xor b
            state = 0
        Case Else
            state = 0
    End Select
End Sub

Function Fletcher(ByVal n As Byte) As Word
    Dim i As Byte
    Dim a, b As Word
    a = 0
    b = 0
    For i = 0 To n - 1
        a = (a + dst(i)) Mod 255
        b = (b + a) Mod 255
    Next
    Result = (b << 8) Or a
End Function

Function ParityByte(ByVal v As Byte) As Byte
    v = v Xor (v >> 4)
    v = v Xor (v >> 2)
    v = v Xor (v >> 1)
    Result = v And 1
End Function

Function RevBits(ByVal v As Byte) As Byte
    Dim r, i As Byte
    r = 0
    For i = 0 To 7
        r = (r << 1) Or (v And 1)
        v = v >> 1
    Next
    Result = r
End Function

Sub ShiftOut(ByVal v As Byte)
    Dim i As Byte
    For i = 0 To 7
        If (v And $80) <> 0 Then
            LATB = LATB Or 1
        Else
            LATB = LATB And $FE
        End If
        LATB = LATB Or 2
        LATB = LATB And $FD
        v = v << 1
    Next
End Sub

Dim i, n, m As Byte
Dim w As Word

state = 0
For i = 0 To 31
    Push(CMDS(i))
    If cnt > 12 Then
        While cnt > 4
            Machine(Pop())
        Wend
    End If
Next
While cnt > 0
    Machine(Pop())
Wend
sink = accum
For i = 0 To 7
    sink = sink + regs(i)
    ShiftOut(regs(i))
Next
InitMat()
MatMul()
sink = sink + Trace()
MakeSrc()
n = Encode(32)
m = Decode(n)
w = Fletcher(m)
sink = sink + w + n + m
For i = 0 To 31
    sink = sink + ParityByte(dst(i)) + RevBits(dst(i))
Next
