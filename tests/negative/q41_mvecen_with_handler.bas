' expect: E-CONFIG
' The PIC18-Q41 vector table (MVECEN = ON) is not generated: a program with a handler may not ask for it.
Program T
Device = 18F16Q41
Clock = 1
Config MVECEN = ON
Dim n As Byte
Interrupt Tick()
    Inc(n)
End Interrupt
Enable(Tick)
