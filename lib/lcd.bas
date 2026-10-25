Module Lcd
' Character LCD with an HD44780U controller, 4-bit interface (HD44780U data sheet, Hitachi
' ADE-207-272(Z) Rev 0.0; page numbers are not given because the copy is unnumbered, tables and
' figures are). Six port pins are used: RS, E and DB4..DB7. R/W is not used: tie it to ground. The
' busy flag is not read; every instruction is followed by a wait longer than its worst case time
' [Table 6]: 50 us for 37 us instructions, 2 ms for Clear display (1.52 ms) and Return home.
'
' Pins are numbered 0..23: RA0..RA7 = 0..7, RB0..RB7 = 8..15, RC0..RC7 = 16..23 (the Adc/I2c/Spi
' numbering with port A added). LcdInit makes the six pins digital outputs. The pins can be shared with
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
Dim used As LongWord
Dim pRs As Byte
Dim pEn As Byte
Dim pD4 As Byte
Dim pD5 As Byte
Dim pD6 As Byte
Dim pD7 As Byte
Dim twoLines As Boolean
Dim ready As Boolean
Dim shown As Byte

' Output level of pin 0..23.
Sub PinSet(ByVal pin As Byte, ByVal level As Boolean)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 8 Then
        If level Then
            LATA = LATA Or m
        Else
            LATA = LATA And (m Xor 255)
        End If
    ElseIf pin < 16 Then
        If level Then
            LATB = LATB Or m
        Else
            LATB = LATB And (m Xor 255)
        End If
    Else
        If level Then
            LATC = LATC Or m
        Else
            LATC = LATC And (m Xor 255)
        End If
    End If
End Sub

' Pin 0..23 as a digital output.
Sub PinOutput(ByVal pin As Byte)
    Dim m As Byte
    Dim n As Byte
    m = 1 << (pin And 7)
    n = m Xor 255
    If pin < 8 Then
        ANSELA = ANSELA And n
        TRISA = TRISA And n
    ElseIf pin < 16 Then
        ANSELB = ANSELB And n
        TRISB = TRISB And n
    Else
        ANSELC = ANSELC And n
        TRISC = TRISC And n
    End If
End Sub

' True when `pin` is 0..23 and no other pin has claimed it yet.
Function Claim(ByVal pin As Byte) As Boolean
    Dim mask As LongWord
    Result = False
    If pin > 23 Then
        Exit
    End If
    mask = LongWord(1) << pin
    If (used And mask) = 0 Then
        used = used Or mask
        Result = True
    End If
End Function

' One enable pulse with the data nibble already on DB4..DB7.
Sub Pulse()
    PinSet(pEn, True)
    DelayUS(1)
    PinSet(pEn, False)
    DelayUS(1)
End Sub

' Puts the low four bits of `nib` on DB4..DB7 (bit 0 on DB4) and pulses E.
Sub Nibble(ByVal nib As Byte)
    PinSet(pD4, (nib And 1) <> 0)
    PinSet(pD5, (nib And 2) <> 0)
    PinSet(pD6, (nib And 4) <> 0)
    PinSet(pD7, (nib And 8) <> 0)
    Pulse()
End Sub

' A whole byte, high nibble first [4-bit interface, "data must be sent or received twice"]; rs = True
' for data (RS = 1), False for an instruction.
Sub Send(ByVal b As Byte, ByVal rs As Boolean)
    PinSet(pRs, rs)
    Nibble(b >> 4)
    Nibble(b And 15)
    DelayUS(50)
End Sub

' Sets up the pins and runs the initialisation by instruction for a 4-bit interface [Figure 24], then
' turns the display on with no cursor, clears it and selects "increment, no shift" [Entry mode set].
' `lines` is 1 or 2 (5 x 8 dot font; the data sheet does not allow two lines with the 5 x 10 font, and
' this module does not offer it). Returns 1, or 0 when `lines` is not 1 or 2, a pin is above 23 or a
' pin is used twice. Takes about 55 ms.
Public Function LcdInit(ByVal rs As Byte, ByVal en As Byte, ByVal d4 As Byte, ByVal d5 As Byte, ByVal d6 As Byte, ByVal d7 As Byte, ByVal lines As Byte) As Byte
    Result = 0
    If lines < 1 Or lines > 2 Then
        Exit
    End If
    used = 0
    If Not Claim(rs) Then
        Exit
    End If
    If Not Claim(en) Then
        Exit
    End If
    If Not Claim(d4) Then
        Exit
    End If
    If Not Claim(d5) Then
        Exit
    End If
    If Not Claim(d6) Then
        Exit
    End If
    If Not Claim(d7) Then
        Exit
    End If
    pRs = rs
    pEn = en
    pD4 = d4
    pD5 = d5
    pD6 = d6
    pD7 = d7
    twoLines = (lines = 2)
    PinSet(rs, False)
    PinSet(en, False)
    PinSet(d4, False)
    PinSet(d5, False)
    PinSet(d6, False)
    PinSet(d7, False)
    PinOutput(rs)
    PinOutput(en)
    PinOutput(d4)
    PinOutput(d5)
    PinOutput(d6)
    PinOutput(d7)
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
    shown = 12
    Send(shown, False)
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
    shown = 8
    If on Then
        shown = shown Or 4
    End If
    If cursor Then
        shown = shown Or 2
    End If
    If blink Then
        shown = shown Or 1
    End If
    LcdCommand(shown)
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

' Unsigned decimal, no leading zeros.
Public Sub LcdWriteWord(ByVal v As Word)
    Dim started As Boolean
    Dim d As Word
    Dim digit As Byte
    started = False
    d = 10000
    While d > 0
        digit = Byte(v / d)
        v = v Mod d
        If digit > 0 Or started Or d = 1 Then
            LcdWriteChar(48 + digit)
            started = True
        End If
        d = d / 10
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
