' expect: ISRT_TICKS=3 ISRT_DONE=1
' Timer 1 interrupts three times; the handler counts, clears its flag and the main line waits for the count.
Program Isrt
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW

Volatile Dim ticks As Word
Dim done As Byte

Interrupt T1()
    IFS0.T1IF = 0
    Inc(ticks)
End Interrupt

PR1 = 100
T1CON = 0
IFS0.T1IF = 0
IEC0.T1IE = 1
T1CON.TON = 1
Enable(T1)
While ticks < 3
Wend
Disable(T1)
T1CON.TON = 0
done = 1
Terminate
