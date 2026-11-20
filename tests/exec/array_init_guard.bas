' expect: T_FULL=6 T_ESC=5
' A named SFR write and a pointer parameter elsewhere in the program must not stop the entry clear of a fully
' written local array from going; an array whose element address escapes keeps its clear.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim full As Word
Volatile Dim esc As Word
Volatile Dim sink As Byte
Sub Put(ByRef v As Byte)
    v = 5
End Sub
NoInline Function Filled() As Word
    Dim buf(4) As Byte
    Dim i As Byte
    For i = 0 To 3
        buf(i) = i
    Next
    Result = Word(buf(0)) + buf(1) + buf(2) + buf(3)
End Function
NoInline Function Escaped() As Word
    Dim buf(4) As Byte
    Put(buf(1))
    Result = Word(buf(0)) + buf(1) + buf(2) + buf(3)
End Function
LATC = 1
Put(sink)
full = Filled()
esc = Escaped()
