' expect: LPM_E1=0 LPM_E2=0 LPM_E3=0 LPM_E4=0 LPM_E5=0 LPM_E6=0 LPM_E7=0 LPM_E8=0 LPM_DONE=1
' Runs the `Pulse`, `Irremote` and `X10` routines against a model of the pins (the `pinio.bas` next to this file replaces the pin
' driver; see its header): X-10 frames are sent and played back through `Xin`, a Sony frame is decoded from a waveform in polls,
' pulse widths are measured from waveforms, and the number of pin writes of the tone and servo routines is counted.
Program Lpm
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pinio"
Include "pulse"
Include "irremote"
Include "x10"
Dim e1 As Byte
Dim e2 As Byte
Dim e3 As Byte
Dim e4 As Byte
Dim e5 As Byte
Dim e6 As Byte
Dim e7 As Byte
Dim e8 As Byte
Dim done As Byte
Dim v As Word
Dim ok As Boolean
Dim i As Byte
Dim n As Byte

Sub Chk(ByRef e As Byte, ByVal got As Word, ByVal want As Word)
    If got <> want Then
        Inc(e)
    End If
End Sub

Sub ChkB(ByRef e As Byte, ByVal got As Boolean, ByVal want As Boolean)
    If got <> want Then
        Inc(e)
    End If
End Sub

' A line for `RC5In`: idle high, then the falling edge (the middle of the first start bit, one poll), then the 13 samples
' of the frame, one poll each, a 1 being low. `w` holds the 13 bits, start 2 in bit 12, then toggle, 5 system bits, 6 command bits.
Sub Rc5Wave(ByVal w As Word)
    Dim k As Byte
    Dim run As Word
    Dim isLow As Boolean
    Dim b As Boolean
    Pinio.WaveBegin()
    Pinio.WaveAdd(5)
    isLow = True
    run = 1
    For k = 0 To 12
        b = ((w >> (12 - k)) And 1) = 1
        If b = isLow Then
            run = run + 1
        Else
            Pinio.WaveAdd(run)
            isLow = b
            run = 1
        End If
    Next
    Pinio.WaveAdd(run)
    Pinio.WaveAdd(5)
    Pinio.WaveStart()
End Sub

' X-10: the code table, one frame on the line, and a round trip through Xin.
For i = 0 To 15
    Chk(e1, X10.NumberOf(X10.CodeOf(i)), i)
Next
Chk(e1, X10.CodeOf(0), 6)
Chk(e1, X10.CodeOf(1), 14)
Chk(e1, X10.CodeOf(12), 0)
Chk(e1, X10.CodeOf(15), 12)
Pinio.ClearBursts()
ok = X10.Xout(8, 9, 1, X10.UnitOn, 2)
ChkB(e2, ok, True)
' two frames of 3 start bursts and 9 bursts for the 9 bits: 24
Chk(e2, Pinio.Bursts(), 24)
' start code 1110, then the house code B = 1110 as bit, complement: 10 10 10 01
ChkB(e2, Pinio.Burst(1) And Pinio.Burst(2) And Pinio.Burst(3), True)
ChkB(e2, Pinio.Burst(4), False)
ChkB(e2, Pinio.Burst(5), True)
ChkB(e2, Pinio.Burst(6), False)
ChkB(e2, Pinio.Burst(11), False)
ChkB(e2, Pinio.Burst(12), True)
Pinio.Replay()
v = 0
ok = X10.Xin(8, 9, 100, v)
ChkB(e3, ok, True)
Chk(e3, v, 274)
Pinio.ClearBursts()
ok = X10.Xout(8, 9, 15, 5, 2)
Pinio.Replay()
ok = X10.Xin(8, 9, 100, v)
ChkB(e3, ok, True)
Chk(e3, v, 3845)
Pinio.ClearBursts()
ok = X10.Xout(8, 9, 12, X10.DimIt, 3)
ChkB(e3, ok, True)
Pinio.Replay()
ok = X10.Xin(8, 9, 100, v)
Chk(e3, v, 3102)
' Refused: a house code above 15, equal pins, and no frame within the timeout
ChkB(e4, X10.Xout(8, 9, 16, 0, 2), False)
ChkB(e4, X10.Xout(8, 8, 0, 0, 2), False)
Pinio.ClearBursts()
ChkB(e4, X10.Xin(8, 9, 5, v), False)

' Sony: header 2.4 ms, then 12 bits LSB first: command 21, system 12.
Pinio.WaveBegin()
Pinio.WaveAdd(500)
Pinio.WaveAdd(240)
Pinio.WaveAdd(60)
For i = 0 To 11
    If i < 7 Then
        n = (21 >> i) And 1
    Else
        n = (12 >> (i - 7)) And 1
    End If
    If n = 1 Then
        Pinio.WaveAdd(120)
    Else
        Pinio.WaveAdd(60)
    End If
    Pinio.WaveAdd(60)
Next
Pinio.WaveStart()
Chk(e5, Irremote.SonyIn(12), 3093)
' a line stuck low: no frame
Pinio.WaveBegin()
Pinio.WaveAdd(0)
Pinio.WaveAdd(65535)
Pinio.WaveStart()
Chk(e5, Irremote.SonyIn(12), 65535)
Pinio.WaveStart()
Chk(e5, Irremote.RC5In(12), 65535)
' RC5: system 5, command 42, start 2 set (so command < 64), toggle 0; then toggle 1 with start 2 clear (command + 64); then all ones
Rc5Wave(4096 + 320 + 42)
Chk(e5, Irremote.RC5In(12), 1322)
Rc5Wave(2048 + 320 + 42)
Chk(e5, Irremote.RC5In(12), 1386)
Rc5Wave(8191)
Chk(e5, Irremote.RC5In(12), 7999)
Rc5Wave(0)
Chk(e5, Irremote.RC5In(12), 64)
Chk(e5, Irremote.SonyIn(30), 65535)

' Pulse measurements: high 10, low 100, high 300 polls; low 123; low 200.
Pinio.WaveBegin()
Pinio.WaveAdd(10)
Pinio.WaveAdd(100)
Pinio.WaveAdd(300)
Pinio.WaveAdd(65535)
Pinio.WaveStart()
Chk(e6, Pulse.PulseIn(12, True), 299)
Pinio.WaveBegin()
Pinio.WaveAdd(0)
Pinio.WaveAdd(123)
Pinio.WaveAdd(65535)
Pinio.WaveStart()
Chk(e6, Pulse.RCin(12, False), 124)
Pinio.WaveBegin()
Pinio.WaveAdd(0)
Pinio.WaveAdd(200)
Pinio.WaveAdd(65535)
Pinio.WaveStart()
Chk(e6, Pulse.Pot(12, 128), 100)
Pinio.WaveStart()
Chk(e6, Pulse.Pot(12, 255), 200)
Chk(e6, Pulse.RCin(30, False), 0)

' Pin writes: a pulse is two, a servo pulse three (low, high, low), a tone one at the start, one per half period, one at the end.
Pinio.ClearSets()
Pulse.PulseOut(10, 5, True)
Chk(e7, Pinio.Sets(10), 2)
Pulse.PulseOut(10, 5)
Chk(e7, Pinio.Sets(10), 4)
Pulse.Servo(11, 120)
Chk(e7, Pinio.Sets(11), 3)
Pulse.Sound(13, 60, 1)
Chk(e7, Pinio.Sets(13), 96)
Pulse.Sound(14, 200, 1)
Chk(e7, Pinio.Sets(14), 116)
Pulse.Sound(15, 0, 1)
Chk(e7, Pinio.Sets(15), 1)
Pulse.Sound2(16, 17, 1000, 2000, 2)
Chk(e8, Pinio.Sets(16), 6)
Chk(e8, Pinio.Sets(17), 10)
Pulse.PwmPin(18, 0, 2)
Chk(e8, Pinio.Sets(18), 2)
Pulse.PwmPin(19, 255, 2)
Chk(e8, Pinio.Sets(19), 2)
Pulse.PwmPin(20, 100, 2)
Chk(e8, Pinio.Sets(20), 4)
Pulse.Freqout(21, 2, 1000)
Chk(e8, Pinio.Sets(21), 6)
Pulse.Freqout(22, 2, 1000, 2000)
Chk(e8, Pinio.Sets(22), 14)
done = 1
