Module Epaper
Include "pinio"
Include "spi"
' WeAct 2.13" (122 x 250) and 2.9" (128 x 296) e-paper modules, black / white and black / white / red, 4-wire SPI. All four use the
' Solomon Systech SSD1680 driver (SSD1680 Rev 0.14, Jun 2019; section and page numbers below are from it). The panel data sheets are in
' docs/ (WeAct-2.9-BWR-panel.pdf, WeAct-2.13-BWR-panel.pdf; the two black / white ones are scanned pictures) and the vendor's example
' code is github.com/WeActStudio/WeActStudio.EpaperModule. Facts that only the vendor's code gives (not the SSD1680 data sheet) are marked [WeAct].
'
'   EpdInit(size, threeColour, dc, cs, res, busy)   size 0 = 2.13", 1 = 2.9"; threeColour True for the black / white / red panels
'
' The bus is set up by the caller first with the `Spi` module: mode 0 or 3 (the data is taken on the rising edge of SCL, D7 first, D/C#
' held for the whole byte [6.1.2]), at most 20 MHz [12.1] (the write cycle is 50 ns). The module owns D/C#, CS#, RES# and BUSY, port pins
' numbered 0..23 as in `Pinio` (CS# may be 255 when the module ties it low; RES# may be 255; BUSY is needed). The 8 pin module is
' VCC, GND, SDA (MOSI), SCL, CS, D/C, RES, BUSY [WeAct schematic]; supply 3.3 V.
'
' There is NO frame buffer: the SSD1680 has 4736 bytes of RAM per colour plane [2.9" BWR panel spec, 10.2: "4736 bytes, 128/8*296"], a PIC has less, and over
' this 4-wire SPI the RAM cannot be read back. So the RAM is written directly, in whole bytes of 8 pixels across:
'   * x and the width of a window are multiples of 8, y and the height are any pixel row;
'   * no single pixel, line or circle (they need a read-modify-write). Draw filled rectangles (EpdFillRect), text on an 8 x 8 pixel cell
'     grid (EpdTextAt / EpdWrite), or stream your own bitmap bytes into a window (EpdWindow, EpdBegin, EpdPut, EpdEnd).
' Nothing shows until EpdUpdate: the panel is refreshed from the RAM, which takes about 2 to 4 s on a black / white panel and longer
' with red, and flashes. The RAM keeps its content afterwards.
'
' Orientation: the module's connector is at the top, x runs along the 122/128 source side (0..W-1, 8 pixels to a byte, bit 7 on the left)
' and y along the gate side (0..249 or 0..295, top to bottom). [WeAct] RAM Y address = 295 - y with the data entry mode X increment, Y
' decrement (11h = 01h [8.3]), also for the 250-line panel, which therefore uses RAM Y 295..46.
'
' Colours: 0 white, 1 black, 2 red (red on a black / white panel is drawn black). Planes [0x24, 0x26 command table]: the black / white
' plane holds 1 = white, 0 = black; the red plane holds 1 = red. [WeAct] on a black / white panel the same bytes are written to both planes.
' A red pixel is written white in the black / white plane; the SSD1680 data sheet does not say which plane wins when both mark a pixel.
'
' Not provided yet (the vendor's fast and partial refresh need a waveform table or temperature trick [WeAct]; not in this data sheet).
' The module is not reentrant.

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

Dim pDc As Byte
Dim pCs As Byte
Dim pRes As Byte
Dim pBusy As Byte
Dim ready As Boolean
Dim tri As Boolean
Dim width As Word
Dim height As Word
Dim tCol As Byte
Dim tRow As Byte
Dim ink As Byte
Dim busyTimeout As Byte

' Opens a command: D/C# low, CS# low, the command byte; D/C# then high so data bytes may follow with CS# still low.
Sub CmdBegin(ByVal c As Byte)
    Pinio.PinSet(pDc, False)
    If pCs <> 255 Then
        Pinio.PinSet(pCs, False)
    End If
    Spi.SpiWrite(c)
    Pinio.PinSet(pDc, True)
End Sub

Sub CmdEnd()
    If pCs <> 255 Then
        Pinio.PinSet(pCs, True)
    End If
End Sub

Sub Cmd0(ByVal c As Byte)
    CmdBegin(c)
    CmdEnd()
End Sub

Sub Cmd1(ByVal c As Byte, ByVal a As Byte)
    CmdBegin(c)
    Spi.SpiWrite(a)
    CmdEnd()
End Sub

Sub Cmd2(ByVal c As Byte, ByVal a As Byte, ByVal b As Byte)
    CmdBegin(c)
    Spi.SpiWrite(a)
    Spi.SpiWrite(b)
    CmdEnd()
End Sub

' BUSY is high while the chip works [pin description, 7 Command Table 12h/20h]: waits up to about 40 s for it to fall. Sets
' busyTimeout = 1 when it does not.
Sub WaitIdle()
    Dim n As Word
    n = 0
    busyTimeout = 0
    While Pinio.PinGet(pBusy)
        DelayMS(10)
        Inc(n)
        If n >= 4000 Then
            busyTimeout = 1
            Exit
        End If
    Wend
End Sub

' Hardware reset (RES# low, then 10 ms [9.1 step 2]), software reset (12h), then the initial code [9.1 step 3]: driver output control
' 01h = 127h (296 lines), TB = 1 [WeAct]; data entry mode 11h = 01h (X increment, Y decrement, X direction [8.3]); RAM window 44h =
' 0..15 bytes, 45h = 295..0; border waveform 3Ch = 05h; display update control 21h = 00h 80h (source S8..S167 [21h]) [WeAct]; internal
' temperature sensor 18h = 80h [18h].
Sub Setup()
    If pRes <> 255 Then
        Pinio.PinSet(pRes, False)
        DelayMS(10)
        Pinio.PinSet(pRes, True)
        DelayMS(10)
    End If
    WaitIdle()
    Cmd0(18)
    DelayMS(10)
    WaitIdle()
    CmdBegin(1)
    Spi.SpiWrite(39)
    Spi.SpiWrite(1)
    Spi.SpiWrite(1)
    CmdEnd()
    Cmd1(17, 1)
    Cmd2(68, 0, 15)
    CmdBegin(69)
    Spi.SpiWrite(39)
    Spi.SpiWrite(1)
    Spi.SpiWrite(0)
    Spi.SpiWrite(0)
    CmdEnd()
    Cmd1(60, 5)
    Cmd2(33, 0, 128)
    Cmd1(24, 128)
End Sub

' Starts the module: 2.13" (`size` 0, 122 x 250) or 2.9" (`size` 1, 128 x 296), `threeColour` True for the black / white / red
' panels. D/C# on `dc`, CS# on `cs` (255 = tied low), RES# on `res` (255 = none), BUSY on `busy`. `SpiInit` must have been called.
' Returns 1, or 0 for a bad size, a pin above 23, a pin the part lacks, or a pin used twice; 2 when the module did not become idle
' (nothing on BUSY, or no module).
Public Function EpdInit(ByVal size As Byte, ByVal threeColour As Boolean, ByVal dc As Byte, ByVal cs As Byte, ByVal res As Byte, ByVal busy As Byte) As Byte
    Result = 0
    ready = False
    If size > 1 Or dc > 23 Or busy > 23 Then
        Exit
    End If
    If (cs <> 255 And cs > 23) Or (res <> 255 And res > 23) Then
        Exit
    End If
    If Not Pinio.PinOk(dc) Or Not Pinio.PinOk(busy) Or dc = busy Then
        Exit
    End If
    If cs <> 255 Then
        If Not Pinio.PinOk(cs) Or cs = dc Or cs = busy Then
            Exit
        End If
    End If
    If res <> 255 Then
        If Not Pinio.PinOk(res) Or res = dc Or res = busy Or res = cs Then
            Exit
        End If
    End If
    pDc = dc
    pCs = cs
    pRes = res
    pBusy = busy
    tri = threeColour
    If size = 0 Then
        width = 122
        height = 250
    Else
        width = 128
        height = 296
    End If
    tCol = 0
    tRow = 0
    ink = 1
    Pinio.PinInput(busy)
    Pinio.PinSet(dc, True)
    Pinio.PinOutput(dc)
    If cs <> 255 Then
        Pinio.PinSet(cs, True)
        Pinio.PinOutput(cs)
    End If
    If res <> 255 Then
        Pinio.PinSet(res, True)
        Pinio.PinOutput(res)
    End If
    ready = True
    Setup()
    Result = 1
    If busyTimeout <> 0 Then
        Result = 2
    End If
End Function

' Width and height in pixels (122 x 250 or 128 x 296).
Public Function EpdWidth() As Word
    Result = width
End Function

Public Function EpdHeight() As Word
    Result = height
End Function

' Sets the RAM window to x..x+w-1 (x and w multiples of 8, w >= 8), y..y+h-1 and the RAM pointer to its first byte; the next bytes of a
' plane fill it row by row (x fastest). 44h = x/8 .. (x+w)/8-1, 45h = 295-y .. 295-(y+h-1), 4Eh / 4Fh = the start [8.4-8.6]. A window
' outside the display (x + w above 8 * bytes per row, y + h above the height) is ignored.
Public Sub EpdWindow(ByVal x As Word, ByVal y As Word, ByVal w As Word, ByVal h As Word)
    Dim xb As Byte
    Dim xe As Byte
    Dim ys As Word
    Dim ye As Word
    If Not ready Then
        Exit
    End If
    If w = 0 Or h = 0 Or (x And 7) <> 0 Or (w And 7) <> 0 Then
        Exit
    End If
    If x + w > 128 Or y + h > height Then
        Exit
    End If
    xb = Byte(x >> 3)
    xe = xb + Byte(w >> 3) - 1
    ys = 295 - y
    ye = 295 - (y + h - 1)
    Cmd2(68, xb, xe)
    CmdBegin(69)
    Spi.SpiWrite(Byte(ys And 255))
    Spi.SpiWrite(Byte(ys >> 8))
    Spi.SpiWrite(Byte(ye And 255))
    Spi.SpiWrite(Byte(ye >> 8))
    CmdEnd()
    Cmd1(78, xb)
    Cmd2(79, Byte(ys And 255), Byte(ys >> 8))
End Sub

' Starts writing bytes into plane 0 (black / white, 24h) or 1 (red, 26h) of the window: follow with EpdPut for each byte and EpdEnd.
Public Sub EpdBegin(ByVal plane As Byte)
    If Not ready Then
        Exit
    End If
    If plane = 0 Then
        CmdBegin(36)
    Else
        CmdBegin(38)
    End If
End Sub

' One data byte (8 pixels, bit 7 on the left) of the open plane.
Public Sub EpdPut(ByVal b As Byte)
    Spi.SpiWrite(b)
End Sub

Public Sub EpdEnd()
    CmdEnd()
End Sub

' The two plane bytes for a colour: 0 white, 1 black, 2 red.
Sub PlaneBytes(ByVal colour As Byte, ByRef bw As Byte, ByRef rd As Byte)
    bw = 255
    rd = 0
    If colour = 1 Then
        bw = 0
    ElseIf colour = 2 And tri Then
        rd = 255
    ElseIf colour = 2 Then
        bw = 0
    End If
    If Not tri Then
        rd = bw
    End If
End Sub

' Fills the window x, y, w, h (as EpdWindow) with a colour.
Public Sub EpdFillRect(ByVal x As Word, ByVal y As Word, ByVal w As Word, ByVal h As Word, ByVal colour As Byte)
    Dim bw As Byte
    Dim rd As Byte
    Dim n As Word
    Dim k As Word
    Dim p As Byte
    If Not ready Or w = 0 Or h = 0 Or (x And 7) <> 0 Or (w And 7) <> 0 Or x + w > 128 Or y + h > height Then
        Exit
    End If
    PlaneBytes(colour, bw, rd)
    n = (w >> 3) * h
    p = 0
    While p < 2
        EpdWindow(x, y, w, h)
        EpdBegin(p)
        k = 0
        While k < n
            If p = 0 Then
                Spi.SpiWrite(bw)
            Else
                Spi.SpiWrite(rd)
            End If
            Inc(k)
        Wend
        EpdEnd()
        Inc(p)
    Wend
End Sub

' Fills the whole RAM with a colour (0 white, 1 black, 2 red): 128 x height, so the 6 spare columns of the 2.13" are filled too.
Public Sub EpdClear(ByVal colour As Byte)
    EpdFillRect(0, 0, 128, height, colour)
End Sub

' Refreshes the panel from the RAM: 22h = F7h (load the temperature, display with display mode 1, power the analog stage down [22h]),
' then 20h, then waits for BUSY to fall [9.1 step 5]. Returns 1, or 0 when BUSY stayed high for about 40 s.
Public Function EpdUpdate() As Byte
    Result = 0
    If Not ready Then
        Exit
    End If
    Cmd1(34, 247)
    Cmd0(32)
    WaitIdle()
    If busyTimeout = 0 Then
        Result = 1
    End If
End Function

' Deep sleep mode 1 (10h = 01h [10h]): 1 uA, the RAM kept but not accessible. Wake with EpdWake.
Public Sub EpdSleep()
    If ready Then
        Cmd1(16, 1)
    End If
End Sub

' Leaves deep sleep: only a hardware reset ends it [10h]; the initial code is sent again. Needs RES# wired.
Public Function EpdWake() As Byte
    Result = 0
    If ready And pRes <> 255 Then
        Setup()
        Result = 1
        If busyTimeout <> 0 Then
            Result = 2
        End If
    End If
End Function

' ---- text on an 8 x 8 cell grid: 5 x 7 glyph with one blank column on the left, 16 (15 on the 2.13") columns, height / 8 rows ----

' Colour of the text (1 black, 2 red); the cell background is white.
Public Sub EpdTextColour(ByVal colour As Byte)
    If colour = 1 Or colour = 2 Then
        ink = colour
    End If
End Sub

' Next character goes to cell `col` (0..15, 14 on the 2.13") of text row `row` (0..height / 8 - 1).
Public Sub EpdTextAt(ByVal col As Byte, ByVal row As Byte)
    tCol = col
    tRow = row
End Sub

' One character (32..126; others draw nothing but advance) at the text position, which then moves one cell right (and to column 0 of
' the next row at the right edge).
Public Sub EpdWriteChar(ByVal ch As Byte)
    Dim g(8) As Byte
    Dim base As Word
    Dim r As Byte
    Dim i As Byte
    Dim b As Byte
    Dim p As Byte
    Dim cols As Byte
    If Not ready Then
        Exit
    End If
    cols = Byte(width >> 3)
    If tCol >= cols Then
        tCol = 0
        Inc(tRow)
    End If
    If (Word(tRow) + 1) * 8 > height Then
        Exit
    End If
    r = 0
    While r < 8
        g(r) = 0
        If ch >= 32 And ch <= 126 And r < 7 Then
            base = Word(ch - 32) * 5
            b = 0
            i = 0
            While i < 5
                b = (b << 1) Or ((Font(base + i) >> r) And 1)
                Inc(i)
            Wend
            g(r) = b << 2
        End If
        Inc(r)
    Wend
    p = 0
    While p < 2
        EpdWindow(Word(tCol) * 8, Word(tRow) * 8, 8, 8)
        EpdBegin(p)
        r = 0
        While r < 8
            b = g(r)
            If p = 0 Then
                If ink = 2 And tri Then
                    b = 255
                Else
                    b = Not b
                End If
            ElseIf tri Then
                If ink <> 2 Then
                    b = 0
                End If
            ElseIf ink = 2 Or ink = 1 Then
                b = Not b
            End If
            Spi.SpiWrite(b)
            Inc(r)
        Wend
        EpdEnd()
        Inc(p)
    Wend
    Inc(tCol)
End Sub

Public Sub EpdWrite(ByRefConst s As String(80))
    Dim i As Byte
    i = 0
    While s(i) <> #0
        EpdWriteChar(Byte(s(i)))
        Inc(i)
    Wend
End Sub
