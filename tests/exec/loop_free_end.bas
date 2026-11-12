' For loops whose variable nothing reads after the loop step before they test (`St::For::free`); a variable that is
' read afterwards keeps the last value it took. Byte and Word, up and down, constant and variable limits, the ends of
' the range, a Break, and a global that another routine names.
' expect: T_R0=256 T_R1=32385 T_R2=255 T_R3=36 T_R4=9 T_R5=21 T_R6=300 T_R7=299 T_R8=4 T_R9=10 T_R10=6 T_R11=55 T_R12=3 T_R13=45150 T_R14=5
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim A(16) As Byte
Dim Lim As Byte
Dim g, h As Byte
Dim R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14 As Word

' Whole Byte range up: 256 passes, the sum of 0..255 is 32640, less 255 read back = 32385.
Sub FullUp()
    Dim i As Byte
    Dim c, s As Word
    For i = 0 To 255
        c = c + 1
        s = s + i
    Next
    R0 = c
    R1 = s - 255
End Sub

' Down to zero: 255 passes from 255 to 1 leave out 0, so count 255; then 8..1 sums to 36.
Sub Down()
    Dim i As Byte
    Dim c As Word
    For i = 255 To 1 Step -1
        c = c + 1
    Next
    R2 = c
    c = 0
    For i = 8 To 1 Step -1
        c = c + i
    Next
    R3 = c
End Sub

' The variable is read after the loop: it keeps the last value (9), and a variable limit sums 1..6 = 21.
Sub Kept(ByVal n As Byte)
    Dim i, j As Byte
    Dim s As Word
    For i = 0 To 9
        A(i) = i
    Next
    R4 = i
    For j = 1 To n
        s = s + j
    Next
    R5 = s
End Sub

' Word loops: 300 passes, and the last value read back.
Sub Words()
    Dim w, x As Word
    Dim c As Word
    For w = 1000 To 1299
        c = c + 1
    Next
    R6 = c
    For x = 0 To 299
        c = c + 1
    Next
    R7 = x
End Sub

' A Break leaves the variable where it was; it is read afterwards, so the loop is not a free one.
Sub Broken()
    Dim i As Byte
    For i = 0 To 20
        If A(i) = 4 Then
            Break
        End If
    Next
    R8 = i
End Sub

' g is named by two routines: Bump sees the value the loop left (the last one it took, 9), plus one.
Sub Bump()
    R9 = g + 1
End Sub

' Nested loops, the inner limit depending on the outer variable: 1 + 2 + 3 passes.
Sub Nested()
    Dim i, j As Byte
    Dim c As Word
    For i = 0 To 2
        For j = 0 To i
            c = c + 1
        Next
    Next
    R10 = c
End Sub

' A variable limit at the top of the range and a loop that runs once.
Sub Edges()
    Dim i, k As Byte
    Dim s, c As Word
    Lim = 10
    For i = 1 To Lim
        s = s + i
    Next
    R11 = s
    Lim = 255
    For k = 253 To Lim
        c = c + 1
    Next
    R12 = c
    s = 0
    For i = 0 To Lim
        s = s + i
    Next
    For i = 44 To 100
        s = s + i + i
    Next
    For i = 7 To 7
        R14 = R14 + 5
    Next
    R13 = s + 4302
End Sub

FullUp()
Down()
Kept(6)
Words()
Broken()
For g = 0 To 9
    h = h + 1
Next
Bump()
Nested()
Edges()
