Module Oled
Include "i2c"
Include "spi"
' Monochrome OLED with an SSD1309 driver, 128 x 64 pixels (Solomon Systech SSD1309 Rev 1.1, Jul 2011;
' section numbers below are from it). Two ways to connect it, chosen by the init routine:
'   OledInitI2c(addr, res)           I2C [8.1.5]: 7-bit address 0x3C (SA0 = D/C# pin low) or 0x3D.
'   OledInitSpi(dc, cs, res)         4-wire SPI [8.1.3]: SCLK, SDIN, D/C#, CS#.
' The bus itself is set up by the caller first, with the `I2c` module (at most 400 kHz: SCL cycle
' time 2.5 us [Table 13-6]) or the `Spi` module (mode 0, at most 10 MHz: 100 ns cycle [Table 13-4]; the
' data is taken on the rising edge of SCLK, and D/C# on every eighth clock [8.1.3]). The module owns
' no pins but D/C#, CS# and RES#, which are port pins numbered 0..23 (RA0..RA7 = 0..7, RB0..RB7 =
' 8..15, RC0..RC7 = 16..23); 255 for CS# or RES# means "not controlled by the module" (tied, or
' absent). The panel supply VCC (about 12 V on the SSD1309) is external: switch it on after RES#, as
' in [8.8], and the picture appears 100 ms after the display-on command.
'
' The controller is used in horizontal addressing mode [10.3]: after each data byte the column
' pointer advances and wraps to the next page at the end of the line. A page is 8 pixel rows, a byte is
' one column of a page with bit 0 on top. There is no frame buffer (the serial interfaces are
' write-only [8.1.3]), so there is no single-pixel call: draw whole bytes with OledGoto and OledData.
'
' Text uses a 5 x 7 pixel font drawn in 6 x 8 pixel cells (21 characters on each of 8 lines) for the
' ASCII codes 32..126; it is the public domain X11 "5x7" fixed font, not data from the data sheet.
'
' Registers left at their Reset value [8.4]: 128 x 64 (MUX 64), SEG0 = column 0, COM0 first, start
' line 0, contrast 7Fh; the COM pin configuration (DAh) reset value is the alternative one used by
' common 128 x 64 modules. If a module shows every other line or an upside down picture, use OledFlip.
' The module is not reentrant: do not use it from a handler and from the main program, nor an
' interrupt handler that uses `I2c` or `Spi`.

' The font: 5 column bytes for each code 32..126 (475 bytes), bit 0 on top. It lives in program memory.
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

' Byte `idx` (0..474) of the font table.
Public Function FontByte(ByVal idx As Word) As Byte
    Result = Font(idx)
End Function
Dim mode As Byte
Dim addr7 As Byte
Dim pDc As Byte
Dim pCs As Byte
Dim err As Byte


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
#if _has(LATB)
        If level Then
            LATB = LATB Or m
        Else
            LATB = LATB And (m Xor 255)
        End If
#endif
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
    Dim n As Byte
    n = (1 << (pin And 7)) Xor 255
    If pin < 8 Then
        ANSELA = ANSELA And n
        TRISA = TRISA And n
    ElseIf pin < 16 Then
#if _has(LATB)
        ANSELB = ANSELB And n
        TRISB = TRISB And n
#endif
    Else
        ANSELC = ANSELC And n
        TRISC = TRISC And n
    End If
End Sub

' Opens a transfer: data bytes follow (isData) or command bytes. I2C: Start, address + W, control
' byte with Co = 0 and D/C# = isData, so every following byte is of that kind until the Stop [8.1.5.2].
' SPI: D/C# set, CS# low.
Sub Begin(ByVal isData As Boolean)
    Dim s As Byte
    If mode = 1 Then
        s = I2c.I2cStart()
        If s = 0 Then
            s = I2c.I2cSend(addr7 << 1)
        End If
        If s = 0 Then
            If isData Then
                s = I2c.I2cSend(64)
            Else
                s = I2c.I2cSend(0)
            End If
        End If
        If s <> 0 And err = 0 Then
            err = s
        End If
    ElseIf mode = 2 Then
        PinSet(pDc, isData)
        If pCs <> 255 Then
            PinSet(pCs, False)
        End If
    End If
End Sub

Sub Put(ByVal b As Byte)
    Dim s As Byte
    If mode = 1 Then
        If err = 0 Then
            s = I2c.I2cSend(b)
            If s <> 0 Then
                err = s
            End If
        End If
    ElseIf mode = 2 Then
        Spi.SpiWrite(b)
    End If
End Sub

Sub Finish()
    Dim s As Byte
    If mode = 1 Then
        s = I2c.I2cStop()
        If s <> 0 And err = 0 Then
            err = s
        End If
    ElseIf mode = 2 Then
        If pCs <> 255 Then
            PinSet(pCs, True)
        End If
    End If
End Sub

' Sends a command of one to three bytes (`n` = 1..3; the command byte and its arguments).
Sub Cmd(ByVal n As Byte, ByVal c As Byte, ByVal a As Byte, ByVal b As Byte)
    If mode = 0 Then
        Exit
    End If
    Begin(False)
    Put(c)
    If n > 1 Then
        Put(a)
    End If
    If n > 2 Then
        Put(b)
    End If
    Finish()
End Sub

' Optional reset pulse on RES#: low for 10 us (at least 3 us [Table 13-1]), then high.
Sub Reset(ByVal res As Byte)
    If res <> 255 Then
        PinSet(res, False)
        PinOutput(res)
        DelayUS(10)
        PinSet(res, True)
        DelayMS(5)
    End If
End Sub

' Next data byte goes to column `col` (0..127) of page `page` (0..7, a page is 8 pixel rows) [10.4, 10.5].
Public Sub OledGoto(ByVal col As Byte, ByVal page As Byte)
    If col > 127 Or page > 7 Then
        Exit
    End If
    Cmd(3, 33, col, 127)
    Cmd(3, 34, page, 7)
End Sub

' Next character goes to character cell `x` (0..20) of text line `line` (0..7).
Public Sub OledTextGoto(ByVal x As Byte, ByVal line As Byte)
    If x > 20 Then
        Exit
    End If
    OledGoto(x * 6, line)
End Sub

' One column byte (bit 0 on top) at the current position.
Public Sub OledData(ByVal b As Byte)
    If mode = 0 Then
        Exit
    End If
    Begin(True)
    Put(b)
    Finish()
End Sub

' Fills the whole RAM with `pattern` (0 clears) and goes back to column 0, page 0.
Public Sub OledFill(ByVal pattern As Byte)
    Dim n As Word
    If mode = 0 Then
        Exit
    End If
    OledGoto(0, 0)
    Begin(True)
    n = 0
    While n < 1024
        Put(pattern)
        Inc(n)
    Wend
    Finish()
    OledGoto(0, 0)
End Sub

' The commands every start needs: unlock (FDh 12h), display off, horizontal addressing (20h 00h), full
' column and page range (21h 0 127, 22h 0 7), RAM content shown (A4h), normal polarity (A6h); then the
' RAM is cleared and the display switched on (AFh).
Sub Setup()
    Cmd(2, 253, 18, 0)
    Cmd(1, 174, 0, 0)
    Cmd(2, 32, 0, 0)
    Cmd(3, 33, 0, 127)
    Cmd(3, 34, 0, 7)
    Cmd(1, 164, 0, 0)
    Cmd(1, 166, 0, 0)
    OledFill(0)
    Cmd(1, 175, 0, 0)
End Sub

' Starts the display on I2C at 7-bit address `addr` (0x3C = 60 or 0x3D = 61), RES# on `res`
' (255 = none). `I2cInit` must have been called. Returns 1 when every byte was acknowledged, else 0
' (OledStatus gives the I2c status code).
Public Function OledInitI2c(ByVal addr As Byte, ByVal res As Byte) As Byte
    Result = 0
    If addr > 127 Or (res <> 255 And res > 23) Then
        Exit
    End If
    err = 0
    addr7 = addr
    mode = 1
    Reset(res)
    Setup()
    If err = 0 Then
        Result = 1
    End If
End Function

' Starts the display on 4-wire SPI with D/C# on `dc`, CS# on `cs` and RES# on `res` (255 for `cs` or
' `res` = not controlled). `SpiInit` must have been called (mode 0, at most 10 MHz). Returns 1, or 0
' for a pin above 23 or a pin used twice.
Public Function OledInitSpi(ByVal dc As Byte, ByVal cs As Byte, ByVal res As Byte) As Byte
    Result = 0
    If dc > 23 Or (cs <> 255 And cs > 23) Or (res <> 255 And res > 23) Then
        Exit
    End If
    If dc = cs Or dc = res Then
        Exit
    End If
    If cs <> 255 And cs = res Then
        Exit
    End If
    err = 0
    pDc = dc
    pCs = cs
    mode = 2
    PinOutput(dc)
    If cs <> 255 Then
        PinSet(cs, True)
        PinOutput(cs)
    End If
    Reset(res)
    Setup()
    Result = 1
End Function

' 0 when all I2C bytes since the init (or the last OledClearStatus) were acknowledged, else the first
' I2c status code (3 = no acknowledge). Always 0 for SPI, which has no acknowledge.
Public Function OledStatus() As Byte
    Result = err
End Function

Public Sub OledClearStatus()
    err = 0
End Sub

' Display on (AFh) or off, sleep mode (AEh); the RAM keeps its content.
Public Sub OledOn(ByVal isOn As Boolean)
    If isOn Then
        Cmd(1, 175, 0, 0)
    Else
        Cmd(1, 174, 0, 0)
    End If
End Sub

' Contrast 0..255 (81h; Reset value 7Fh).
Public Sub OledContrast(ByVal level As Byte)
    Cmd(2, 129, level, 0)
End Sub

' Inverse display (A7h) or normal (A6h).
Public Sub OledInvert(ByVal inverse As Boolean)
    If inverse Then
        Cmd(1, 167, 0, 0)
    Else
        Cmd(1, 166, 0, 0)
    End If
End Sub

' Every pixel on regardless of the RAM (A5h), or the RAM content (A4h).
Public Sub OledAllOn(ByVal allOn As Boolean)
    If allOn Then
        Cmd(1, 165, 0, 0)
    Else
        Cmd(1, 164, 0, 0)
    End If
End Sub

' Turns the picture through 180 degrees: segment re-map A1h and COM scan C8h (rotated = True), or A0h
' and C0h. Takes effect for data written afterwards (the RAM is not rewritten).
Public Sub OledFlip(ByVal rotated As Boolean)
    If rotated Then
        Cmd(1, 161, 0, 0)
        Cmd(1, 200, 0, 0)
    Else
        Cmd(1, 160, 0, 0)
        Cmd(1, 192, 0, 0)
    End If
End Sub

Public Sub OledClear()
    OledFill(0)
End Sub

' One character at the current position (codes outside 32..126 show '?'), five columns of font and
' one blank column.
Public Sub OledWriteChar(ByVal ch As Byte)
    Dim base As Word
    Dim i As Byte
    If mode = 0 Then
        Exit
    End If
    If ch < 32 Or ch > 126 Then
        ch = 63
    End If
    base = Word(ch - 32) * 5
    Begin(True)
    i = 0
    While i < 5
        Put(FontByte(base + i))
        Inc(i)
    Wend
    Put(0)
    Finish()
End Sub

Public Sub OledWrite(ByRefConst s As String(80))
    Dim i As Byte
    i = 0
    While s(i) <> #0
        OledWriteChar(Byte(s(i)))
        Inc(i)
    Wend
End Sub

' Unsigned decimal, no leading zeros.
Public Sub OledWriteWord(ByVal v As Word)
    Dim started As Boolean
    Dim d As Word
    Dim digit As Byte
    started = False
    d = 10000
    While d > 0
        digit = Byte(v / d)
        v = v Mod d
        If digit > 0 Or started Or d = 1 Then
            OledWriteChar(48 + digit)
            started = True
        End If
        d = d / 10
    Wend
End Sub

' Two hexadecimal digits.
Public Sub OledWriteHex(ByVal v As Byte)
    Dim h As Byte
    h = v >> 4
    If h > 9 Then
        h = h + 7
    End If
    OledWriteChar(48 + h)
    h = v And 15
    If h > 9 Then
        h = h + 7
    End If
    OledWriteChar(48 + h)
End Sub

' ---- Bitmaps and pixel drawing ----

' Draws an image straight to the display (no frame buffer): `w` columns starting at column `x`,
' page `page` (0..7), one byte per column, bit 0 on top, so the image is 8 pixel rows high; a taller
' image is drawn one page-high strip at a time with the `Const` array of that strip. The columns past
' the right edge (127) are dropped. Example: Oled.OledBitmap(0, 2, 8, Logo).
Public Sub OledBitmap(ByVal x As Byte, ByVal page As Byte, ByVal w As Byte, ByRefConst d() As Byte)
    Dim i As Byte
    If mode = 0 Or x > 127 Or page > 7 Then
        Exit
    End If
    If w > 128 - x Then
        w = 128 - x
    End If
    OledGoto(x, page)
    Begin(True)
    i = 0
    While i < w
        Put(d(i))
        Inc(i)
    Wend
    Finish()
End Sub

' The frame buffer: the whole picture, 1024 bytes in the same layout as the display RAM (byte
' x + 128 * page, bit 0 on top). The pixel commands change the buffer only; OledUpdate sends it. A
' program that never calls a pixel command does not link the buffer.
Dim fb(1024) As Byte

' Sets (on = True) or clears one pixel of the frame buffer; x 0..127 left to right, y 0..63 top to
' bottom. A point outside the screen is ignored.
Public Sub OledPixel(ByVal x As Byte, ByVal y As Byte, ByVal on As Boolean)
    Dim i As Word
    Dim m As Byte
    If x > 127 Or y > 63 Then
        Exit
    End If
    i = Word(y >> 3) * 128 + x
    m = 1 << (y And 7)
    If on Then
        fb(i) = fb(i) Or m
    Else
        fb(i) = fb(i) And (m Xor 255)
    End If
End Sub

' The pixel at x, y as 1 or 0 (0 outside the screen).
Public Function OledPoint(ByVal x As Byte, ByVal y As Byte) As Byte
    Result = 0
    If x < 128 And y < 64 Then
        If (fb(Word(y >> 3) * 128 + x) And (1 << (y And 7))) <> 0 Then
            Result = 1
        End If
    End If
End Function

' Sets every byte of the frame buffer to `pattern` (0 = all pixels off, 255 = all on).
Public Sub OledBufFill(ByVal pattern As Byte)
    Dim i As Word
    i = 0
    While i < 1024
        fb(i) = pattern
        Inc(i)
    Wend
End Sub

Public Sub OledBufClear()
    OledBufFill(0)
End Sub

' Sends the frame buffer to the display (1024 bytes in one transfer).
Public Sub OledUpdate()
    Dim i As Word
    If mode = 0 Then
        Exit
    End If
    OledGoto(0, 0)
    Begin(True)
    i = 0
    While i < 1024
        Put(fb(i))
        Inc(i)
    Wend
    Finish()
End Sub

' Straight line from (x0, y0) to (x1, y1), both ends included (Bresenham). Parts outside the screen
' are not drawn.
Public Sub OledLine(ByVal x0 As Integer, ByVal y0 As Integer, ByVal x1 As Integer, ByVal y1 As Integer, ByVal on As Boolean)
    Dim dx As Integer
    Dim dy As Integer
    Dim sx As Integer
    Dim sy As Integer
    Dim e As Integer
    Dim e2 As Integer
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
        If x0 >= 0 And x0 < 128 And y0 >= 0 And y0 < 64 Then
            OledPixel(Byte(x0), Byte(y0), on)
        End If
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

' Rectangle outline with its top left corner at (x, y), `w` wide and `h` high (both at least 1; keep
' x + w and y + h within 255, as the sums wrap). OledClear and OledFill clear the display, not the frame buffer.
Public Sub OledRect(ByVal x As Byte, ByVal y As Byte, ByVal w As Byte, ByVal h As Byte, ByVal on As Boolean)
    Dim i As Byte
    If w = 0 Or h = 0 Then
        Exit
    End If
    i = 0
    While i < w
        OledPixel(x + i, y, on)
        OledPixel(x + i, y + h - 1, on)
        Inc(i)
    Wend
    i = 0
    While i < h
        OledPixel(x, y + i, on)
        OledPixel(x + w - 1, y + i, on)
        Inc(i)
    Wend
End Sub

' Filled rectangle, same arguments as OledRect.
Public Sub OledFillRect(ByVal x As Byte, ByVal y As Byte, ByVal w As Byte, ByVal h As Byte, ByVal on As Boolean)
    Dim i As Byte
    Dim j As Byte
    j = 0
    While j < h
        i = 0
        While i < w
            OledPixel(x + i, y + j, on)
            Inc(i)
        Wend
        Inc(j)
    Wend
End Sub

' Draws a bitmap into the frame buffer at pixel position (x, y): `w` columns of `d`, each one byte
' per 8 rows (bit 0 on top) and `pages` such byte rows one after the other (`d` holds w * pages
' bytes, the first row of columns first). Pixels set in the image are set in the buffer, clear ones
' are left alone (or cleared when `opaque` is True). The position is any pixel, not only page edges.
Public Sub OledBufBitmap(ByVal x As Byte, ByVal y As Byte, ByVal w As Byte, ByVal pages As Byte, ByVal opaque As Boolean, ByRefConst d() As Byte)
    Dim c As Byte
    Dim r As Byte
    Dim b As Byte
    Dim k As Byte
    Dim idx As Word
    idx = 0
    r = 0
    While r < pages
        c = 0
        While c < w
            b = d(idx)
            k = 0
            While k < 8
                If (b And (1 << k)) <> 0 Then
                    OledPixel(x + c, y + r * 8 + k, True)
                ElseIf opaque Then
                    OledPixel(x + c, y + r * 8 + k, False)
                End If
                Inc(k)
            Wend
            Inc(idx)
            Inc(c)
        Wend
        Inc(r)
    Wend
End Sub

' Writes one character into the frame buffer with its top left pixel at (x, y), in the 5 x 7 font
' (a 6 x 8 cell with the blank column and row); set pixels only, so text can be laid over a picture.
Public Sub OledBufChar(ByVal x As Byte, ByVal y As Byte, ByVal ch As Byte, ByVal on As Boolean)
    Dim base As Word
    Dim c As Byte
    Dim b As Byte
    Dim k As Byte
    If ch < 32 Or ch > 126 Then
        ch = 63
    End If
    base = Word(ch - 32) * 5
    c = 0
    While c < 5
        b = Font(base + c)
        k = 0
        While k < 7
            If (b And (1 << k)) <> 0 Then
                OledPixel(x + c, y + k, on)
            End If
            Inc(k)
        Wend
        Inc(c)
    Wend
End Sub

Public Sub OledBufText(ByVal x As Byte, ByVal y As Byte, ByVal on As Boolean, ByRefConst s As String(80))
    Dim i As Byte
    i = 0
    While s(i) <> #0
        OledBufChar(x, y, Byte(s(i)), on)
        x = x + 6
        Inc(i)
    Wend
End Sub
