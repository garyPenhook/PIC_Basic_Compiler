' x > 0, x <= 0 and the mirrored forms on signed 16- and 32-bit values, around the byte boundaries.
' Each result is 5 (positive: x > 0 and 0 < x) or 10 (zero or negative: x <= 0 and 0 >= x).
' expect: T_I0=10 T_I1=10 T_I2=10 T_I3=10 T_I4=5 T_I5=5 T_I6=5 T_I7=5
' expect: T_L0=10 T_L1=10 T_L2=10 T_L3=5 T_L4=5 T_L5=5 T_L6=10 T_L7=5 T_BR=24
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim i As Integer
Dim j As LongInt
Dim I0 As Word
Dim I1 As Word
Dim I2 As Word
Dim I3 As Word
Dim I4 As Word
Dim I5 As Word
Dim I6 As Word
Dim I7 As Word
Dim L0 As Word
Dim L1 As Word
Dim L2 As Word
Dim L3 As Word
Dim L4 As Word
Dim L5 As Word
Dim L6 As Word
Dim L7 As Word
Dim BR As Word

Function Mask16(ByVal v As Integer) As Word
    Result = 0
    If v > 0 Then
        Result = Result + 1
    End If
    If v <= 0 Then
        Result = Result + 2
    End If
    If 0 < v Then
        Result = Result + 4
    End If
    If 0 >= v Then
        Result = Result + 8
    End If
End Function

i = -32768
I0 = Mask16(i)
i = -256
I1 = Mask16(i)
i = -1
I2 = Mask16(i)
i = 0
I3 = Mask16(i)
i = 1
I4 = Mask16(i)
i = 255
I5 = Mask16(i)
i = 256
I6 = Mask16(i)
i = 32767
I7 = Mask16(i)

j = -2147483648
L0 = 0
If j > 0 Then
    L0 = L0 + 1
End If
If j <= 0 Then
    L0 = L0 + 2
End If
If 0 < j Then
    L0 = L0 + 4
End If
If 0 >= j Then
    L0 = L0 + 8
End If
j = -65536
L1 = 0
If j > 0 Then
    L1 = L1 + 1
End If
If j <= 0 Then
    L1 = L1 + 2
End If
If 0 < j Then
    L1 = L1 + 4
End If
If 0 >= j Then
    L1 = L1 + 8
End If
j = -1
L2 = 0
If j > 0 Then
    L2 = L2 + 1
End If
If j <= 0 Then
    L2 = L2 + 2
End If
If 0 < j Then
    L2 = L2 + 4
End If
If 0 >= j Then
    L2 = L2 + 8
End If
j = 1
L3 = 0
If j > 0 Then
    L3 = L3 + 1
End If
If j <= 0 Then
    L3 = L3 + 2
End If
If 0 < j Then
    L3 = L3 + 4
End If
If 0 >= j Then
    L3 = L3 + 8
End If
j = 65536
L4 = 0
If j > 0 Then
    L4 = L4 + 1
End If
If j <= 0 Then
    L4 = L4 + 2
End If
If 0 < j Then
    L4 = L4 + 4
End If
If 0 >= j Then
    L4 = L4 + 8
End If
j = 16777216
L5 = 0
If j > 0 Then
    L5 = L5 + 1
End If
If j <= 0 Then
    L5 = L5 + 2
End If
If 0 < j Then
    L5 = L5 + 4
End If
If 0 >= j Then
    L5 = L5 + 8
End If
j = 0
L6 = 0
If j > 0 Then
    L6 = L6 + 1
End If
If j <= 0 Then
    L6 = L6 + 2
End If
If 0 < j Then
    L6 = L6 + 4
End If
If 0 >= j Then
    L6 = L6 + 8
End If
j = 2147483647
L7 = 0
If j > 0 Then
    L7 = L7 + 1
End If
If j <= 0 Then
    L7 = L7 + 2
End If
If 0 < j Then
    L7 = L7 + 4
End If
If 0 >= j Then
    L7 = L7 + 8
End If

' In a loop condition and with an Else branch, where the jump is taken the other way.
BR = 0
i = 3
While i > 0
    BR = BR + 1
    i = i - 1
Wend
i = -2
While i <= 0
    BR = BR + 10
    i = i + 1
    If i > 0 Then
        BR = BR - 9
    Else
        BR = BR + 0
    End If
Wend
End
