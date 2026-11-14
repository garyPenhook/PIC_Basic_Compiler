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
' numbered as in `Pinio` (0..23, up to 47 with ports D to F; CS# may be 255 when the module ties it low; RES# may be 255; BUSY is needed). The 8 pin module is
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
Dim tCols As Byte
Dim tRows As Byte
Dim ink As Byte
Dim busyTimeout As Byte

' CS# to `level`, unless the module ties it low (pin 255).
Sub CsSet(ByVal level As Boolean)
    If pCs <> 255 Then
        Pinio.PinSet(pCs, level)
    End If
End Sub

' Opens a command: D/C# low, CS# low, the command byte; D/C# then high so data bytes may follow with CS# still low.
Sub CmdBegin(ByVal c As Byte)
    Pinio.PinSet(pDc, False)
    CsSet(False)
    Spi.SpiWrite(c)
    Pinio.PinSet(pDc, True)
End Sub

Sub CmdEnd()
    CsSet(True)
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

' 10 ms (one copy of the delay loop for the five places that wait).
Sub Pause()
    DelayMS(10)
End Sub

' BUSY is high while the chip works [pin description, 7 Command Table 12h/20h]: waits up to about 40 s for it to fall. Sets
' busyTimeout = 1 when it does not.
Sub WaitIdle()
    Dim n As Word
    n = 4000
    busyTimeout = 0
    While Pinio.PinGet(pBusy)
        Pause()
        Dec(n)
        If n = 0 Then
            busyTimeout = 1
            Exit
        End If
    Wend
End Sub

' Hardware reset (RES# low, then 10 ms [9.1 step 2]), software reset (12h), then the initial code [9.1 step 3]: driver output control
' 01h = 127h (296 lines), TB = 1 [WeAct]; data entry mode 11h = 01h (X increment, Y decrement, X direction [8.3]); RAM window 44h =
' 0..15 bytes, 45h = 295..0; border waveform 3Ch = 05h; display update control 21h = 00h 80h (source S8..S167 [21h]) [WeAct]; internal
' temperature sensor 18h = 80h [18h].
Const InitTab(29) As Byte = (3, 1, 39, 1, 1, 1, 17, 1, 2, 68, 0, 15, 4, 69, 39, 1, 0, 0, 1, 60, 5, 2, 33, 0, 128, 1, 24, 128, 0)
Sub Setup()
    Dim i As Byte
    Dim n As Byte
    If pRes <> 255 Then
        Pinio.PinSet(pRes, False)
        Pause()
        Pinio.PinSet(pRes, True)
        Pause()
    End If
    WaitIdle()
    Cmd0(18)
    Pause()
    WaitIdle()
    ' InitTab: for each command the number of data bytes (1..4), the command, the data bytes; a 0 ends it
    i = 0
    While InitTab(i) <> 0
        n = InitTab(i)
        CmdBegin(InitTab(i + 1))
        i = i + 2
        While n > 0
            Spi.SpiWrite(InitTab(i))
            Inc(i)
            Dec(n)
        Wend
        CmdEnd()
    Wend
End Sub

' Output, high (not for pin 255).
Sub Drive(ByVal pin As Byte)
    If pin <> 255 Then
        Pinio.PinSet(pin, True)
        Pinio.PinOutput(pin)
    End If
End Sub

' Starts the module: 2.13" (`size` 0, 122 x 250) or 2.9" (`size` 1, 128 x 296), `threeColour` True for the black / white / red
' panels. D/C# on `dc`, CS# on `cs` (255 = tied low), RES# on `res` (255 = none), BUSY on `busy`. `SpiInit` must have been called.
' Returns 1, or 0 for a bad size, a pin the part lacks, or a pin used twice; 2 when the module did not become idle
' (nothing on BUSY, or no module).
Public Function EpdInit(ByVal size As Byte, ByVal threeColour As Boolean, ByVal dc As Byte, ByVal cs As Byte, ByVal res As Byte, ByVal busy As Byte) As Byte
    Result = 0
    ready = False
    If size > 1 Then
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
        tCols = 15
        tRows = 31
    Else
        width = 128
        height = 296
        tCols = 16
        tRows = 37
    End If
    tCol = 0
    tRow = 0
    ink = 1
    Pinio.PinInput(busy)
    Drive(dc)
    Drive(cs)
    Drive(res)
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

' Window for EpdWindow: False (nothing sent) when the module is not started or the window is empty, not on byte columns or
' outside the display.
Function SetWindow(ByVal x As Word, ByVal y As Word, ByVal w As Word, ByVal h As Word) As Boolean
    Dim xb As Byte
    Dim xe As Word
    Dim ys As Word
    Dim ye As Word
    Result = False
    xe = x + w
    ye = y + h
    If Not ready Or w = 0 Or h = 0 Or ((Byte(x) Or Byte(w)) And 7) <> 0 Or xe > 128 Or ye > height Then
        Exit
    End If
    Result = True
    xb = Byte(x) >> 3
    Cmd2(68, xb, (Byte(xe) >> 3) - 1)
    ys = 295 - y
    ye = 296 - ye
    CmdBegin(69)
    Spi.SpiWrite(Byte(ys))
    Spi.SpiWrite(Byte(ys >> 8))
    Spi.SpiWrite(Byte(ye))
    Spi.SpiWrite(Byte(ye >> 8))
    CmdEnd()
    Cmd1(78, xb)
    Cmd2(79, Byte(ys), Byte(ys >> 8))
End Function

' Sets the RAM window to x..x+w-1 (x and w multiples of 8, w >= 8), y..y+h-1 and the RAM pointer to its first byte; the next bytes of a
' plane fill it row by row (x fastest). 44h = x/8 .. (x+w)/8-1, 45h = 295-y .. 295-(y+h-1), 4Eh / 4Fh = the start [8.4-8.6]. A window
' outside the display (x + w above 8 * bytes per row, y + h above the height) is ignored.
Public Sub EpdWindow(ByVal x As Word, ByVal y As Word, ByVal w As Word, ByVal h As Word)
    Dim ok As Boolean
    ok = SetWindow(x, y, w, h)
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

' The byte that fills plane `p` for a colour: 0 white, 1 black, 2 red. The black / white plane holds 1 = white; the red plane holds
' 1 = red, and on a black / white panel it gets the same bytes as the black / white plane.
Function PlaneByte(ByVal colour As Byte, ByVal p As Byte) As Byte
    If p = 1 And tri Then
        Result = 0
        If colour = 2 Then
            Result = 255
        End If
    Else
        Result = 255
        If colour = 1 Or (colour = 2 And Not tri) Then
            Result = 0
        End If
    End If
End Function

' Fills the window x, y, w, h (as EpdWindow) with a colour.
Public Sub EpdFillRect(ByVal x As Word, ByVal y As Word, ByVal w As Word, ByVal h As Word, ByVal colour As Byte)
    Dim n As Word
    Dim k As Word
    Dim p As Byte
    Dim v As Byte
    n = Word(Byte(w) >> 3) * h
    p = 0
    While p < 2
        If Not SetWindow(x, y, w, h) Then
            Exit
        End If
        EpdBegin(p)
        v = PlaneByte(colour, p)
        k = n
        While k > 0
            Spi.SpiWrite(v)
            Dec(k)
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
    Dim fb As Byte
    Dim p As Byte
    Dim am As Byte
    Dim xm As Byte
    If Not ready Then
        Exit
    End If
    If tCol >= tCols Then
        tCol = 0
        Inc(tRow)
    End If
    If tRow >= tRows Then
        Exit
    End If
    ' g is zero (a local array is cleared at every entry), so a character outside 32..126 is a blank cell
    ' the font is stored a column (5 bytes, bit r = row r) at a time: the rows get its bits, the first column most significant
    If ch >= 32 And ch <= 126 Then
        base = Word(ch - 32) * 5
        i = 0
        While i < 5
            fb = Font(base + i)
            r = 0
            While r < 7
                g(r) = (g(r) << 1) Or (fb And 1)
                fb = fb >> 1
                Inc(r)
            Wend
            Inc(i)
        Wend
    End If
    p = 0
    While p < 2
        ' the byte written is (row << 2 And am) Xor xm: the black / white plane holds the inverse of the glyph, or all ones for red
        ' ink on a red panel; the red plane holds the glyph for red ink on a red panel and zeros for black ink; a black / white panel
        ' gets the inverse in both planes
        am = 255
        xm = 255
        If p = 0 Then
            If ink = 2 And tri Then
                am = 0
            End If
        ElseIf tri Then
            xm = 0
            If ink <> 2 Then
                am = 0
            End If
        End If
        If Not SetWindow(Word(tCol) * 8, Word(tRow) * 8, 8, 8) Then
            Exit
        End If
        EpdBegin(p)
        r = 0
        While r < 8
            Spi.SpiWrite(((g(r) << 2) And am) Xor xm)
            Inc(r)
        Wend
        EpdEnd()
        Inc(p)
    Wend
    Inc(tCol)
End Sub

' Writes a string at the text position with EpdWriteChar.
Public Sub EpdWrite(ByRefConst s As String(80))
    Dim i As Byte
    i = 0
    While s(i) <> #0
        EpdWriteChar(Byte(s(i)))
        Inc(i)
    Wend
End Sub
