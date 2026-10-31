Module Pinio
' Test double for `Pinio` used with the `pulse`, `irremote` and `x10` models. Every pin below 24 exists. A call to PinGet is one
' poll of 10 us, so a waveform is a list of poll counts:
'   pin 12: the waveform built with WaveAdd (even entries high, odd entries low; the last level stays);
'   pin 9:  the zero-cross pin of an X-10 interface: it falls once for every two calls, and each fall is one half-cycle (Half);
'   pin 8:  the X-10 data pin: PinSet(8, True) is recorded as a burst in the current half-cycle, and after Replay PinGet
'           returns low (a burst, as the TW523 receive output) for each half-cycle that had one.
' PinSet counts its calls for each pin.
Dim seg(40) As Word
Dim segn As Byte
Dim idx As Byte
Dim left As Word
Dim writes(24) As Byte
Dim hasBurst(127) As Boolean
Dim hc As Byte
Dim zt As Boolean

Public Function PinOk(ByVal pin As Byte) As Boolean
    Result = pin < 24
End Function

Public Sub PinSet(ByVal pin As Byte, ByVal level As Boolean)
    writes(pin) = writes(pin) + 1
    If pin = 8 And level And hc < 127 Then
        hasBurst(hc) = True
    End If
End Sub

Public Sub PinOutput(ByVal pin As Byte)
End Sub

Public Sub PinInput(ByVal pin As Byte)
End Sub

Public Function PinGet(ByVal pin As Byte) As Boolean
    Result = False
    If pin = 12 Then
        While left = 0 And idx + 1 < segn
            idx = idx + 1
            left = seg(idx)
        Wend
        If left > 0 Then
            left = left - 1
        End If
        Result = (idx And 1) = 0
    ElseIf pin = 9 Then
        zt = Not zt
        Result = zt
        If Not zt And hc < 127 Then
            hc = hc + 1
        End If
    ElseIf pin = 8 Then
        Result = Not hasBurst(hc)
    End If
End Function

Public Sub WaveBegin()
    segn = 0
End Sub

Public Sub WaveAdd(ByVal n As Word)
    seg(segn) = n
    segn = segn + 1
End Sub

Public Sub WaveStart()
    idx = 0
    left = seg(0)
End Sub

' Calls of PinSet on pin so far.
Public Function Sets(ByVal pin As Byte) As Byte
    Result = writes(pin)
End Function

Public Sub ClearSets()
    Dim i As Byte
    For i = 0 To 23
        writes(i) = 0
    Next
End Sub

' Start the half-cycle count again, to play back what was sent.
Public Sub Replay()
    hc = 0
    zt = False
End Sub

' Forget every burst.
Public Sub ClearBursts()
    Dim i As Byte
    For i = 0 To 126
        hasBurst(i) = False
    Next
    hc = 0
    zt = False
End Sub

Public Function Burst(ByVal h As Byte) As Boolean
    Result = hasBurst(h)
End Function

Public Function Bursts() As Byte
    Dim i As Byte
    Result = 0
    For i = 0 To 126
        If hasBurst(i) Then
            Result = Result + 1
        End If
    Next
End Function
