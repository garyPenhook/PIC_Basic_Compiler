Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim flag As Byte
Private Volatile Dim big As Word
Interrupt Tmr0Int()
    flag = 1
End Interrupt
Sub Tick()
    Static Volatile Dim n As Byte
    Volatile Static Dim m(2) As Byte = (1, 2)
    Inc(n)
    m(0) = n
End Sub
Tick()
big = flag
