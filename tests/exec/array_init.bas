' expect: T_FULL=232 T_PARTIAL=0 T_BRANCH=46
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim sourceValue As Word
Volatile Dim full As Word
Volatile Dim partial As Word
Volatile Dim branch As Word
NoInline Function Filled(ByVal x As Word) As Word
    Dim buf(16) As Word
    Dim i As Byte
    Dim total As Word
    For i = 0 To 15
        buf(i) = x + i
    Next
    For i = 0 To 15
        total = total + buf(i)
    Next
    Result = total
End Function
NoInline Function PartialBuf(ByVal x As Word) As Word
    Dim buf(16) As Word
    Dim i As Byte
    For i = 0 To 14
        buf(i) = x + i
    Next
    Result = buf(15)
End Function
NoInline Function BranchBuf(ByVal x As Word) As Word
    Dim buf(4) As Byte
    If x = 0 Then
        buf(0) = 1
        buf(1) = 2
        buf(2) = 3
        buf(3) = 4
    Else
        buf(0) = 10
        buf(1) = 11
        buf(2) = 12
        buf(3) = 13
    End If
    Result = Word(buf(0)) + buf(1) + buf(2) + buf(3)
End Function
sourceValue = 7
full = Filled(sourceValue)
partial = PartialBuf(sourceValue)
branch = BranchBuf(sourceValue)
