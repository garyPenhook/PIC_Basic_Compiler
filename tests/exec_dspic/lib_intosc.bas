' expect: IO_OSC0=4384 IO_FBD0=100 IO_DIV0=65 IO_OSC1=4384 IO_FBD1=100 IO_DIV1=33 IO_CLK2=30464 IO_OK2=1 IO_OK3=1 IO_DONE=1
' Library intosc on the dsPIC33CK: start-up at Clock = 100 (FRCPLL, M = 100, N2 = 4, N3 = 1), then SetClock(200), SetClock(8) and a speed the part lacks.
Program Io
Device = dsPIC33CK64MC105
Clock = 100
Config FWDTEN = ON_SW, FCKSM = CSECMD
Include "intosc"
Dim OSC0 As Word
Dim FBD0 As Word
Dim DIV0 As Word
Dim OSC1 As Word
Dim FBD1 As Word
Dim DIV1 As Word
Dim CLK2 As Word
Dim OK2 As Byte
Dim OK3 As Byte
Dim DONE As Byte
OSC0 = OSCCON
FBD0 = PLLFBD
DIV0 = PLLDIV
OK2 = 0
If IntOsc.SetClock(200) Then
    OK2 = 1
End If
OSC1 = OSCCON
FBD1 = PLLFBD
DIV1 = PLLDIV
OK3 = 9
If IntOsc.SetClock(8) Then
    OK3 = 1
End If
CLK2 = OSCCON
If IntOsc.SetClock(7) Then
    OK3 = 7
End If
DONE = 1
