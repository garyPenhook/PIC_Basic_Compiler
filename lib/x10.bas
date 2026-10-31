Module X10
Include "pinio"
' X-10 power-line control through a PL513 (send only) or TW523 (two-way) interface, as the Xout / Xin commands of
' PICBASIC-style compilers. Pins are numbered 0..23 as in `Pinio`. Never connect a pin to the AC line: use the
' interface module, which isolates it. The interface outputs are open collector: use pull-up resistors (4.7 k) on
' the zero-cross and receive pins.
'
' House code 0..15 is A..P. Key code 0..15 is the unit 1..16; 16 + n is a function: UnitOn = 18, UnitOff = 26,
' UnitsOff = 28, LightsOn = 20, LightsOff = 16, Bright = 22, Dim = 30 (the constants below). On the line a frame is
' a start code (three half-cycles with a 120 kHz burst and one without) and nine bits, each sent in a whole cycle
' as the bit and its complement: the 4-bit house code, the 4-bit key code, then 0 for a unit and 1 for a function.
' The zero-cross output of the interface pulses low at every zero crossing of the line (120 times a second at 60 Hz);
' without those pulses the routines give up after about 50 ms and return False.
Public Const UnitOn = 18
Public Const UnitOff = 26
Public Const UnitsOff = 28
Public Const LightsOn = 20
Public Const LightsOff = 16
Public Const Bright = 22
Public Const DimIt = 30

' The 4-bit pattern sent for house or unit number n (0..15), first bit sent in bit 3: A = 0110, B = 1110, C = 0010 ...
Public Function CodeOf(ByVal n As Byte) As Byte
    Dim t As LongWord
    n = n And 15
    If n < 8 Then
        t = 3583091430
    Else
        t = 3296769015
        n = n - 8
    End If
    Result = Byte((t >> (n * 4)) And 15)
End Function

' Number for a 4-bit pattern, the inverse of CodeOf.
Public Function NumberOf(ByVal code As Byte) As Byte
    Dim i As Byte
    Result = 0
    For i = 0 To 15
        If CodeOf(i) = code Then
            Result = i
        End If
    Next
End Function

' Waits for the next zero-crossing pulse (the pin goes low). False when none comes within about 50 ms.
Function Zero(ByVal zpin As Byte) As Boolean
    Dim n As Word
    n = 0
    Result = False
    While Pinio.PinGet(zpin) = False
        DelayUS(10)
        n = n + 1
        If n > 5000 Then
            Exit
        End If
    Wend
    n = 0
    While Pinio.PinGet(zpin)
        DelayUS(10)
        n = n + 1
        If n > 5000 Then
            Exit
        End If
    Wend
    Result = n <= 5000
End Function

' One half-cycle: a burst (1 ms) at the zero crossing when burst is True.
Function Half(ByVal dpin As Byte, ByVal zpin As Byte, ByVal burst As Boolean) As Boolean
    Result = Zero(zpin)
    If Result And burst Then
        Pinio.PinSet(dpin, True)
        DelayMS(1)
        Pinio.PinSet(dpin, False)
    End If
End Function

' One bit: the bit, then its complement, in one cycle.
Function SendBit(ByVal dpin As Byte, ByVal zpin As Byte, ByVal b As Boolean) As Boolean
    Result = Half(dpin, zpin, b) And Half(dpin, zpin, Not b)
End Function

' One frame; False if the zero-cross pulses stop.
Function Frame(ByVal dpin As Byte, ByVal zpin As Byte, ByVal house As Byte, ByVal key As Byte) As Boolean
    Dim i As Byte
    Dim h As Byte
    Dim k As Byte
    h = CodeOf(house)
    k = CodeOf(key)
    Result = Half(dpin, zpin, True) And Half(dpin, zpin, True) And Half(dpin, zpin, True) And Half(dpin, zpin, False)
    For i = 0 To 3
        Result = Result And SendBit(dpin, zpin, (h And (8 >> i)) <> 0)
    Next
    For i = 0 To 3
        Result = Result And SendBit(dpin, zpin, (k And (8 >> i)) <> 0)
    Next
    Result = Result And SendBit(dpin, zpin, (key And 16) <> 0)
End Function

' Sends house, key `reps` times (at least 2; 2 is the normal code, more are for Bright and Dim). Frames go out in
' pairs with three silent cycles after each pair, except for Bright and Dim, which follow each other at once.
' Returns False, having sent part of a frame, when the zero-cross pulses fail. The data pin is made an output.
Public Function Xout(ByVal dataPin As Byte, ByVal zeroPin As Byte, ByVal house As Byte, ByVal key As Byte, ByVal reps As Byte) As Boolean
    Dim n As Byte
    Dim g As Byte
    Dim sent As Boolean
    Result = False
    sent = True
    If Not (Pinio.PinOk(dataPin) And Pinio.PinOk(zeroPin)) Or dataPin = zeroPin Or house > 15 Or key > 31 Then
        Exit
    End If
    If reps < 2 Then
        reps = 2
    End If
    Pinio.PinSet(dataPin, False)
    Pinio.PinOutput(dataPin)
    Pinio.PinInput(zeroPin)
    For n = 1 To reps
        If sent Then
            sent = Frame(dataPin, zeroPin, house, key)
        End If
        If sent And (n And 1) = 0 And n < reps And key <> Bright And key <> DimIt Then
            For g = 1 To 6
                If sent Then
                    sent = Zero(zeroPin)
                End If
            Next
        End If
    Next
    Result = sent
End Function

' Receives one frame. value gets the house code (0..15) in the high byte and the key code (0..15 unit, 16 + n function)
' in the low byte, as sent by Xout. timeout is a number of half-cycles (about 8.33 ms) to wait for the start of a
' frame; 0 waits for ever as long as the zero-cross pulses keep coming. False on timeout, on a frame whose bit and
' complement agree, or when the zero-cross pulses fail. The receive pin of the TW523 is low while a burst is present.
Public Function Xin(ByVal dataPin As Byte, ByVal zeroPin As Byte, ByVal timeout As Word, ByRef value As Word) As Boolean
    Dim hist As Byte
    Dim n As Word
    Dim i As Byte
    Dim a As Boolean
    Dim b As Boolean
    Dim h As Byte
    Dim k As Byte
    Dim f As Byte
    Dim good As Boolean
    Result = False
    If Not (Pinio.PinOk(dataPin) And Pinio.PinOk(zeroPin)) Or dataPin = zeroPin Then
        Exit
    End If
    Pinio.PinInput(dataPin)
    Pinio.PinInput(zeroPin)
    hist = 0
    n = 0
    While hist <> 14
        If Not Zero(zeroPin) Then
            Exit
        End If
        DelayUS(500)
        hist = (hist << 1) And 15
        If Not Pinio.PinGet(dataPin) Then
            hist = hist Or 1
        End If
        n = n + 1
        If timeout > 0 And n >= timeout Then
            Exit
        End If
    Wend
    If hist <> 14 Then
        Exit
    End If
    h = 0
    k = 0
    f = 0
    good = True
    For i = 0 To 8
        If good Then
            good = Zero(zeroPin)
        End If
        DelayUS(500)
        a = Pinio.PinGet(dataPin) = False
        If good Then
            good = Zero(zeroPin)
        End If
        DelayUS(500)
        b = Pinio.PinGet(dataPin) = False
        If a = b Then
            good = False
        End If
        If i < 4 Then
            h = h << 1
            If a Then
                h = h Or 1
            End If
        ElseIf i < 8 Then
            k = k << 1
            If a Then
                k = k Or 1
            End If
        ElseIf a Then
            f = 1
        End If
    Next
    If Not good Then
        Exit
    End If
    value = (NumberOf(h) << 8) Or NumberOf(k) Or (f << 4)
    Result = True
End Function
