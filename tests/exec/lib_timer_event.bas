' expect: LTE_N=3
' Timer0OnExpire: the handler runs once per Timer0 overflow, called from Timer0Service.
Program Lte
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "timer"
Volatile Dim n As Byte
Event Tick()
    Inc(n)
End Event
Timer0OnExpire = Tick
Timer0Start(0, 1)
While n < 3
    Timer0Service()
Wend
