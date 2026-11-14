Module Glcd
Include "pinio"
' Graphic LCDs on an 8-bit parallel bus, three controllers behind one drawing interface:
'   GlcdInitKs0108(data, rs, rw, en, cs1, cs2, rst, csHigh)   128 x 64 from two KS0108 / S6B0108 segment drivers
'   GlcdInitT6963(data, wr, rd, ce, cd, rst, xres, yres, fontWidth)   Toshiba T6963C, any size, 6 or 8 pixel font
'   GlcdInitSt7920(data, rs, rw, en, rst, folded)             Sitronix ST7920, 8-bit parallel (PSB high)
'   GlcdInitSt7920x4(data, ...), GlcdInitSt7920Serial(cs, sid, sclk, rst), GlcdInitT6963Dual(...)  see the calls
' Each returns 1, or 0 for a bad argument (a pin the part lacks, a pin used twice, a data port the part lacks).
' `data` is the first pin of the port that carries DB0..DB7: 8 = port B, 16 = port C (port A is refused: RA3 is input only on
' most parts); all eight bits of the
' port are used (`Pinio.PortWrite`, `PortRead`, `PortDirection`). The other lines are pins numbered 0..47 as in `Pinio`; 255 for
' `rst` means "not controlled by the module". The module is not reentrant: do not use it from a handler and the main program.
'
' Sources (the data sheets are in docs/): KS0108 family: Samsung S6B0108 Ver. 0.0 (the KS0108's pin-compatible driver; section
' numbers below are its pages 21-27). T6963C: Toshiba 2002-01-07. ST7920: Sitronix V4.0 2008-08-18.
'
' Coordinates: x to the right 0..xres-1, y down 0..yres-1, (0, 0) at the top left; points outside the display are not drawn.
'   KS0108 128 x 64, T6963C xres x yres as given, ST7920 128 x 64 (folded) or 256 x 64.
'
' KS0108 [S6B0108 pp.21-27]: instructions with RS = 0: display on 3Eh/3Fh, Y address 40h + 0..63, page B8h + 0..7, start line
' C0h + 0..63; data with RS = 1. Page y/8, bit 0 of a data byte on top. A read needs one dummy read, and the Y address
' advances after every read and write. CS1 selects x 0..63, CS2 x 64..127; `csHigh` True when the module's selects are active
' high (the segment driver has CS1B and CS2B active low and CS3 high). Busy flag DB7 of the status read. E pulse 1 us
' (tWH 450 ns, cycle 1000 ns, data delay 320 ns [p.15]).
'
' T6963C [pp.9-26]: a command is sent after its data bytes (the status bits STA0 and STA1 must both be 1 first). The graphic
' area starts at address 0 and the text area (internal CG ROM, code = ASCII - 32) follows it; the external CG RAM (for GlcdUdg) is at
' the first 2 KB boundary above the text area (offset register = address / 800h). A pixel is set or cleared with the Bit Set / Bit Reset command on the address
' pointer, a read is "Data read, ADP unchanged". The leftmost pixel of a byte is the highest bit in use (bit 7 with the 8
' pixel font, bit 5 with the 6 pixel font); the datasheet leaves that to the display drawing, this follows the usual
' LCDwrite convention. `fontWidth` is 8 or 6: it must match the FS pin and the MD2 / MD3 column setting of the module (the
' columns are xres / fontWidth, at most 64). CE, RD and WR pulses 80 ns minimum, C/D set-up 100 ns [p.31].
'
' ST7920 [pp.10-25, 34, 40]: graphic RAM is 64 rows of 16 words of 16 bits, bit 15 on the left (Table 7); an address is the
' vertical address then the horizontal word address (extended instruction set, 80h + n each). `folded` True selects the usual
' 128 x 64 module wiring, rows 32..63 held in words 8..15 of rows 0..31. THE DATA SHEET DOES NOT STATE THIS FOLDING: it comes
' from common module drivers, so check it on the module in hand. `folded` False is Table 7 itself: 256 x 64. The 4-bit mode (`GlcdInitSt7920x4`, DB4..DB7 on the upper pins of a port) and the serial mode
' (`GlcdInitSt7920Serial`, write only: the module keeps a copy of the graphic RAM) are described at the init calls. E pulse 1 us (140 ns, cycle 1200 ns at 4.5 V).
'
' Text uses the 5 x 7 font in a 6 x 8 cell, cols 0..xres/6-1 and rows 0..yres/8-1 (the T6963C uses its own text layer, cell
' width fontWidth, instead). The font is the public domain X11 "5x7" fixed font (as in `Oled`).
'
' Differences from the classic commands: Plot / UnPlot / Pixel take (x, y), not (y, x); Box and Circle are centred as there.
' GlcdLine does 16-bit arithmetic: keep coordinates within about +-16000.

Const Font(475) As Byte = ( _
    0, 0, 0, 0, 0, 0, 0, 94, 0, 0, 0, 14, 0, 14, 0, _
    40, 124, 40, 124, 40, 8, 84, 124, 84, 32, 38, 16, 8, 100, 0, _
    40, 84, 40, 64, 0, 0, 0, 14, 0, 0, 0, 60, 66, 0, 0, _
    0, 66, 60, 0, 0, 0, 84, 56, 84, 0, 16, 16, 124, 16, 16, _
    0, 128, 96, 32, 0, 16, 16, 16, 16, 0, 0, 96, 96, 0, 0, _
    32, 16, 8, 4, 0, 0, 60, 66, 60, 0, 0, 68, 126, 64, 0, _
    68, 98, 82, 76, 0, 34, 74, 74, 54, 0, 24, 20, 126, 16, 0, _
    46, 74, 74, 50, 0, 60, 74, 74, 48, 0, 2, 98, 26, 6, 0, _
    52, 74, 74, 52, 0, 12, 82, 82, 60, 0, 0, 108, 108, 0, 0, _
    128, 108, 44, 0, 0, 0, 16, 40, 68, 0, 40, 40, 40, 40, 0, _
    0, 68, 40, 16, 0, 0, 4, 82, 12, 0, 60, 66, 90, 28, 0, _
    124, 18, 18, 124, 0, 126, 74, 74, 52, 0, 60, 66, 66, 36, 0, _
    126, 66, 66, 60, 0, 126, 74, 74, 66, 0, 126, 10, 10, 2, 0, _
    60, 66, 82, 116, 0, 126, 8, 8, 126, 0, 0, 66, 126, 66, 0, _
    32, 64, 64, 62, 0, 126, 24, 36, 66, 0, 126, 64, 64, 64, 0, _
    126, 12, 12, 126, 0, 126, 12, 48, 126, 0, 60, 66, 66, 60, 0, _
    126, 18, 18, 12, 0, 60, 98, 66, 188, 0, 126, 18, 50, 76, 0, _
    36, 74, 82, 36, 0, 0, 2, 126, 2, 0, 62, 64, 64, 62, 0, _
    30, 96, 96, 30, 0, 126, 48, 48, 126, 0, 102, 24, 24, 102, 0, _
    0, 14, 112, 14, 0, 98, 82, 74, 70, 0, 0, 126, 66, 66, 0, _
    4, 8, 16, 32, 0, 0, 66, 66, 126, 0, 0, 4, 2, 4, 0, _
    64, 64, 64, 64, 0, 0, 2, 4, 0, 0, 48, 72, 40, 120, 0, _
    126, 72, 72, 48, 0, 48, 72, 72, 0, 0, 48, 72, 72, 126, 0, _
    48, 104, 88, 16, 0, 16, 124, 18, 4, 0, 80, 168, 168, 152, 0, _
    126, 8, 8, 112, 0, 0, 72, 122, 64, 0, 0, 64, 128, 122, 0, _
    126, 16, 40, 64, 0, 0, 66, 126, 64, 0, 120, 16, 24, 112, 0, _
    120, 8, 8, 112, 0, 48, 72, 72, 48, 0, 248, 72, 72, 48, 0, _
    48, 72, 72, 248, 0, 120, 8, 8, 16, 0, 80, 88, 104, 40, 0, _
    8, 62, 72, 64, 0, 56, 64, 64, 120, 0, 0, 56, 64, 56, 0, _
    120, 96, 96, 120, 0, 72, 48, 48, 72, 0, 24, 160, 64, 56, 0, _
    72, 104, 88, 72, 0, 0, 8, 60, 66, 0, 0, 0, 126, 0, 0, _
    0, 66, 60, 8, 0, 4, 2, 4, 2, 0)

Dim kind As Byte
Dim used(6) As Byte
Dim pData As Byte
Dim pA As Byte
Dim pB As Byte
Dim pC As Byte
Dim pD As Byte
Dim pE As Byte
Dim pRst As Byte
Dim csHigh As Boolean
Dim folded As Boolean
Dim xres As Integer
Dim yres As Integer
Dim fw As Byte
Dim cols As Byte
Dim textHome As Word
Dim cgOff As Byte
Dim dual As Boolean
Dim smode As Byte
Dim wHi As Byte
Dim wLo As Byte
#if _maxram >= 1536
' Copy of the 128 x 64 graphic RAM (32 rows of 16 words), kept for the serial interface, which cannot read the display back.
Dim shadow(1024) As Byte
#endif
Dim half As Word
Dim penX As Integer
Dim penY As Integer
Dim tCol As Byte
Dim tRow As Byte

' True when `pin` is a pin the part has (0..47) and no other line has claimed it yet.
Function Claim(ByVal pin As Byte) As Boolean
    Dim mask As Byte
    Dim ix As Byte
    Result = False
    If Not Pinio.PinOk(pin) Then
        Exit
    End If
    ix = pin >> 3
    mask = Byte(1) << (pin And 7)
    If (used(ix) And mask) = 0 Then
        used(ix) = used(ix) Or mask
        Result = True
    End If
End Function

' True when the last `n` (8, 4 or 0) of the eight pins from `base` (8 or 16) exist and are free.
Function ClaimBus(ByVal base As Byte, ByVal n As Byte) As Boolean
    Dim i As Byte
    Result = True
    If n = 0 Then
        Exit
    End If
    Result = False
    If base <> 8 And base <> 16 Then
        Exit
    End If
    i = 8 - n
    While i < 8
        If Not Claim(base + i) Then
            Exit
        End If
        Inc(i)
    Wend
    Result = True
End Function

' A pin that may be 255 (not used) is claimed only when it is a pin.
Function ClaimOpt(ByVal pin As Byte) As Boolean
    Result = True
    If pin <> 255 Then
        Result = Claim(pin)
    End If
End Function

Sub Pulse(ByVal pin As Byte)
    Pinio.PinSet(pin, True)
    DelayUS(1)
    Pinio.PinSet(pin, False)
End Sub

' Sets `pin` to `level`, then makes it an output.
Sub Drive(ByVal pin As Byte, ByVal level As Boolean)
    Pinio.PinSet(pin, level)
    Pinio.PinOutput(pin)
End Sub

Sub MakeOutputs(ByVal count As Byte, ByVal idle As Boolean)
    Drive(pA, False)
    Drive(pB, idle)
    Drive(pC, idle)
    If count > 3 Then
        Drive(pD, idle)
    End If
    If count > 4 Then
        Drive(pE, idle)
    End If
    If smode = 1 Then
        Pinio.PortDigitalHigh(pData)
        Pinio.PortDirectionHigh(pData, False)
    ElseIf smode = 0 Then
        Pinio.PortDigital(pData)
        Pinio.PortDirection(pData, False)
    End If
End Sub

' The reset pulse (low, at least 10 us) on `rst` and 50 ms of power-up before it.
Sub ResetPulse()
    DelayMS(50)
    If pRst <> 255 Then
        Drive(pRst, True)
        Pinio.PinSet(pRst, False)
        DelayUS(20)
        Pinio.PinSet(pRst, True)
        DelayMS(50)
    End If
End Sub

' ---- KS0108: pA = RS (D/I), pB = R/W, pC = E, pD = CS1, pE = CS2 ----

Sub KsSelect(ByVal chip As Byte)
    Dim a As Boolean
    Dim b As Boolean
    a = (chip = 0)
    b = (chip = 1)
    If Not csHigh Then
        a = Not a
        b = Not b
    End If
    Pinio.PinSet(pD, a)
    Pinio.PinSet(pE, b)
End Sub

' One read cycle: the status (`isData` False, busy flag DB7) or the data register.
Function KsIn(ByVal isData As Boolean) As Byte
    Pinio.PortDirection(pData, True)
    Pinio.PinSet(pA, isData)
    Pinio.PinSet(pB, True)
    Pinio.PinSet(pC, True)
    DelayUS(1)
    Result = Pinio.PortRead(pData)
    Pinio.PinSet(pC, False)
End Function

' Waits for the busy flag to clear (at most 200 polls, so a missing display does not hang the program).
Sub KsWait()
    Dim n As Byte
    n = 200
    While n > 0 And (KsIn(False) And 128) <> 0
        Dec(n)
    Wend
End Sub

Sub KsWrite(ByVal isData As Boolean, ByVal v As Byte)
    KsWait()
    Pinio.PortDirection(pData, False)
    Pinio.PinSet(pA, isData)
    Pinio.PinSet(pB, False)
    Pinio.PortWrite(pData, v)
    Pulse(pC)
End Sub

Function KsRead() As Byte
    KsWait()
    Result = KsIn(True)
End Function

' Selects chip 0 or 1 and points it at (page, column 0..63).
Sub KsAt(ByVal chip As Byte, ByVal page As Byte, ByVal col As Byte)
    KsSelect(chip)
    KsWrite(False, 184 Or page)
    KsWrite(False, 64 Or col)
End Sub

' ---- T6963C: pA = C/D, pB = WR, pC = RD, pD = CE ----

' One read cycle: the status (`cd` True) or the data register.
Function TIn(ByVal cd As Boolean) As Byte
    Pinio.PortDirection(pData, True)
    Pinio.PinSet(pA, cd)
    Pinio.PinSet(pC, False)
    Pinio.PinSet(pD, False)
    DelayUS(1)
    Result = Pinio.PortRead(pData)
    Pinio.PinSet(pC, True)
    Pinio.PinSet(pD, True)
End Function

' Waits until the status bits in `mask` are all 1 (3 for a command or data, 8 for auto write); gives up after 200 polls.
Sub TWait(ByVal mask As Byte)
    Dim n As Byte
    n = 200
    While n > 0 And (TIn(True) And mask) <> mask
        Dec(n)
    Wend
End Sub

Sub TRaw(ByVal isCmd As Boolean, ByVal v As Byte)
    Pinio.PortDirection(pData, False)
    Pinio.PinSet(pA, isCmd)
    Pinio.PortWrite(pData, v)
    Pinio.PinSet(pB, False)
    Pinio.PinSet(pD, False)
    DelayUS(1)
    Pinio.PinSet(pB, True)
    Pinio.PinSet(pD, True)
End Sub

Sub TData(ByVal v As Byte)
    TWait(3)
    TRaw(False, v)
End Sub

Sub TCmd(ByVal c As Byte)
    TWait(3)
    TRaw(True, c)
End Sub

Function TReadData() As Byte
    TWait(3)
    Result = TIn(False)
End Function

Sub TCmd1(ByVal c As Byte, ByVal d As Byte)
    TData(d)
    TCmd(c)
End Sub

Sub TCmd2(ByVal c As Byte, ByVal d1 As Byte, ByVal d2 As Byte)
    TData(d1)
    TData(d2)
    TCmd(c)
End Sub

Sub TAddr(ByVal a As Word)
    TCmd2(36, Byte(a And 255), Byte(a >> 8))
End Sub

' Address of the first byte of pixel row y. With dual scan the lower screen holds the same layout as the upper one, 8000h higher
' [T6963C p.7].
Function TRowAddr(ByVal y As Word) As Word
    If dual And y >= half Then
        Result = 32768 + (y - half) * cols
    Else
        Result = y * cols
    End If
End Function

' Points the address pointer at the graphic byte holding pixel x of row y and returns the bit of it.
Function TPoint(ByVal x As Word, ByVal y As Word) As Byte
    Dim q As Word
    q = x / fw
    TAddr(TRowAddr(y) + q)
    Result = fw - 1 - Byte(x - q * fw)
End Function

' Address of the text cell (tCol, tRow); rows below the upper screen are on the lower one.
Function TTextAddr() As Word
    Dim r As Word
    r = tRow
    Result = textHome
    If dual And r >= (half >> 3) Then
        r = r - (half >> 3)
        Result = Result + 32768
    End If
    Result = Result + r * cols + tCol
End Function

' ---- ST7920: pA = RS (CS in serial mode), pB = R/W (SID), pC = E (SCLK) ----
' smode 0: 8-bit parallel, 1: 4-bit parallel on DB4..DB7 (the upper four pins of the port), 2: serial (write only).

' One read cycle, of the status (`rs` False: the busy flag is bit 7) or of the data register. In the 4-bit mode it takes two
' E pulses, the upper nibble first [ST7920 p.25].
Function SReadRaw(ByVal rs As Boolean) As Byte
    Dim hi As Byte
    If smode = 0 Then
        Pinio.PortDirection(pData, True)
    Else
        Pinio.PortDirectionHigh(pData, True)
    End If
    Pinio.PinSet(pA, rs)
    Pinio.PinSet(pB, True)
    Pinio.PinSet(pC, True)
    DelayUS(1)
    If smode = 0 Then
        Result = Pinio.PortRead(pData)
        Pinio.PinSet(pC, False)
    Else
        hi = Pinio.PortReadHigh(pData)
        Pinio.PinSet(pC, False)
        Pinio.PinSet(pC, True)
        DelayUS(1)
        Result = hi Or (Pinio.PortReadHigh(pData) >> 4)
        Pinio.PinSet(pC, False)
    End If
End Function

Function SStatus() As Byte
    Result = SReadRaw(False)
End Function

' Waits for the busy flag. The serial interface cannot read it: an instruction takes 72 us at the 540 kHz clock (a slow one,
' 470 kHz, 83 us) [ST7920 p.16].
Sub SWait()
    Dim n As Byte
    If smode = 2 Then
        DelayUS(90)
        Exit
    End If
    n = 200
    While n > 0 And (SStatus() And 128) <> 0
        Dec(n)
    Wend
End Sub

' Sends one byte as serial bits, most significant first, on SID with an SCLK pulse for each.
Sub SBits(ByVal v As Byte)
    Dim i As Byte
    i = 0
    While i < 8
        Pinio.PinSet(pB, (v And 128) <> 0)
        Pulse(pC)
        v = v << 1
        Inc(i)
    Wend
End Sub

Sub SWrite(ByVal isData As Boolean, ByVal v As Byte)
    SWait()
    If smode = 2 Then
        ' Start byte 11111, RW = 0, RS, 0; then the upper nibble and the lower nibble, each followed by four zero bits
        ' [ST7920 p.25]. CS is high for the three bytes.
        Pinio.PinSet(pA, True)
        If isData Then
            SBits(250)
        Else
            SBits(248)
        End If
        SBits(v And 240)
        SBits(v << 4)
        Pinio.PinSet(pA, False)
    ElseIf smode = 1 Then
        Pinio.PortDirectionHigh(pData, False)
        Pinio.PinSet(pA, isData)
        Pinio.PinSet(pB, False)
        Pinio.PortWriteHigh(pData, v)
        Pulse(pC)
        Pinio.PortWriteHigh(pData, v << 4)
        Pulse(pC)
    Else
        Pinio.PortDirection(pData, False)
        Pinio.PinSet(pA, isData)
        Pinio.PinSet(pB, False)
        Pinio.PortWrite(pData, v)
        Pulse(pC)
    End If
End Sub

Function SRead() As Byte
    SWait()
    Result = SReadRaw(True)
End Function

' Sets the graphic address: row 0..63 and word 0..15 (the extended instruction set stays selected).
Sub SPos(ByVal wd As Byte, ByVal row As Byte)
    SWrite(False, 128 Or row)
    SWrite(False, 128 Or wd)
End Sub

' Row and word of pixel (x, y) in graphic RAM.
Sub SMap(ByVal x As Word, ByVal y As Word, ByRef wd As Byte, ByRef row As Byte)
    wd = Byte(x >> 4)
    row = Byte(y)
    If folded And y >= 32 Then
        row = Byte(y - 32)
        wd = wd + 8
    End If
End Sub

' Loads graphic RAM word `wd` of `row` into wHi, wLo: read from the display, or from the shadow copy of the serial mode.
Sub SGetWord(ByVal wd As Byte, ByVal row As Byte)
    Dim v As Byte
    If smode = 2 Then
#if _maxram >= 1536
        v = row And 31
        wHi = shadow(Word(v) * 32 + Word(wd) * 2)
        wLo = shadow(Word(v) * 32 + Word(wd) * 2 + 1)
#endif
    Else
        SPos(wd, row)
        v = SRead()
        wHi = SRead()
        wLo = SRead()
    End If
End Sub

' Writes wHi, wLo to graphic RAM word `wd` of `row` (and to the shadow copy).
Sub SPutWord(ByVal wd As Byte, ByVal row As Byte)
    SPos(wd, row)
    SWrite(True, wHi)
    SWrite(True, wLo)
#if _maxram >= 1536
    If smode = 2 Then
        row = row And 31
        shadow(Word(row) * 32 + Word(wd) * 2) = wHi
        shadow(Word(row) * 32 + Word(wd) * 2 + 1) = wLo
    End If
#endif
End Sub

' Replaces the `n` bits of `w` whose leftmost is bit `top` (15 = the leftmost bit of the word) by the low `n` bits of `bits`.
Function Splice(ByVal w As Word, ByVal top As Byte, ByVal n As Byte, ByVal bits As Word) As Word
    Dim sh As Byte
    Dim m As Word
    sh = top + 1 - n
    m = ((Word(1) << n) - 1) << sh
    Result = (w And (m Xor 65535)) Or ((bits << sh) And m)
End Function

' Draws character `ch` (32..126) in the 6 x 8 cell at the text position, a row of eight pixel rows at a time: the six pixels of
' a row lie in one or two graphic RAM words, which are read, spliced and written back.
Sub SGlyph(ByVal ch As Byte)
    Dim base As Word
    Dim x0 As Word
    Dim k As Byte
    Dim i As Byte
    Dim p As Word
    Dim wd As Byte
    Dim row As Byte
    Dim o As Byte
    Dim n1 As Byte
    Dim ww As Word
    base = Word(ch - 32) * 5
    x0 = Word(tCol) * 6
    o = Byte(x0 And 15)
    k = 0
    While k < 8
        p = 0
        i = 0
        While i < 5
            p = (p << 1) Or ((Word(Font(base + i)) >> k) And 1)
            Inc(i)
        Wend
        p = p << 1
        SMap(x0, Word(tRow) * 8 + Word(k), wd, row)
        SGetWord(wd, row)
        ww = Word(wHi) * 256 + Word(wLo)
        If o <= 10 Then
            ww = Splice(ww, 15 - o, 6, p)
            wHi = Byte(ww >> 8)
            wLo = Byte(ww And 255)
            SPutWord(wd, row)
        Else
            n1 = 16 - o
            ww = Splice(ww, 15 - o, n1, p >> (6 - n1))
            wHi = Byte(ww >> 8)
            wLo = Byte(ww And 255)
            SPutWord(wd, row)
            SGetWord(wd + 1, row)
            ww = Word(wHi) * 256 + Word(wLo)
            ww = Splice(ww, 15, 6 - n1, p And ((Word(1) << (6 - n1)) - 1))
            wHi = Byte(ww >> 8)
            wLo = Byte(ww And 255)
            SPutWord(wd + 1, row)
        End If
        Inc(k)
    Wend
End Sub

' ---- Whole display ----

' Clears the graphic memory (and the text layer of the T6963C); the text cursor goes home.
Public Sub GlcdClear()
    Dim i As Word
    Dim n As Word
    Dim c As Byte
    Dim r As Byte
    tCol = 0
    tRow = 0
    If kind = 1 Then
        c = 0
        While c < 2
            r = 0
            While r < 8
                KsAt(c, r, 0)
                i = 0
                While i < 64
                    KsWrite(True, 0)
                    Inc(i)
                Wend
                Inc(r)
            Wend
            Inc(c)
        Wend
    ElseIf kind = 2 Then
        n = textHome + Word(cols) * (half >> 3)
        c = 0
        While c < 2
            TAddr(Word(c) << 15)
            TCmd(176)
            i = 0
            While i < n
                TWait(8)
                TRaw(False, 0)
                Inc(i)
            Wend
            TWait(8)
            TRaw(True, 178)
            Inc(c)
            If Not dual Then
                Break
            End If
        Wend
    ElseIf kind = 3 Then
        r = 0
        n = 64
        If folded Then
            n = 32
        End If
        While r < n
            SPos(0, r)
            c = 0
            While c < 32
                SWrite(True, 0)
                Inc(c)
            Wend
            Inc(r)
        Wend
#if _maxram >= 1536
        If smode = 2 Then
            i = 0
            While i < 1024
                shadow(i) = 0
                Inc(i)
            Wend
        End If
#endif
    End If
End Sub

' ---- Init ----

Function ClaimAll(ByVal bus As Byte, ByVal busPins As Byte, ByVal a As Byte, ByVal b As Byte, ByVal c As Byte, ByVal d As Byte, ByVal e As Byte, ByVal rst As Byte) As Boolean
    Dim k As Byte
    For k = 0 To 5
        used(k) = 0
    Next
    Result = False
    If Not ClaimBus(bus, busPins) Then
        Exit
    End If
    If Not Claim(a) Then
        Exit
    End If
    If Not Claim(b) Then
        Exit
    End If
    If Not Claim(c) Then
        Exit
    End If
    If Not ClaimOpt(d) Then
        Exit
    End If
    If Not ClaimOpt(e) Then
        Exit
    End If
    If Not ClaimOpt(rst) Then
        Exit
    End If
    pData = bus
    smode = 0
    pA = a
    pB = b
    pC = c
    pD = d
    pE = e
    pRst = rst
    penX = 0
    penY = 0
    tCol = 0
    tRow = 0
    Result = True
End Function

Public Function GlcdInitKs0108(ByVal bus As Byte, ByVal rs As Byte, ByVal rw As Byte, ByVal en As Byte, ByVal cs1 As Byte, ByVal cs2 As Byte, ByVal rst As Byte, ByVal selHigh As Boolean) As Byte
    Dim i As Byte
    Result = 0
    kind = 0
    If cs1 = 255 Or cs2 = 255 Then
        Exit
    End If
    If Not ClaimAll(bus, 8, rs, rw, en, cs1, cs2, rst) Then
        Exit
    End If
    csHigh = selHigh
    xres = 128
    yres = 64
    cols = 21
    MakeOutputs(5, False)
    ResetPulse()
    ' Display on and start line 0 on both chips, then clear.
    i = 0
    While i < 2
        KsSelect(i)
        KsWrite(False, 63)
        KsWrite(False, 192)
        Inc(i)
    Wend
    kind = 1
    GlcdClear()
    Result = 1
End Function

Function T6963Init(ByVal bus As Byte, ByVal wr As Byte, ByVal rd As Byte, ByVal ce As Byte, ByVal cd As Byte, ByVal rst As Byte, ByVal width As Word, ByVal height As Word, ByVal fontWidth As Byte, ByVal isDual As Boolean) As Byte
    Result = 0
    kind = 0
    If fontWidth <> 6 And fontWidth <> 8 Then
        Exit
    End If
    If width = 0 Or height = 0 Or width > 512 Or height > 256 Or width Mod fontWidth <> 0 Or height Mod 8 <> 0 Then
        Exit
    End If
    If isDual And height Mod 16 <> 0 Then
        Exit
    End If
    If width / fontWidth > 64 Then
        Exit
    End If
    If ce = 255 Then
        Exit
    End If
    If Not ClaimAll(bus, 8, cd, wr, rd, ce, 255, rst) Then
        Exit
    End If
    xres = Integer(width)
    yres = Integer(height)
    fw = fontWidth
    cols = Byte(width / fontWidth)
    dual = isDual
    half = height
    If isDual Then
        half = height >> 1
    End If
    textHome = Word(cols) * half
    MakeOutputs(4, True)
    ResetPulse()
    kind = 2
    ' Graphic home 0000h and text home just above it, both `cols` wide; OR mode with the internal CG ROM; the external CG RAM
    ' above the text area; graphic and text on, no cursor.
    TCmd2(66, 0, 0)
    TCmd2(67, cols, 0)
    TCmd2(64, Byte(textHome And 255), Byte(textHome >> 8))
    TCmd2(65, cols, 0)
    cgOff = Byte((textHome + Word(cols) * (half >> 3) + 2047) >> 11)
    TCmd2(34, cgOff, 0)
    TCmd(128)
    TCmd(156)
    GlcdClear()
    Result = 1
End Function

Public Function GlcdInitT6963(ByVal bus As Byte, ByVal wr As Byte, ByVal rd As Byte, ByVal ce As Byte, ByVal cd As Byte, ByVal rst As Byte, ByVal width As Word, ByVal height As Word, ByVal fontWidth As Byte) As Byte
    Result = T6963Init(bus, wr, rd, ce, cd, rst, width, height, fontWidth, False)
End Function

' Dual-scan screen (DUAL pin low): `height` is both halves together, so it must be a multiple of 16. The controller keeps the
' lower half 8000h above the upper one and displays both; the module draws into the right half.
Public Function GlcdInitT6963Dual(ByVal bus As Byte, ByVal wr As Byte, ByVal rd As Byte, ByVal ce As Byte, ByVal cd As Byte, ByVal rst As Byte, ByVal width As Word, ByVal height As Word, ByVal fontWidth As Byte) As Byte
    Result = T6963Init(bus, wr, rd, ce, cd, rst, width, height, fontWidth, True)
End Function

' One nibble on DB4..DB7 with an E pulse (4-bit mode start-up only).
Sub SendNibble(ByVal v As Byte)
    Pinio.PortDirectionHigh(pData, False)
    Pinio.PinSet(pA, False)
    Pinio.PinSet(pB, False)
    Pinio.PortWriteHigh(pData, v)
    Pulse(pC)
End Sub

' One start-up instruction and the wait after it.
Sub SCmd(ByVal v As Byte, ByVal us As Byte)
    SWrite(False, v)
    DelayUS(us)
End Sub

Function St7920Init(ByVal mode As Byte, ByVal bus As Byte, ByVal rs As Byte, ByVal rw As Byte, ByVal en As Byte, ByVal rst As Byte, ByVal isFolded As Boolean) As Byte
    Dim busPins As Byte
    Result = 0
    kind = 0
    busPins = 8
    If mode = 1 Then
        busPins = 4
    ElseIf mode = 2 Then
        busPins = 0
    End If
    If Not ClaimAll(bus, busPins, rs, rw, en, 255, 255, rst) Then
        Exit
    End If
    smode = mode
    folded = isFolded
    xres = 256
    cols = 42
    If isFolded Then
        xres = 128
        cols = 21
    End If
    yres = 64
    MakeOutputs(3, False)
    ResetPulse()
    kind = 3
    If mode = 1 Then
        ' The 4-bit initialisation of [p.35]: the function set with DL = 0, sent twice. The first nibble alone moves a
        ' controller that starts in the 8-bit mode over to the 4-bit mode.
        SendNibble(32)
        DelayUS(150)
        SCmd(32, 150)
        SCmd(32, 150)
    Else
        ' The 8-bit initialisation of [p.34].
        SCmd(48, 150)
        SCmd(48, 50)
    End If
    SCmd(12, 150)
    SWrite(False, 1)
    DelayMS(12)
    SWrite(False, 6)
    ' Then the extended set (RE = 1) and graphic display on (G = 1); in the 4-bit mode DL stays 0.
    If mode = 1 Then
        SWrite(False, 36)
        SWrite(False, 38)
    Else
        SWrite(False, 52)
        SWrite(False, 54)
    End If
    GlcdClear()
    Result = 1
End Function


Public Function GlcdInitSt7920(ByVal bus As Byte, ByVal rs As Byte, ByVal rw As Byte, ByVal en As Byte, ByVal rst As Byte, ByVal isFolded As Boolean) As Byte
    Result = St7920Init(0, bus, rs, rw, en, rst, isFolded)
End Function

' 4-bit parallel interface (the controller's function set DL = 0): DB4..DB7 go to the upper four pins of port B or C
' (`bus` 8 or 16); the lower four pins of the port are left alone, and DB0..DB3 stay unconnected.
Public Function GlcdInitSt7920x4(ByVal bus As Byte, ByVal rs As Byte, ByVal rw As Byte, ByVal en As Byte, ByVal rst As Byte, ByVal isFolded As Boolean) As Byte
    Result = St7920Init(1, bus, rs, rw, en, rst, isFolded)
End Function

' Serial interface (PSB low): `cs` is the RS pin of the module, `sid` its R/W pin and `sclk` its E pin. The display cannot be
' read back in this mode, so the module keeps a copy of the graphic RAM (1 KB, 128 x 64 only); a part with too little RAM
' returns 0.
Public Function GlcdInitSt7920Serial(ByVal cs As Byte, ByVal sid As Byte, ByVal sclk As Byte, ByVal rst As Byte) As Byte
    Result = 0
#if _maxram >= 1536
    Result = St7920Init(2, 255, cs, sid, sclk, rst, True)
#endif
End Function

' ---- Pixels ----

' Sets (`on` True) or clears the pixel; the caller has checked the range.
Sub PutPixel(ByVal x As Word, ByVal y As Word, ByVal on As Boolean)
    Dim v As Byte
    Dim m As Byte
    Dim col As Byte
    Dim w As Byte
    Dim row As Byte
    Dim b As Byte
    If kind = 1 Then
        col = Byte(x And 63)
        m = 1 << Byte(y And 7)
        KsAt(Byte(x >> 6), Byte(y >> 3), col)
        v = KsRead()
        v = KsRead()
        KsWrite(False, 64 Or col)
        If on Then
            v = v Or m
        Else
            v = v And (m Xor 255)
        End If
        KsWrite(True, v)
    ElseIf kind = 2 Then
        b = TPoint(x, y)
        If on Then
            b = b Or 248
        Else
            b = b Or 240
        End If
        TCmd(b)
    ElseIf kind = 3 Then
        SMap(x, y, w, row)
        SGetWord(w, row)
        m = 1 << (7 - Byte(x And 7))
        If (x And 8) = 0 Then
            If on Then
                wHi = wHi Or m
            Else
                wHi = wHi And (m Xor 255)
            End If
        Else
            If on Then
                wLo = wLo Or m
            Else
                wLo = wLo And (m Xor 255)
            End If
        End If
        SPutWord(w, row)
    End If
End Sub

Sub GetPixelBit(ByVal x As Word, ByVal y As Word, ByRef isSet As Boolean)
    Dim v As Byte
    Dim b As Byte
    Dim w As Byte
    Dim row As Byte
    isSet = False
    If kind = 1 Then
        KsAt(Byte(x >> 6), Byte(y >> 3), Byte(x And 63))
        v = KsRead()
        v = KsRead()
        isSet = (v And (1 << Byte(y And 7))) <> 0
    ElseIf kind = 2 Then
        b = TPoint(x, y)
        TCmd(197)
        v = TReadData()
        isSet = (v And (1 << b)) <> 0
    ElseIf kind = 3 Then
        SMap(x, y, w, row)
        SGetWord(w, row)
        If (x And 8) = 0 Then
            isSet = (wHi And (1 << (7 - Byte(x And 7)))) <> 0
        Else
            isSet = (wLo And (1 << (7 - Byte(x And 7)))) <> 0
        End If
    End If
End Sub

Function InRange(ByVal x As Integer, ByVal y As Integer) As Boolean
    Result = kind <> 0 And x >= 0 And y >= 0 And x < xres And y < yres
End Function

Public Sub GlcdPlot(ByVal x As Integer, ByVal y As Integer)
    If InRange(x, y) Then
        PutPixel(Word(x), Word(y), True)
    End If
End Sub

Public Sub GlcdUnplot(ByVal x As Integer, ByVal y As Integer)
    If InRange(x, y) Then
        PutPixel(Word(x), Word(y), False)
    End If
End Sub

' 1 for a set pixel, 0 for a clear one or one outside the display.
Public Function GlcdPixel(ByVal x As Integer, ByVal y As Integer) As Byte
    Dim b As Boolean
    Result = 0
    If InRange(x, y) Then
        GetPixelBit(Word(x), Word(y), b)
        If b Then
            Result = 1
        End If
    End If
End Function

' Sets or clears one pixel by value (`on` True sets it).
Public Sub GlcdSetPixel(ByVal x As Integer, ByVal y As Integer, ByVal on As Boolean)
    If InRange(x, y) Then
        PutPixel(Word(x), Word(y), on)
    End If
End Sub

' ---- Bytes (LCDwrite / LCDread) ----
' KS0108: `row` is the page 0..7 and `col` the x position 0..127, bit 0 on top. T6963C: `row` is the pixel row and `col` the
' byte column 0..xres/fontWidth-1. ST7920: `row` is the pixel row 0..63 and `col` the byte column 0..15 (0..31 unfolded: x / 8).
' Anything outside the display is ignored (read as 0).

Public Sub GlcdWriteByte(ByVal row As Byte, ByVal col As Byte, ByVal v As Byte)
    Dim w As Byte
    Dim r As Byte
    If kind = 1 Then
        If row < 8 And col < 128 Then
            KsAt(col >> 6, row, col And 63)
            KsWrite(True, v)
        End If
    ElseIf kind = 2 Then
        If row < yres And col < cols Then
            TAddr(TRowAddr(row) + col)
            TCmd1(196, v)
        End If
    ElseIf kind = 3 Then
        If row < 64 And col < (xres >> 3) Then
            SMap(Word(col) << 3, row, w, r)
            ' Both bytes of the word are rewritten: the other half is read first.
            SGetWord(w, r)
            If (col And 1) = 0 Then
                wHi = v
            Else
                wLo = v
            End If
            SPutWord(w, r)
        End If
    End If
End Sub

Public Function GlcdReadByte(ByVal row As Byte, ByVal col As Byte) As Byte
    Dim w As Byte
    Dim r As Byte
    Dim v As Byte
    Result = 0
    If kind = 1 Then
        If row < 8 And col < 128 Then
            KsAt(col >> 6, row, col And 63)
            v = KsRead()
            Result = KsRead()
        End If
    ElseIf kind = 2 Then
        If row < yres And col < cols Then
            TAddr(TRowAddr(row) + col)
            TCmd(197)
            Result = TReadData()
        End If
    ElseIf kind = 3 Then
        If row < 64 And col < (xres >> 3) Then
            SMap(Word(col) << 3, row, w, r)
            SGetWord(w, r)
            Result = wHi
            If (col And 1) <> 0 Then
                Result = wLo
            End If
        End If
    End If
End Function

' ---- Lines, boxes, circles ----

' Straight line from (x0, y0) to (x1, y1), both ends included (Bresenham); `on` False erases. The end becomes the pen position of
' GlcdLineTo.
Public Sub GlcdLine(ByVal on As Boolean, ByVal x0 As Integer, ByVal y0 As Integer, ByVal x1 As Integer, ByVal y1 As Integer)
    Dim dx As Integer
    Dim dy As Integer
    Dim sx As Integer
    Dim sy As Integer
    Dim e As Integer
    Dim e2 As Integer
    penX = x1
    penY = y1
    dx = x1 - x0
    sx = 1
    If dx < 0 Then
        dx = -dx
        sx = -1
    End If
    dy = y0 - y1
    sy = 1
    If dy > 0 Then
        dy = -dy
        sy = -1
    End If
    e = dx + dy
    While True
        GlcdSetPixel(x0, y0, on)
        If x0 = x1 And y0 = y1 Then
            Exit
        End If
        e2 = e + e
        If e2 >= dy Then
            e = e + dy
            x0 = x0 + sx
        End If
        If e2 <= dx Then
            e = e + dx
            y0 = y0 + sy
        End If
    Wend
End Sub

' A line from the end of the previous GlcdLine / GlcdLineTo (or (0, 0) after init) to (x, y).
Public Sub GlcdLineTo(ByVal on As Boolean, ByVal x As Integer, ByVal y As Integer)
    GlcdLine(on, penX, penY, x, y)
End Sub

' Outline of a square `size` pixels on a side centred on (x, y).
Public Sub GlcdBox(ByVal on As Boolean, ByVal x As Integer, ByVal y As Integer, ByVal size As Byte)
    Dim h As Integer
    Dim x0 As Integer
    Dim y0 As Integer
    Dim x1 As Integer
    Dim y1 As Integer
    If size = 0 Then
        GlcdSetPixel(x, y, on)
        Exit
    End If
    h = Integer(size >> 1)
    x0 = x - h
    y0 = y - h
    x1 = x0 + Integer(size) - 1
    y1 = y0 + Integer(size) - 1
    GlcdLine(on, x0, y0, x1, y0)
    GlcdLine(on, x1, y0, x1, y1)
    GlcdLine(on, x1, y1, x0, y1)
    GlcdLine(on, x0, y1, x0, y0)
End Sub

' Circle outline of radius `r` centred on (x, y) (midpoint algorithm).
Public Sub GlcdCircle(ByVal on As Boolean, ByVal x As Integer, ByVal y As Integer, ByVal r As Byte)
    Dim cx As Integer
    Dim cy As Integer
    Dim e As Integer
    cx = Integer(r)
    cy = 0
    e = 1 - cx
    While cx >= cy
        GlcdSetPixel(x + cx, y + cy, on)
        GlcdSetPixel(x - cx, y + cy, on)
        GlcdSetPixel(x + cx, y - cy, on)
        GlcdSetPixel(x - cx, y - cy, on)
        GlcdSetPixel(x + cy, y + cx, on)
        GlcdSetPixel(x - cy, y + cx, on)
        GlcdSetPixel(x + cy, y - cx, on)
        GlcdSetPixel(x - cy, y - cx, on)
        cy = cy + 1
        If e < 0 Then
            e = e + cy + cy + 1
        Else
            cx = cx - 1
            e = e + cy + cy - cx - cx + 1
        End If
    Wend
End Sub

' ---- Text ----

' Moves the text position to column `col`, row `row` (0, 0 = top left).
Public Sub GlcdTextAt(ByVal col As Byte, ByVal row As Byte)
    tCol = col
    tRow = row
End Sub

' A full line goes on to the next row, and the end of the display wraps to the top. `cols` is the text columns of every controller
' (set at init: xres / 6, or xres / fontWidth for the T6963C).
Sub WrapText()
    If tCol >= cols Then
        tCol = 0
        Inc(tRow)
    End If
    If tRow >= Byte(yres >> 3) Then
        tRow = 0
    End If
End Sub

' Draws one character (code 32..126, else '?') at the text position and advances it; a line that is full wraps to the next,
' and the end of the display wraps to the top.
Public Sub GlcdWriteChar(ByVal ch As Byte)
    Dim base As Word
    Dim i As Byte
    Dim b As Byte
    If kind = 0 Then
        Exit
    End If
    If ch < 32 Or ch > 126 Then
        ch = 63
    End If
    WrapText()
    If kind = 2 Then
        TAddr(TTextAddr())
        TCmd1(192, ch - 32)
    ElseIf kind = 3 Then
        SGlyph(ch)
    Else
        base = Word(ch - 32) * 5
        i = 0
        While i < 6
            b = 0
            If i < 5 Then
                b = Font(base + i)
            End If
            GlcdWriteByte(tRow, tCol * 6 + i, b)
            Inc(i)
        Wend
    End If
    Inc(tCol)
End Sub

Public Sub GlcdWrite(ByRefConst s As String(80))
    Dim i As Byte
    i = 0
    While s(i) <> #0
        GlcdWriteChar(Byte(s(i)))
        Inc(i)
    Wend
End Sub

Const Pow10(10) As LongWord = (1000000000, 100000000, 10000000, 1000000, 100000, 10000, 1000, 100, 10, 1)

' Decimal digits of `v` from the power of ten at index `first` of Pow10, no leading zeros (the last digit is always sent).
Sub Digits(ByVal v As LongWord, ByVal first As Byte)
    Dim started As Boolean
    Dim digit As Byte
    Dim d As LongWord
    started = False
    While first < 10
        d = Pow10(first)
        digit = 48
        While v >= d
            v = v - d
            Inc(digit)
        Wend
        If digit > 48 Or started Or first = 9 Then
            GlcdWriteChar(digit)
            started = True
        End If
        Inc(first)
    Wend
End Sub

' Unsigned decimal, no leading zeros.
Public Sub GlcdWriteWord(ByVal v As Word)
    Digits(LongWord(v), 5)
End Sub

' Unsigned decimal of 0..4294967295, no leading zeros.
Public Sub GlcdWriteLong(ByVal v As LongWord)
    Digits(v, 0)
End Sub

' Signed decimal of -32768..32767.
Public Sub GlcdWriteInt(ByVal v As Integer)
    If v < 0 Then
        GlcdWriteChar(45)
        GlcdWriteWord(Word(0) - Word(v))
    Else
        GlcdWriteWord(Word(v))
    End If
End Sub

' Signed decimal of a 32-bit value.
Public Sub GlcdWriteLongInt(ByVal v As LongInt)
    If v < 0 Then
        GlcdWriteChar(45)
        GlcdWriteLong(LongWord(0) - LongWord(v))
    Else
        GlcdWriteLong(LongWord(v))
    End If
End Sub

' One hexadecimal digit (upper case) of the low four bits of `h`.
Sub HexDigit(ByVal h As Byte)
    h = h And 15
    If h > 9 Then
        h = h + 7
    End If
    GlcdWriteChar(48 + h)
End Sub

' Two hexadecimal digits (upper case).
Public Sub GlcdWriteHex(ByVal v As Byte)
    HexDigit(v >> 4)
    HexDigit(v)
End Sub

' Four hexadecimal digits.
Public Sub GlcdWriteHexWord(ByVal v As Word)
    GlcdWriteHex(Byte(v >> 8))
    GlcdWriteHex(Byte(v And 255))
End Sub

' ---- T6963C extras (Toshiba_Command, Toshiba_UDG) ----

' Sends a command byte with no data, one data byte, or two (the data first, as the controller wants). Ignored on the other
' controllers. See the command table [T6963C p.11]; the graphic and text areas set at init are the module's, so commands
' that move them break the drawing routines.
Public Sub GlcdCommand(ByVal c As Byte)
    If kind = 2 Then
        TCmd(c)
    End If
End Sub

Public Sub GlcdCommand(ByVal c As Byte, ByVal d1 As Byte)
    If kind = 2 Then
        TCmd1(c, d1)
    End If
End Sub

Public Sub GlcdCommand(ByVal c As Byte, ByVal d1 As Byte, ByVal d2 As Byte)
    If kind = 2 Then
        TCmd2(c, d1, d2)
    End If
End Sub

' Defines user character `code` 128..255 (shown with that code in the text layer) from eight row bytes, top row first, in the
' external CG RAM above the text area; the internal ROM keeps codes 0..127 (the text layer writes ASCII - 32 for printable characters, so a
' code of 128 or more is written with GlcdWriteCode).
Public Sub GlcdUdg(ByVal code As Byte, ByRefConst d() As Byte)
    Dim i As Byte
    Dim h As Byte
    If kind <> 2 Or code < 128 Then
        Exit
    End If
    h = 0
    While h < 2
        TAddr((Word(cgOff) << 11) + Word(code) * 8 + (Word(h) << 15))
        i = 0
        While i < 8
            TCmd1(192, d(i))
            Inc(i)
        Wend
        Inc(h)
        If Not dual Then
            Break
        End If
    Wend
End Sub

' Writes a raw character code (0..255) into the text layer at the text position and advances it (T6963C only).
Public Sub GlcdWriteCode(ByVal code As Byte)
    If kind <> 2 Then
        Exit
    End If
    WrapText()
    TAddr(TTextAddr())
    TCmd1(192, code)
    Inc(tCol)
End Sub
