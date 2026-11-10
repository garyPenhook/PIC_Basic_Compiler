' expect: TR_R1=4660 TR_R2=65280 TR_R3=255 TR_DONE=1
' Timer1Read and Timer0Read put the low byte in the low half and the high byte in the high half of the result. The timers
' are stopped, the count registers are written, and the reads are compared with what was written.
Program Tr
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "timer"
Dim r1 As Word
Dim r2 As Word
Dim r3 As Word
Dim done As Byte
Timer.Timer1Stop()
TMR1H = 18
TMR1L = 52
r1 = Timer.Timer1Read()
TMR1H = 255
TMR1L = 0
r2 = Timer.Timer1Read()
TMR1H = 0
TMR1L = 255
r3 = Timer.Timer1Read()
done = 1
