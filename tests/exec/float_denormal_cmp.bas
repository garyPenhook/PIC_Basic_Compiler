' expect: FD_BAD=0 FD_FIRST=0
' A denormal compares as a zero: every ordering of two values gives the answer for the same values with the denormals
' replaced by +0, both through Cmp and, against a zero constant, through FSign. FD_FIRST is 0, or the check * 256 + pair + 1.
Program Fd
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "floatlib"
Const DV(16) As LongWord = (0, 2147483648, 1, 8388607, 2147483649, 2155872255, 4194304, 8388608, 2155872256, 1065353216, 3212836864, 2139095039, 2139095040, 4286578688, 2143289344, 3)
Dim bad As Word
Dim first As Word
Dim i As Byte
Dim j As Byte
Dim p As Byte
Dim x As Float
Dim xw As x.AsLongWord
Dim y As Float
Dim yw As y.AsLongWord
Dim fx As Float
Dim fxw As fx.AsLongWord
Dim fy As Float
Dim fyw As fy.AsLongWord
Dim z As Float
Dim d As Float
Dim dw As d.AsLongWord
Dim m As Float
Dim mw As m.AsLongWord
Dim q As Float
Dim qw As q.AsLongWord
Sub Miss(ByVal op As Byte)
    Inc(bad)
    If first = 0 Then
        first = Word(op) * 256 + p + 1
    End If
End Sub
z = 0
For i = 0 To 15
    For j = 0 To 15
        p = i * 16 + j
        xw = DV(i)
        yw = DV(j)
        fxw = xw
        If (xw And $7F800000) = 0 Then
            fxw = 0
        End If
        fyw = yw
        If (yw And $7F800000) = 0 Then
            fyw = 0
        End If
        If (x = y) <> (fx = fy) Then
            Miss(1)
        End If
        If (x < y) <> (fx < fy) Then
            Miss(2)
        End If
        If (x > y) <> (fx > fy) Then
            Miss(3)
        End If
        If (x <= y) <> (fx <= fy) Then
            Miss(4)
        End If
        If (x >= y) <> (fx >= fy) Then
            Miss(5)
        End If
        If (x <> y) <> (fx <> fy) Then
            Miss(6)
        End If
        If (x = 0.0) <> (fx = z) Then
            Miss(7)
        End If
        If (x < 0.0) <> (fx < z) Then
            Miss(8)
        End If
        If (0.0 > x) <> (z > fx) Then
            Miss(9)
        End If
        If (x >= 0.0) <> (fx >= z) Then
            Miss(10)
        End If
    Next
Next
' Fixed answers that do not go through the replaced-by-zero copies: d is a positive denormal, m the smallest normal, q a NaN.
dw = 4194305
mw = 8388608
qw = 2143289344
p = 0
If Not (d = z) Then
    Miss(11)
End If
If Not (d < m) Then
    Miss(12)
End If
If d > m Then
    Miss(13)
End If
If Not (m > d) Then
    Miss(14)
End If
dw = 2151677953
If Not (d = z) Then
    Miss(15)
End If
If Not (d > -m) Then
    Miss(16)
End If
If Not (-m < d) Then
    Miss(17)
End If
If d < 0.0 Then
    Miss(18)
End If
If d > 0.0 Then
    Miss(19)
End If
If d = q Then
    Miss(20)
End If
If d < q Then
    Miss(21)
End If
If d > q Then
    Miss(22)
End If
If d >= q Then
    Miss(23)
End If
If Not (d <> q) Then
    Miss(24)
End If
