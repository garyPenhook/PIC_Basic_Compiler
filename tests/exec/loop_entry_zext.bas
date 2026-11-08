' For loops whose start is the lowest (or, counting down, highest) value of the type skip the entry test; a hidden
' loop limit or Select subject that becomes a constant after argument propagation is folded; a zero-extended value
' is stored byte by byte with the upper bytes cleared.
' expect: T_R0=1 T_R1=256 T_R2=4 T_R3=3 T_R4=2 T_R5=5 T_R6=48 T_R7=48 T_R8=40 T_R9=7 T_R10=200 T_R11=772 T_R12=65535
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim B(4) As Byte = (7, 200, 3, 4)
Dim WA(2) As Word = (772, 65535)
Dim Lim As Byte
Dim SLim As Integer
Dim R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12 As LongWord

Function CountUp(ByVal n As Byte) As Word
    Dim i As Byte
    Dim c As Word
    For i = 0 To n
        c = c + 1
    Next
    Result = c
End Function

Function CountSigned(ByVal n As Integer) As Word
    Dim i As Integer
    Dim c As Word
    For i = -32768 To n
        c = c + 1
    Next
    Result = c
End Function

Function CountDown(ByVal n As Byte) As Word
    Dim i As Byte
    Dim c As Word
    For i = 255 To n Step -1
        c = c + 1
    Next
    Result = c
End Function

' Always called with 48: the hidden limit n - 1 becomes a constant.
Function Span(ByVal n As Byte) As Word
    Dim i As Byte
    Dim c As Word
    For i = 0 To n - 1
        c = c + 1
    Next
    Result = c
End Function

' Always called with 2: the Select subject becomes a constant.
Function Pick(ByVal k As Byte) As Byte
    Select k
        Case 1
            Result = 10
        Case 2
            Result = 40
        Case Else
            Result = 99
    End Select
End Function

NoInline Function Small(ByVal k As Byte) As Byte
    Result = B(k)
End Function

Lim = 0
R0 = CountUp(Lim)
Lim = 255
R1 = CountUp(Lim)
Lim = 3
R2 = CountUp(Lim)
SLim = -32766
R3 = CountSigned(SLim)
Lim = 254
R4 = CountDown(Lim)
Lim = 251
R5 = CountDown(Lim)
R6 = Span(48)
R7 = Span(48)
R8 = Pick(2) + Pick(2) - 40
R9 = Small(0)
R10 = Small(1)
Lim = 0
R11 = WA(Lim)
Lim = 1
R12 = WA(Lim)
