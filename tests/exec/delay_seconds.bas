' cycles: 32000000 32000200
' DelaySeconds(0) waits no time; DelaySeconds(2) is two passes of DelayMS(1000), 16 000 000 cycles each at 64 MHz.
' DelayNop is the call, a nop and the return.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "delay"
Dim n As Byte
n = 0
DelaySeconds(n)
n = 2
DelaySeconds(n)
DelayNop()
