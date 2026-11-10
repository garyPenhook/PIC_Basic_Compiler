' Multi-byte stores from a plain variable (byte by byte through WREG, not through __A): Word from Word, Word and LongWord
' from a Byte (zero-extended), LongWord from a Word, Integer from Integer, Integer from a ShortInt (sign-extended), a
' value passed to a Word parameter, and a Word array element stored to a Word. SC_BAD counts wrong results.
' expect: SC_BAD=0 SC_DONE=1
Program Sc
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a As Word
Dim a2 As Word
Dim b As Byte
Dim l As LongWord
Dim i As Integer
Dim j As Integer
Dim sb As ShortInt
Dim tv(3) As Word
Dim r As Word
Dim bad As Byte
Dim done As Byte
Sub Take(ByVal x As Word)
    r = x
End Sub
tv(0) = 4660
tv(1) = 65535
tv(2) = 256
a = tv(0)
b = PORTA
b = 154 + (b And 0)
a2 = a
If a2 <> 4660 Then
    bad = bad + 1
End If
a2 = b
If a2 <> 154 Then
    bad = bad + 1
End If
l = a
If l <> 4660 Then
    bad = bad + 1
End If
l = b
If l <> 154 Then
    bad = bad + 1
End If
a = tv(1)
l = a
If l <> 65535 Then
    bad = bad + 1
End If
i = -5
j = i
If j <> -5 Then
    bad = bad + 1
End If
sb = -3
i = sb
If i <> -3 Then
    bad = bad + 1
End If
a = tv(2)
Take(a)
If r <> 256 Then
    bad = bad + 1
End If
Take(b)
If r <> 154 Then
    bad = bad + 1
End If
a = a
If a <> 256 Then
    bad = bad + 1
End If
a2 = tv(1)
If a2 <> 65535 Then
    bad = bad + 1
End If
done = 1
