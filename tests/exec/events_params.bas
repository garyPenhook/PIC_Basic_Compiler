' expect: T_R1=15 T_R2=34 T_R3=7
' Events with parameters: two handlers of one type, a handler of another type, an array of events
' called with an argument.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Type TByte = Event(ByVal v As Byte)
Type TPair = Event(ByVal a As Byte, ByVal b As Word)
Dim Cb As TByte
Dim Tbl(2) As TByte
Dim P As TPair
Volatile Dim r1 As Word
Volatile Dim r2 As Word
Volatile Dim r3 As Word
Event Add(ByVal v As Byte)
    r1 = r1 + v
End Event
Event Twice(ByVal v As Byte)
    Dim k As Byte
    k = v + v
    r2 = r2 + k
End Event
Event SumPair(ByVal a As Byte, ByVal b As Word)
    r3 = a + b
End Event
Cb = Add
Cb(5)
Cb(10)
Tbl(0) = Twice
Tbl(1) = Add
Tbl(0)(12)
P = SumPair
P(3, 4)
Tbl(0)(5)
Tbl(1)(0)
