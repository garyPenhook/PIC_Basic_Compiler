Module Shift
Include "pinio"
' Bit-banged synchronous shift, for shift registers (74HC595, 74HC165), DACs, ADCs and any device with a
' data line and a clock. Pins are numbered 0..23 as in `Pinio` (RA0 = 0, RB0 = 8, RC0 = 16). The clock idles
' low. Data is changed while the clock is low and is valid at its rising edge (SPI mode 0, so 74HC595 and
' most chips work); the input is sampled just before the clock goes low again. Each clock phase lasts about
' 1 us plus the instruction time, so the rate is below 250 kHz at 64 MHz and the routines work with any slower part.
'
' ShiftOut(data, dataPin, clkPin, lsbFirst, bits): the low `bits` bits of data, 1..8, most significant first
'   (lsbFirst = False) or least significant first. ShiftIn(dataPin, clkPin, lsbFirst, bits) gives the bits read,
'   right-justified. ShiftOut16 / ShiftIn16 do the same for 9..16 bits.
' Both set their pins (clock output, data output or input) and make them digital. A pin that does not exist
' on the part, or equal pins, stop the routine at once: ShiftOut sends nothing and ShiftIn returns 0.
Function PinsOk(ByVal d As Byte, ByVal c As Byte, ByVal bits As Byte, ByVal max As Byte) As Boolean
    Result = Pinio.PinOk(d) And Pinio.PinOk(c) And d <> c And bits >= 1 And bits <= max
End Function

Public Sub ShiftOut(ByVal data As Byte, ByVal dataPin As Byte, ByVal clkPin As Byte, ByVal lsbFirst As Boolean, ByVal bits As Byte)
    Dim i As Byte
    If Not PinsOk(dataPin, clkPin, bits, 8) Then
        Exit
    End If
    Pinio.PinSet(clkPin, False)
    Pinio.PinOutput(clkPin)
    Pinio.PinOutput(dataPin)
    If Not lsbFirst Then
        data = data << (8 - bits)
    End If
    For i = 1 To bits
        If lsbFirst Then
            Pinio.PinSet(dataPin, (data And 1) <> 0)
            data = data >> 1
        Else
            Pinio.PinSet(dataPin, (data And 128) <> 0)
            data = data << 1
        End If
        DelayUS(1)
        Pinio.PinSet(clkPin, True)
        DelayUS(1)
        Pinio.PinSet(clkPin, False)
    Next
End Sub

Public Function ShiftIn(ByVal dataPin As Byte, ByVal clkPin As Byte, ByVal lsbFirst As Boolean, ByVal bits As Byte) As Byte
    Dim i As Byte
    Result = 0
    If Not PinsOk(dataPin, clkPin, bits, 8) Then
        Exit
    End If
    Pinio.PinSet(clkPin, False)
    Pinio.PinOutput(clkPin)
    Pinio.PinInput(dataPin)
    For i = 1 To bits
        Pinio.PinSet(clkPin, True)
        DelayUS(1)
        If lsbFirst Then
            Result = Result >> 1
            If Pinio.PinGet(dataPin) Then
                Result = Result Or (1 << (bits - 1))
            End If
        Else
            Result = Result << 1
            If Pinio.PinGet(dataPin) Then
                Result = Result Or 1
            End If
        End If
        Pinio.PinSet(clkPin, False)
        DelayUS(1)
    Next
End Function

Public Sub ShiftOut16(ByVal data As Word, ByVal dataPin As Byte, ByVal clkPin As Byte, ByVal lsbFirst As Boolean, ByVal bits As Byte)
    Dim i As Byte
    If Not PinsOk(dataPin, clkPin, bits, 16) Then
        Exit
    End If
    Pinio.PinSet(clkPin, False)
    Pinio.PinOutput(clkPin)
    Pinio.PinOutput(dataPin)
    If Not lsbFirst Then
        data = data << (16 - bits)
    End If
    For i = 1 To bits
        If lsbFirst Then
            Pinio.PinSet(dataPin, (data And 1) <> 0)
            data = data >> 1
        Else
            Pinio.PinSet(dataPin, (data And 32768) <> 0)
            data = data << 1
        End If
        DelayUS(1)
        Pinio.PinSet(clkPin, True)
        DelayUS(1)
        Pinio.PinSet(clkPin, False)
    Next
End Sub

Public Function ShiftIn16(ByVal dataPin As Byte, ByVal clkPin As Byte, ByVal lsbFirst As Boolean, ByVal bits As Byte) As Word
    Dim i As Byte
    Result = 0
    If Not PinsOk(dataPin, clkPin, bits, 16) Then
        Exit
    End If
    Pinio.PinSet(clkPin, False)
    Pinio.PinOutput(clkPin)
    Pinio.PinInput(dataPin)
    For i = 1 To bits
        Pinio.PinSet(clkPin, True)
        DelayUS(1)
        If lsbFirst Then
            Result = Result >> 1
            If Pinio.PinGet(dataPin) Then
                Result = Result Or (Word(1) << (bits - 1))
            End If
        Else
            Result = Result << 1
            If Pinio.PinGet(dataPin) Then
                Result = Result Or 1
            End If
        End If
        Pinio.PinSet(clkPin, False)
        DelayUS(1)
    Next
End Function
