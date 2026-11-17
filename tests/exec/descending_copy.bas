' expect: DC_SINK=0
Program DC
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a(140) As Word
Dim b(8) As Word
Dim small(8) As Byte
Dim wide(8) As LongInt
Dim i As Byte
Volatile Dim sink As Word
sink = 0
For i = 0 To 139
    a(i) = Word(i) * 257
Next
' Overlap in the safe shift direction, crossing linear RAM banks and 127/128.
For i = 139 To 1 Step -1
    a(i) = a(i - 1)
Next
For i = 1 To 139
    If a(i) <> Word(i - 1) * 257 Then
        sink = sink + 1
    End If
Next
' Copy to a separate array in descending order.
For i = 7 To 0 Step -1
    b(i) = a(i)
Next
For i = 0 To 7
    If b(i) <> a(i) Then
        sink = sink + 1
    End If
Next
' Overlap in the propagating direction must preserve sequential semantics.
For i = 138 To 0 Step -1
    a(i) = a(i + 1)
Next
For i = 0 To 139
    If a(i) <> 35466 Then
        sink = sink + 1
    End If
Next

' Byte and signed four-byte copies use the same stationary-pointer path.
For i = 0 To 7
    small(i) = i
    wide(i) = LongInt(i) * -100000
Next
For i = 7 To 1 Step -1
    small(i) = small(i - 1)
Next
For i = 7 To 1 Step -1
    wide(i) = wide(i - 1)
Next
For i = 1 To 7
    If small(i) <> i - 1 Then
        sink = sink + 1
    End If
    If wide(i) <> LongInt(i - 1) * -100000 Then
        sink = sink + 1
    End If
Next
