' expect: IO_OSC0=30464 IO_DIV0=54 IO_DONE=1
' Library intosc on the dsPIC33CK at Clock = 0.125: start-up runs FRCDIVN with FRCDIV = 6 (CLKDIV high byte 0x36 with the reset DOZE), DIV0 is read before the program calls SetClock(8), which must also end on FRCDIVN (OSC0 = 0x7700).
Program Io
Device = dsPIC33CK64MC105
Clock = 0.125
Config FWDTEN = ON_SW, FCKSM = CSECMD
Include "intosc"
Dim OSC0 As Word
Dim DIV0 As Word
Dim DONE As Byte
DIV0 = CLKDIV >> 8
If IntOsc.SetClock(8) Then
    DONE = 0
End If
OSC0 = OSCCON
DONE = 1
