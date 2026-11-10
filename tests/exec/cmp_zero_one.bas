' expect: CZ_CZ_C0=0 CZ_CZ_C1=0 CZ_CZ_C2=0 CZ_CZ_C3=0 CZ_CZ_C4=0 CZ_CZ_C5=0 CZ_CZ_C6=0 CZ_CZ_C7=0 CZ_CZ_C8=0 CZ_CZ_C9=0 CZ_CZ_C10=0 CZ_CZ_C11=0 CZ_CZ_C12=0 CZ_CZ_C13=0 CZ_CZ_C14=0 CZ_CZ_R1=0 CZ_CZ_R2=0 CZ_CZ_R3=0 CZ_CZ_R4=0
' Unsigned compares against 0 and 1 (`x > 0`, `x >= 1`, `0 < x`, `x <= 0`, ... are zero tests), byte and word equality
' with 1 and 255 (`decf`/`incf` into W), and a ByRef byte stepped and tested in place (the pointer is not reloaded).
' Each counter is the number of values the condition got wrong, so every expectation is 0.
Program Cz
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim tv(8) As Word
Dim i As Byte
Dim w As Word
Dim b As Byte
Dim l As LongWord
Dim want As Boolean
Dim cz_c0 As Byte
Dim cz_c1 As Byte
Dim cz_c2 As Byte
Dim cz_c3 As Byte
Dim cz_c4 As Byte
Dim cz_c5 As Byte
Dim cz_c6 As Byte
Dim cz_c7 As Byte
Dim cz_c8 As Byte
Dim cz_c9 As Byte
Dim cz_c10 As Byte
Dim cz_c11 As Byte
Dim cz_c12 As Byte
Dim cz_c13 As Byte
Dim cz_c14 As Byte
Dim st As Byte
Dim cz_r1 As Byte
Dim cz_r2 As Byte
Dim cz_r3 As Byte
Dim cz_r4 As Byte

' One step of a countdown kept by the caller: True when it reaches 0, and then it starts again from `reload`.
Function Tick(ByRef s As Byte, ByVal reload As Byte) As Boolean
    Result = False
    If s = 255 Then
        Exit
    End If
    s = s - 1
    If s = 0 Then
        Result = True
        s = reload
    End If
    s = s + 1
    s = s - 1
End Function

' Counts in `c` a condition that disagrees with `want`.
Sub Check(ByRef c As Byte, ByVal got As Boolean)
    If got <> want Then
        c = c + 1
    End If
End Sub

tv(0) = 0
tv(1) = 1
tv(2) = 2
tv(3) = 255
tv(4) = 256
tv(5) = $01FF
tv(6) = $FF01
tv(7) = $FFFF
For i = 0 To 7
    w = tv(i)
    b = w.Byte0
    l = LongWord(w) << 8
    want = w <> 0
    If w > 0 Then
        Check(cz_c0, True)
    Else
        Check(cz_c0, False)
    End If
    If 0 < w Then
        Check(cz_c1, True)
    Else
        Check(cz_c1, False)
    End If
    If w >= 1 Then
        Check(cz_c2, True)
    Else
        Check(cz_c2, False)
    End If
    If 1 <= w Then
        Check(cz_c3, True)
    Else
        Check(cz_c3, False)
    End If
    want = w = 0
    If w <= 0 Then
        Check(cz_c4, True)
    Else
        Check(cz_c4, False)
    End If
    If w < 1 Then
        Check(cz_c5, True)
    Else
        Check(cz_c5, False)
    End If
    If 1 > w Then
        Check(cz_c6, True)
    Else
        Check(cz_c6, False)
    End If
    want = b <> 0
    If b > 0 Then
        Check(cz_c7, True)
    Else
        Check(cz_c7, False)
    End If
    want = b = 0
    If 0 >= b Then
        Check(cz_c8, True)
    Else
        Check(cz_c8, False)
    End If
    want = l <> 0
    If l > 0 Then
        Check(cz_c9, True)
    Else
        Check(cz_c9, False)
    End If
    want = (b - 1) = 0
    If b = 1 Then
        Check(cz_c10, True)
    Else
        Check(cz_c10, False)
    End If
    want = (b + 1) = 0
    If b = 255 Then
        Check(cz_c11, True)
    Else
        Check(cz_c11, False)
    End If
    want = (w + 1) = 0
    If w = $FFFF Then
        Check(cz_c12, True)
    Else
        Check(cz_c12, False)
    End If
    want = (w Xor $01FF) = 0
    If w <> $01FF Then
        Check(cz_c13, False)
    Else
        Check(cz_c13, True)
    End If
    want = (w Xor $FF01) = 0
    If $FF01 = w Then
        Check(cz_c14, True)
    Else
        Check(cz_c14, False)
    End If
Next
' Tick: 3, 2, 1 -> True and back to 3; 255 stays.
st = 3
If Tick(st, 3) Then
    cz_r1 = cz_r1 + 1
End If
If Tick(st, 3) Then
    cz_r1 = cz_r1 + 1
End If
If Not Tick(st, 3) Then
    cz_r2 = cz_r2 + 1
End If
cz_r3 = st Xor 3
st = 255
If Tick(st, 3) Then
    cz_r4 = cz_r4 + 1
End If
cz_r4 = cz_r4 + (st Xor 255)
