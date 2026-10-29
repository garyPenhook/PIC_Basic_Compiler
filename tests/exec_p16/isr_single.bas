' expect: ISR_OK=1 ISR_N=300 ISR_R1=0 ISR_HITS=300
' One handler (the only vector of the enhanced mid-range core), driven by a free-running Timer0 whose period the handler
' varies, so
' the interrupts land at many different points of the main program. Whatever the main
' program holds in WREG, STATUS, BSR, FSR0/1, the scratch registers must survive,
' and a routine the handler calls (inside Save) must not corrupt the main program's frames.
Program Isr
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Dim T0If As PIR0.5
Dim T0Ie As PIE0.5
Dim n As Word
Dim hits As Word
Dim ok As Byte
Dim r1 As LongWord
Dim r2 As LongWord
Dim hv(4) As Word
Dim arr(8) As Byte

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
        TMR0H = 200 + (hits And 31)
    Else
        ' Stop the timer and its interrupt: the handler multiplies in software here, so it can be longer than a timer
        ' period, and a flag raised while it runs would be taken after the return.
        T0CON0 = 0
        T0Ie = 0
    End If
End Interrupt

T0Ie = 1
Enable(Tick)
r1 = Work()
n = 0
T0CON1 = 65
T0CON0 = 128
r2 = Work()
' The handler stops the timer after the last hit. One byte cannot be read half-updated, which
' `While hits < 300` could (the handler may land between the two byte reads).
While T0CON0 <> 0
Wend
Disable(Tick)
n = hits
If r1 = r2 Then
    ok = 1
End If
r1 = 0
