' warn:
Program Main
Device = 18F27Q10
Include "Util"
Include "Timer"
Dim r As Word
Util.Counter = 0
r = Util.Twice(4) + Timer.Ticks
Util.Bump()
Bump2()
