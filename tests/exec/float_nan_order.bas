' expect: FN_BAD=0 FN_FIRST=0
' FAdd and FMul give the same bits whichever way round the operands are (the compiler swaps them to run a conversion call
' first), including NaNs of either sign and payload, infinities and zeros. FN_FIRST is 0, or the check * 256 + pair + 1.
Program Fn
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "floatlib"
Const NV(16) As LongWord = (2143289344, 4290772993, 2139095041, 4286578689, 2139095040, 4286578688, 0, 2147483648, 1, 2147483649, 8388607, 1065353216, 3212836864, 2139095039, 8388608, 1)
Dim bad As Word
Dim first As Word
Dim i As Byte
Dim j As Byte
Dim p As Byte
Dim n As LongWord
Sub Miss(ByVal op As Byte)
    Inc(bad)
    If first = 0 Then
        first = Word(op) * 256 + p + 1
    End If
End Sub
For i = 0 To 15
    For j = 0 To 15
        p = i * 16 + j
        If FloatLib.FAdd(NV(i), NV(j)) <> FloatLib.FAdd(NV(j), NV(i)) Then
            Miss(1)
        End If
        If FloatLib.FMul(NV(i), NV(j)) <> FloatLib.FMul(NV(j), NV(i)) Then
            Miss(2)
        End If
        n = NV(j) Xor $80000000
        If FloatLib.FAdd(NV(i), n) <> FloatLib.FAdd(n, NV(i)) Then
            Miss(3)
        End If
    Next
Next
