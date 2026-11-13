Module Format
' Number formatting with a field width, a fill character and a radix. Every routine writes its text
' into the one shared String `FmtBuf`, which is then passed to any routine that takes a String:
'     FmtDec(w, 5, "0")  SerialWrite(FmtBuf)         ' 00042
' One shared routine replaces a `Str` expansion at every call site, and the output modules need
' nothing new. The next call overwrites `FmtBuf`. A width only ever pads: a longer number is never cut.
' The digits are made at the width of the argument (the Byte, Word and LongWord forms are overloads of one
' name), so a Byte pays for no 16- or 32-bit divide.

' 32 binary digits and the Null.
Public Dim FmtBuf As String(32)

' The digits of a number are in FmtBuf(p) up to FmtBuf(31). Pad them on the left with `fill` until the text is
' `width` long (at most 32) and return the new start.
Private Function Pad(ByVal p As Byte, ByVal width As Byte, ByVal fill As Char) As Byte
    If width > 32 Then
        width = 32
    End If
    width = 32 - width
    While p > width
        Dec(p)
        FmtBuf(p) = fill
    Wend
    Result = p
End Function

' Move the text that starts at FmtBuf(p) to the front and end it.
Private Sub Close(ByVal p As Byte)
    Dim k As Byte
    k = 0
    While p < 32
        FmtBuf(k) = FmtBuf(p)
        Inc(k)
        Inc(p)
    Wend
    FmtBuf(k) = Char(0)
End Sub

' ---- Decimal ----------------------------------------------------------------------------------

' The decimal digits of n in FmtBuf, ending at FmtBuf(31); returns where they start. The three widths are
' overloads, so a Byte pays for no 16-bit divide.
Private Function Digits(ByVal n As Byte) As Byte
    Dim p As Byte
    Dim q As Byte
    p = 32
    Repeat
        Dec(p)
        q = n / 10
        FmtBuf(p) = Char(48 + n - q * 10)
        n = q
    Until n = 0
    Result = p
End Function

Private Function Digits(ByVal n As Word) As Byte
    Dim p As Byte
    p = 32
    Repeat
        Dec(p)
        FmtBuf(p) = Char(48 + Byte(n Mod 10))
        n = n / 10
    Until n = 0
    Result = p
End Function

Private Function Digits(ByVal n As LongWord) As Byte
    Dim p As Byte
    p = 32
    Repeat
        Dec(p)
        FmtBuf(p) = Char(48 + Byte(n Mod 10))
        n = n / 10
    Until n = 0
    Result = p
End Function

' Unsigned: FmtDec(42, 5, "0") gives 00042, FmtDec(42, 5, " ") gives "   42", width 0 gives 42.
Public Sub FmtDec(ByVal n As Byte, ByVal width As Byte, ByVal fill As Char)
    Close(Pad(Digits(n), width, fill))
End Sub

Public Sub FmtDec(ByVal n As Word, ByVal width As Byte, ByVal fill As Char)
    Close(Pad(Digits(n), width, fill))
End Sub

Public Sub FmtDec(ByVal n As LongWord, ByVal width As Byte, ByVal fill As Char)
    Close(Pad(Digits(n), width, fill))
End Sub

' With a sign. The minus sign counts in the width and comes before the zeros of a "0" fill
' (FmtSDec(-42, 6, "0") gives -00042) and right before the digits of any other fill (FmtSDec(-42, 6, " ") gives "   -42").
Private Function PadSign(ByVal p As Byte, ByVal width As Byte, ByVal fill As Char, ByVal neg As Boolean) As Byte
    If Not neg Then
        p = Pad(p, width, fill)
    ElseIf fill = "0" Then
        If width > 0 Then
            Dec(width)
        End If
        p = Pad(p, width, fill)
        Dec(p)
        FmtBuf(p) = "-"
    Else
        Dec(p)
        FmtBuf(p) = "-"
        p = Pad(p, width, fill)
    End If
    Result = p
End Function

Public Sub FmtSDec(ByVal n As ShortInt, ByVal width As Byte, ByVal fill As Char)
    Dim m As Byte
    m = Byte(n)
    If n < 0 Then
        m = 0 - m
    End If
    Close(PadSign(Digits(m), width, fill, n < 0))
End Sub

Public Sub FmtSDec(ByVal n As Integer, ByVal width As Byte, ByVal fill As Char)
    Dim m As Word
    m = Word(n)
    If n < 0 Then
        m = 0 - m
    End If
    Close(PadSign(Digits(m), width, fill, n < 0))
End Sub

Public Sub FmtSDec(ByVal n As LongInt, ByVal width As Byte, ByVal fill As Char)
    Dim m As LongWord
    m = LongWord(n)
    If n < 0 Then
        m = 0 - m
    End If
    Close(PadSign(Digits(m), width, fill, n < 0))
End Sub

' ---- Hexadecimal and binary ---------------------------------------------------------------------

' The low `digits` hexadecimal digits of n (capitals), at most 8: FmtHex($2A, 2) gives 2A, FmtHex($2A, 4) gives 002A.
Private Function HexChar(ByVal v As Byte) As Char
    v = v + 48
    If v > 57 Then
        v = v + 7
    End If
    Result = Char(v)
End Function

Public Sub FmtHex(ByVal n As Byte, ByVal digits As Byte)
    If digits > 8 Then
        digits = 8
    End If
    FmtBuf(digits) = Char(0)
    While digits > 0
        Dec(digits)
        FmtBuf(digits) = HexChar(n And 15)
        n = n >> 4
    Wend
End Sub

Public Sub FmtHex(ByVal n As Word, ByVal digits As Byte)
    If digits > 8 Then
        digits = 8
    End If
    FmtBuf(digits) = Char(0)
    While digits > 0
        Dec(digits)
        FmtBuf(digits) = HexChar(Byte(n) And 15)
        n = n >> 4
    Wend
End Sub

Public Sub FmtHex(ByVal n As LongWord, ByVal digits As Byte)
    If digits > 8 Then
        digits = 8
    End If
    FmtBuf(digits) = Char(0)
    While digits > 0
        Dec(digits)
        FmtBuf(digits) = HexChar(Byte(n) And 15)
        n = n >> 4
    Wend
End Sub

' The low `digits` binary digits of n, at most 32: FmtBin(5, 8) gives 00000101.
Public Sub FmtBin(ByVal n As Byte, ByVal digits As Byte)
    If digits > 32 Then
        digits = 32
    End If
    FmtBuf(digits) = Char(0)
    While digits > 0
        Dec(digits)
        FmtBuf(digits) = Char(48 + (n And 1))
        n = n >> 1
    Wend
End Sub

Public Sub FmtBin(ByVal n As Word, ByVal digits As Byte)
    If digits > 32 Then
        digits = 32
    End If
    FmtBuf(digits) = Char(0)
    While digits > 0
        Dec(digits)
        FmtBuf(digits) = Char(48 + Byte(n And 1))
        n = n >> 1
    Wend
End Sub

Public Sub FmtBin(ByVal n As LongWord, ByVal digits As Byte)
    If digits > 32 Then
        digits = 32
    End If
    FmtBuf(digits) = Char(0)
    While digits > 0
        Dec(digits)
        FmtBuf(digits) = Char(48 + Byte(n And 1))
        n = n >> 1
    Wend
End Sub
