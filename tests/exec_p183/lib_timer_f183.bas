' expect: LT_C0=128 LT_C1=67 LT_PER=200 LT_T1=17 LT_G1=0 LT_T2=21 LT_PR2V=249 LT_GG=193 LT_T1G=65 LT_RUN=1 LT_HIT=1 LT_STP=0 LT_RD=1
' Timer library on the PIC16F183xx (PIC16F18326; DS40001839E chapters 26-28). Timer0Start(3, 200): T0CON0 = T0EN (128), T0CON1 = T0CS FOSC/4 (010) << 5 | 3 = 67, TMR0H = 200.
' Timer1Start(1): T1CON = TMR1CS 00 (FOSC/4) | T1CKPS 01 << 4 | TMR1ON = 17 (no RD16 bit on this part), T1GCON = 0 (the read-only gate value bit T1GVAL, bit 2, is masked). Timer2Start(1, 2, 249): T2CON = TMR2ON (4) | T2CKPS 1 | T2OUTPS 2 << 3 = 21,
' PR2 = 249. Timer1StartGated(FOSC, 0, Timer0, high): T1GCON = TMR1GE | T1GPOL | T1GSS 01 = 193, T1CON = TMR1CS 01 << 6 | TMR1ON = 65. Timer2 with period 9 runs and sets its flag; Timer2Stop clears T2CON.
' Timer1Read of a running timer returns a count above zero.
Program Lt
Device = 16F18326
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "timer"
Dim c0 As Byte
Dim c1 As Byte
Dim per As Byte
Dim t1 As Byte
Dim g1 As Byte
Dim t2 As Byte
Dim pr2v As Byte
Dim gg As Byte
Dim t1g As Byte
Dim run As Byte
Dim hit As Byte
Dim stp As Byte
Dim rd As Byte
Dim n As Word
Dim w As Word
Dim f As Boolean
Timer.Timer0Start(3, 200)
c0 = T0CON0
c1 = T0CON1
per = TMR0H
Timer.Timer0Stop()
Timer.Timer1Start(1)
t1 = T1CON
g1 = T1GCON And 251
Timer.Timer1Stop()
Timer.Timer2Start(1, 2, 249)
t2 = T2CON
pr2v = PR2
f = Timer.Timer2Running()
run = 0
If f Then
    run = 1
End If
Timer.Timer2Stop()
Timer.Timer1StartGated(Timer.T1ClkFosc, 0, Timer.T1GateTmr0, True)
gg = T1GCON
t1g = T1CON
Timer.Timer1Stop()
Timer.Timer2Start(0, 0, 9)
hit = 0
n = 0
While n < 2000 And hit = 0
    f = Timer.Timer2Expired()
    If f Then
        hit = 1
    End If
    Inc(n)
Wend
Timer.Timer2Stop()
stp = T2CON
Timer.Timer1Start(0)
w = Timer.Timer1Read()
w = Timer.Timer1Read()
rd = 0
If w > 0 Then
    rd = 1
End If
