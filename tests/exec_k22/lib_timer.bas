' expect: LT_N0=3 LT_CFG0=192 LT_TL=1 LT_OK0=1 LT_CFG16=136 LT_OK16=1 LT_C1=19 LT_OK1=1 LT_N1=2 LT_C2=5 LT_PER=99 LT_N2=4 LT_OK2=1
' Timer library on the PIC18(L)F2x/4xK22 (DS40001412H chapters 11-13):
' Timer0Start(1, 99): T0CON = TMR0ON | T08BIT | T0PS 000 (1:2) = 192 (Register 11-1), TMR0L preloaded to 255 - 99 = 156; each overflow is
' taken by Timer0Expired, which reloads TMR0L (TMR0L read soon after the start is 156 plus the counts since). Timer0Start16(0): T0CON = TMR0ON | PSA (no prescaler) = 136, and the count moves.
' Timer1Start(1): T1CON = T1CKPS 01 | T1RD16 | TMR1ON = 19 (Register 12-1); it counts and overflows (TMR1IF, PIR1 bit 0).
' Timer2Start(1, 0, 99): T2CON = TMR2ON | T2CKPS 01 (1:4) = 5, PR2 = 99 (Register 13-1); TMR2IF (PIR1 bit 1) every 400 cycles.
Program Lt
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "timer"
Include "gpio"
Include "delay"
Dim n0 As Byte
Dim cfg0 As Byte
Dim tl As Byte
Dim ok0 As Byte
Dim cfg16 As Byte
Dim ok16 As Byte
Dim c1 As Byte
Dim ok1 As Byte
Dim n1 As Byte
Dim c2 As Byte
Dim per As Byte
Dim n2 As Byte
Dim ok2 As Byte
Dim a As Word
Dim b As Word
Dim c As Byte
Gpio.GpioAllDigital()
Timer.Timer0Start(1, 99)
cfg0 = T0CON
If TMR0L >= 156 And TMR0L <= 160 Then
    tl = 1
End If
While n0 < 3
    If Timer.Timer0Expired() Then
        Inc(n0)
    End If
Wend
' After a reload TMR0L is at least 156 again (it is reloaded relative to the count since the overflow).
If TMR0L >= 156 Then
    ok0 = 1
End If
Timer.Timer0Stop()
Timer.Timer0Start16(0)
cfg16 = T0CON
a = Timer.Timer0Read()
Delay.DelayNop()
Delay.DelayNop()
b = Timer.Timer0Read()
If b > a Then
    ok16 = 1
End If
Timer.Timer0Stop()
Timer.Timer1Start(1)
c1 = T1CON
a = Timer.Timer1Read()
Delay.DelayNop()
b = Timer.Timer1Read()
If b > a Then
    ok1 = 1
End If
' 65536 * 2 cycles per overflow: two overflows.
While n1 < 2
    If Timer.Timer1Expired() Then
        Inc(n1)
    End If
Wend
Timer.Timer1Stop()
Timer.Timer2Start(1, 0, 99)
c2 = T2CON
per = PR2
While n2 < 4
    If Timer.Timer2Expired() Then
        Inc(n2)
    End If
Wend
c = Timer.Timer2Read()
If c <= 99 And Timer.Timer2Running() Then
    ok2 = 1
End If
Timer.Timer2Stop()
