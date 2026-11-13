Module Lcd
Include "pinio"
' Character LCD with an HD44780U controller, 4-bit interface (HD44780U data sheet, Hitachi
' ADE-207-272(Z) Rev 0.0; page numbers are not given because the copy is unnumbered, tables and
' figures are). Six port pins are used: RS, E and DB4..DB7. R/W is not used unless LcdRwInit is called:
' tie it to ground. Writes do not read the busy flag; every instruction is followed by a wait longer than its worst case time
' [Table 6]: 50 us for 37 us instructions, 2 ms for Clear display (1.52 ms) and Return home.
'
' Pins are numbered 0..23: RA0..RA7 = 0..7, RB0..RB7 = 8..15, RC0..RC7 = 16..23 (the Adc/I2c/Spi
' numbering with port A added). A part without port B (the 14-pin PIC18-Q41, the PIC16F13123/13124/13125 and the 8-pin PIC16F13113) refuses pins 8..15, and one without port C (the PIC16F13113) pins 16..23. LcdInit makes the six pins digital outputs. The pins can be shared with
' other outputs of the same ports only if nothing else changes a LATx register while a Lcd routine
' runs (the pins are set with read-modify-write on LATA/LATB/LATC): do not use the module from an
' interrupt handler and from the main program.
'
' Display data RAM [Figure 8, "Set DDRAM address"]: a 2-line display has its first line at DDRAM address
' 00H..27H and its second line at 40H..67H; a 1-line display uses 00H..4FH. LcdGoto(col, row) takes
' col 0..39 (0..79 for one line) and row 0 or 1. Displays with four lines are wired onto these two
' lines in a way the data sheet does not describe: address them with LcdSetAddress.
'
' The enable pulse is 1 us high and 1 us low; the data sheet asks for at least 450 ns high and a 1000 ns
' cycle [Bus Timing Characteristics, write operation]. Address set-up (60 ns) is met by the
' instruction before the pulse. The display power supply must be stable (more than 15 ms after VCC
' rises to 4.5 V, more than 40 ms after 2.7 V [Figure 24]): LcdInit waits 50 ms first.
' The six pins: 0 = RS, 1 = E, 2..5 = DB4..DB7.
Dim pins(6) As Byte
Dim twoLines As Boolean
Dim ready As Boolean
Dim hasRw As Boolean
Dim rwPin As Byte
Dim rx As Byte

' One enable pulse with the data nibble already on DB4..DB7.
Sub Pulse()
    Pinio.PinSet(pins(1), True)
    DelayUS(1)
    Pinio.PinSet(pins(1), False)
    DelayUS(1)
End Sub

' Puts the low four bits of `nib` on DB4..DB7 (bit 0 on DB4) and pulses E.
Sub Nibble(ByVal nib As Byte)
    Dim i As Byte
    For i = 2 To 5
        Pinio.PinSet(pins(i), (nib And 1) <> 0)
        nib = nib >> 1
    Next
    Pulse()
End Sub

' A whole byte, high nibble first [4-bit interface, "data must be sent or received twice"]; rs = True
' for data (RS = 1), False for an instruction.
Sub Send(ByVal b As Byte, ByVal rs As Boolean)
    Pinio.PinSet(pins(0), rs)
    Nibble(b >> 4)
    Nibble(b And 15)
    DelayUS(50)
End Sub

' Sets up the pins and runs the initialisation by instruction for a 4-bit interface [Figure 24], then
' turns the display on with no cursor, clears it and selects "increment, no shift" [Entry mode set].
' `lines` is 1 or 2 (5 x 8 dot font; the data sheet does not allow two lines with the 5 x 10 font, and
' this module does not offer it). Returns 1, or 0 when `lines` is not 1 or 2, a pin is above 23 or a
' pin is used twice (a pin the part lacks counts as above 23). A refused call leaves the
' module disabled: every other Lcd routine does nothing until a call succeeds. Takes about 55 ms.
Public Function LcdInit(ByVal rs As Byte, ByVal en As Byte, ByVal d4 As Byte, ByVal d5 As Byte, ByVal d6 As Byte, ByVal d7 As Byte, ByVal lines As Byte) As Byte
    Dim i As Byte
    Dim j As Byte
    Result = 0
    ready = False
    hasRw = False
    If lines < 1 Or lines > 2 Then
        Exit
    End If
    pins(0) = rs
    pins(1) = en
    pins(2) = d4
    pins(3) = d5
    pins(4) = d6
    pins(5) = d7
    For i = 0 To 5
        If Not Pinio.PinOk(pins(i)) Then
            Exit
        End If
        j = 0
        While j < i
            If pins(j) = pins(i) Then
                Exit
            End If
            Inc(j)
        Wend
    Next
    twoLines = (lines = 2)
    For i = 0 To 5
        Pinio.PinSet(pins(i), False)
        Pinio.PinOutput(pins(i))
    Next
    DelayMS(50)
    ' Function set (8-bit interface) three times, the waits are those of Figure 24.
    Nibble(3)
    DelayMS(5)
    Nibble(3)
    DelayUS(150)
    Nibble(3)
    DelayUS(150)
    ' Function set: 4-bit interface. The busy flag could be checked from here on; it is not.
    Nibble(2)
    DelayUS(150)
    ' Function set again with the number of lines (N) and the font (F = 0, 5 x 8): 0 0 1 DL N F * *
    If twoLines Then
        Send(40, False)
    Else
        Send(32, False)
    End If
    Send(8, False)
    Send(1, False)
    DelayMS(2)
    ' Entry mode set: I/D = 1, S = 0.
    Send(6, False)
    ' Display on/off: D = 1, C = 0, B = 0.
    Send(12, False)
    ready = True
    Result = 1
End Function

' Sends an instruction byte (see the instruction table of the data sheet). Waits 2 ms after Clear
' display (1) and Return home (2 or 3), 50 us after the rest.
Public Sub LcdCommand(ByVal c As Byte)
    If Not ready Then
        Exit
    End If
    Send(c, False)
    If c < 4 Then
        DelayMS(2)
    End If
End Sub

' Clears the display and puts the cursor at the first character of the first line.
Public Sub LcdClear()
    LcdCommand(1)
End Sub

' Cursor to the first character of the first line and the display back to its unshifted position.
Public Sub LcdHome()
    LcdCommand(2)
End Sub

' Display on/off control: D = `on`, C = `cursor`, B = `blink` (character at the cursor blinks).
Public Sub LcdDisplay(ByVal on As Boolean, ByVal cursor As Boolean, ByVal blink As Boolean)
    Dim c As Byte
    c = 8
    If on Then
        c = c Or 4
    End If
    If cursor Then
        c = c Or 2
    End If
    If blink Then
        c = c Or 1
    End If
    LcdCommand(c)
End Sub

' Cursor or display shift [Table 7]: shifts the whole display (`whole` = True) or only the cursor, one
' position to the right (`right` = True) or the left.
Public Sub LcdShift(ByVal whole As Boolean, ByVal right As Boolean)
    Dim c As Byte
    c = 16
    If whole Then
        c = c Or 8
    End If
    If right Then
        c = c Or 4
    End If
    LcdCommand(c)
End Sub

' Set DDRAM address: the next character is written at address 0..127 (7 bits).
Public Sub LcdSetAddress(ByVal addr As Byte)
    LcdCommand(128 Or (addr And 127))
End Sub

' Cursor to column `col` (0..39, or 0..79 on a one-line display) of row `row` (0 or 1). A position
' the display does not have is ignored.
Public Sub LcdGoto(ByVal col As Byte, ByVal row As Byte)
    If twoLines Then
        If col > 39 Or row > 1 Then
            Exit
        End If
        If row = 1 Then
            col = col + 64
        End If
    Else
        If col > 79 Or row > 0 Then
            Exit
        End If
    End If
    LcdSetAddress(col)
End Sub

' Writes one character code at the cursor (codes 32..126 are ASCII for the A00 character ROM; 0..7
' are the user characters of LcdCustomRow).
Public Sub LcdWriteChar(ByVal ch As Byte)
    If ready Then
        Send(ch, True)
    End If
End Sub

' Writes a string at the cursor.
Public Sub LcdWrite(ByRefConst s As String(80))
    Dim i As Byte
    i = 0
    While s(i) <> #0
        LcdWriteChar(Byte(s(i)))
        Inc(i)
    Wend
End Sub

' Unsigned decimal, no leading zeros. Each digit is found by subtracting the power of ten, so no divide routine is linked.
Public Sub LcdWriteWord(ByVal v As Word)
    Dim started As Boolean
    Dim d As Word
    Dim digit As Byte
    started = False
    d = 10000
    While d > 0
        digit = 0
        While v >= d
            v = v - d
            Inc(digit)
        Wend
        If digit > 0 Or started Or d = 1 Then
            LcdWriteChar(48 + digit)
            started = True
        End If
        If d = 10000 Then
            d = 1000
        ElseIf d = 1000 Then
            d = 100
        ElseIf d = 100 Then
            d = 10
        ElseIf d = 10 Then
            d = 1
        Else
            d = 0
        End If
    Wend
End Sub

' Two hexadecimal digits.
Public Sub LcdWriteHex(ByVal v As Byte)
    Dim h As Byte
    h = v >> 4
    If h > 9 Then
        h = h + 7
    End If
    LcdWriteChar(48 + h)
    h = v And 15
    If h > 9 Then
        h = h + 7
    End If
    LcdWriteChar(48 + h)
End Sub

' Sets row `row` (0..7, the eight dot rows of a 5 x 8 character) of the user character `slot`
' (0..7, shown as character code 0..7) to the low five bits of `bits` (bit 4 = leftmost dot). The
' 8th row is the cursor row: keep it 0 if the cursor is used [CGRAM, "Set CGRAM address"]. The write
' leaves the address counter in CGRAM: call LcdGoto (or LcdClear / LcdHome) before writing text.
Public Sub LcdCustomRow(ByVal slot As Byte, ByVal row As Byte, ByVal bits As Byte)
    If slot > 7 Or row > 7 Then
        Exit
    End If
    LcdCommand(64 Or (slot << 3) Or row)
    Send(bits And 31, True)
End Sub

' Reading [Table 1, "Read busy flag and address", "Read data from CG or DDRAM"] needs the R/W pin,
' which LcdInit leaves unused (tie it to ground if LcdRwInit is not called).

' Claims the R/W pin `rw` (0..23, none of the six pins of LcdInit) as a digital output, low (write).
' Call it after a successful LcdInit; a second call moves the pin. Returns 1, or 0 when LcdInit has not
' succeeded, the pin is above 23 or one of the six pins.
Public Function LcdRwInit(ByVal rw As Byte) As Byte
    Dim i As Byte
    Result = 0
    If Not ready Then
        Exit
    End If
    If Not Pinio.PinOk(rw) Then
        Exit
    End If
    For i = 0 To 5
        If pins(i) = rw Then
            Exit
        End If
    Next
    rwPin = rw
    Pinio.PinSet(rw, False)
    Pinio.PinOutput(rw)
    hasRw = True
    Result = 1
End Function

' One nibble read with E high, shifted into `rx` from the right: the display drives DB4..DB7 for at most
' 360 ns after E rises (tDDR) and holds them 5 ns after it falls. DB7 is read first, so DB4 ends in bit 0.
Sub RecvNibble()
    Dim i As Byte
    Pinio.PinSet(pins(1), True)
    DelayUS(1)
    For i = 0 To 3
        rx = rx << 1
        If Pinio.PinGet(pins(5 - i)) Then
            rx = rx Or 1
        End If
    Next
    Pinio.PinSet(pins(1), False)
    DelayUS(1)
End Sub

' A whole byte read, high nibble first; rs = False reads the busy flag and address counter, True the data.
Function Recv(ByVal rs As Boolean) As Byte
    Dim i As Byte
    For i = 2 To 5
        Pinio.PinInput(pins(i))
    Next
    Pinio.PinSet(pins(0), rs)
    Pinio.PinSet(rwPin, True)
    rx = 0
    RecvNibble()
    RecvNibble()
    Pinio.PinSet(rwPin, False)
    For i = 2 To 5
        Pinio.PinOutput(pins(i))
    Next
    Result = rx
End Function

' Busy flag (bit 7) and address counter (bits 0..6). Returns 0 when LcdRwInit has not succeeded.
Public Function LcdStatus() As Byte
    Result = 0
    If hasRw Then
        Result = Recv(False)
    End If
End Function

' Waits for the busy flag to clear (at most 255 reads, so an absent display cannot hang the program),
' then reads the byte at the address counter (DDRAM, or CGRAM after LcdCommand(64 + a)); the address
' then moves as the entry mode says. Valid straight after LcdGoto, LcdSetAddress or a cursor shift;
' after writing characters call one of those first, because the byte at the counter cannot be read
' then. Returns 0 when LcdRwInit has not succeeded.
Public Function LcdRead() As Byte
    Dim n As Byte
    Result = 0
    If Not hasRw Then
        Exit
    End If
    n = 255
    While n > 0 And (Recv(False) And 128) <> 0
        Dec(n)
    Wend
    Result = Recv(True)
End Function
