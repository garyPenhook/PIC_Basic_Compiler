' cycles: 16000000 16000200
' DelaySeconds(0) waits no time; DelaySeconds(2) is two passes of DelayMS(1000), 8 000 000 cycles each at 32 MHz.
' DelayNop is the call, a nop and the return.
Program T
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "delay"
Dim n As Byte
n = 0
DelaySeconds(n)
n = 2
DelaySeconds(n)
DelayNop()
