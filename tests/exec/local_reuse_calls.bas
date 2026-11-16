' expect: REUSE_ANSWER=8104
Program Reuse
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim stimulus As Word
Volatile Dim answer As Word
NoInline Function Mix(ByVal x As Word) As Word
    Dim scratch As Word
    scratch = x Xor $A55A
    Result = scratch + 17
End Function
NoInline Function Work(ByVal x As Word) As Word
    Dim a, b, total As Word
    a = x Xor 1234
    total = a * 3
    total = total + Mix(a)
    b = x Xor 5678
    total = total + b * 5
    Result = total
End Function
stimulus = 123
answer = Work(stimulus)
