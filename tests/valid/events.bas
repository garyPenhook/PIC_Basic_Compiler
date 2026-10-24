Program T
Device = 18F27Q10
Type TCallback = Event()
Dim OnTick As TCallback
Event MyHandler()
End Event
OnTick = MyHandler
OnTick()
