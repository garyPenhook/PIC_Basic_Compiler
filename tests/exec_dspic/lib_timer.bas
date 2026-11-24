' expect: TM_T1CON_=32784 TM_PR1_=999 TM_SRCCON=33030 TM_N=3 TM_OV=1 TM_DONE=1
' Library timer on the dsPIC33CK: Timer1StartPeriod (prescale 1 = 1:8) sets T1CON/PR1 and the flag comes once per period; Timer1StartSource sets TECS/TCS/TSYNC; Timer1Start is free-running.
Program Tm
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "timer"
Dim T1CON_ As Word
Dim PR1_ As Word
Dim SRCCON As Word
Dim N As Byte
Dim OV As Byte
Dim DONE As Byte
Timer.Timer1StartPeriod(1, 999)
T1CON_ = T1CON
PR1_ = PR1
While N < 3
    If Timer.Timer1Expired() Then
        Inc(N)
    End If
Wend
Timer.Timer1Stop()
Timer.Timer1StartSource(Timer.T1ClkFp, 0)
SRCCON = T1CON
Timer.Timer1Stop()
Timer.Timer1Start(0)
OV = 0
While Timer.Timer1Read() < 100
Wend
Timer.Timer1Stop()
OV = 1
DONE = 1
