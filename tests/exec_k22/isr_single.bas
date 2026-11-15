' expect: ISR_OK=1 ISR_N=300 ISR_R1=0 ISR_HITS=300
' One handler, no priorities (IPEN = 0), driven by a free-running Timer0 whose period the handler
' varies, so the interrupts land at many different points of the main program. Whatever the main
' program holds in WREG, STATUS, BSR, FSR0/1, TBLPTR, PROD and the scratch registers must survive,
' and a routine the handler calls (inside Save) must not corrupt the main program's frames.
' PIC18(L)F2x/4xK22 version: TMR0IF/TMR0IE are INTCON bits 2 and 5 (DS40001412H Register 9-1 p.109), and the older Timer0 has no
' period register (Register 11-1 p.154), so the handler varies the period by reloading TMR0L. T0CON = 192: on, 8-bit, FOSC/4, 1:2.
Program Isr
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Dim T0If As INTCON.2
Dim T0Ie As INTCON.5
Dim n As Word
Dim hits As Word
Dim ok As Byte
Dim r1 As LongWord
Dim r2 As LongWord
Dim hv(4) As Word
Dim arr(8) As Byte
Dim s As String(16)

Function Mix(ByVal x As Word) As Word
    Dim t As Word
    t = x * 3
    Result = t + 1
End Function

Function Work() As LongWord
    Dim i As Byte
    Dim acc As LongWord
    Dim w As Word
    Dim k As Byte
    s = "abc"
    s = s + "def"
    acc = 0
    For i = 0 To 7
        arr(i) = i * 7
    Next
    For i = 0 To 7
        w = arr(i)
        acc = acc + w * 300 + Mix(w)
        k = i
        acc = acc + arr(k) / 3
    Next
    If s = "abcdef" Then
        acc = acc + 1000
    End If
    acc = acc Xor (acc >> 3)
    Result = acc
End Function

Interrupt Tick()
    Dim j As Byte
    Dim p As Word
    T0If = 0
    Inc(hits)
    hv(hits And 3) = hits * 5
    p = hv(hits And 3) * 7
    j = Byte(p And 255)
    Save(0, Mix)
        p = Mix(p)
    Restore
    If hits < 300 Then
        TMR0L = 55 - (hits And 31)
    Else
        T0CON = 0
    End If
End Interrupt

T0Ie = 1
Enable(Tick)
r1 = Work()
n = 0
T0CON = 192
r2 = Work()
' The handler stops the timer after the last hit. One byte cannot be read half-updated, which
' `While hits < 300` could (the handler may land between the two byte reads).
While T0CON <> 0
Wend
Disable(Tick)
n = hits
If r1 = r2 Then
    ok = 1
End If
r1 = 0
