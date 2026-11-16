' expect: T_SINK=32077
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim sink As Word
Volatile Dim sourceValue As Word
NoInline Function Work(ByVal x As Word) As Word
 Dim a As Word
 Dim b As Word
 Dim total As Word
 a = x Xor 1234
 total = a * 3
 b = x Xor 5678
 total = total + b * 5
 Result = total + 1
End Function
sourceValue = 7
sink = Work(sourceValue)
