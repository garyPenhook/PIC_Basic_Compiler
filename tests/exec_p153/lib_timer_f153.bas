' expect: LT_C0=128 LT_C1=83 LT_PER=200 LT_T1=19 LT_G1=0 LT_CLK1=1 LT_T2=146 LT_PR2V=249 LT_RUN=1 LT_GG=192 LT_T1G=3 LT_CLKG=2 LT_GATEG=1 LT_HLT=4 LT_RST=3 LT_T2L=144 LT_HIT=1 LT_STP=0 LT_RD=1 LT_F0=1 LT_F1=1 LT_F2=1 LT_FL0=0 LT_FL1=0 LT_FL2=0 LT_I0=32 LT_I1=1 LT_I2=2 LT_K1=3 LT_K2=2 LT_K3=4 LT_K4=9
' Timer library on the PIC16F153xx (PIC16F15356; DS40001866E and DS40001889E chapters 25 to 27). Timer0Start(3, 200): T0CON0 = EN (128), T0CON1 = CS FOSC/4 (010) << 5 | T0ASYNC (16, the workaround of errata DS80000728D 5.1 and
' DS80000717K 5.1) | 3 = 83, TMR0H = 200. Timer1Start(1): T1CLK = 1 (FOSC/4), T1CON = CKPS 01 << 4 | RD16 | ON = 19, T1GCON = 0 (the read-only gate value bit GVAL, bit 2, is masked). Timer2Start(1, 2, 249): T2CON = ON (128) | CKPS 1 << 4 |
' OUTPS 2 = 146, T2PR = 249. Timer1StartGated(FOSC, 0, Timer0, high): T1CLK = 2, T1GATE = 1, T1GCON = GE | GPOL = 192, T1CON = RD16 | ON = 3. Timer2StartLimit with a rising-edge reset (MODE 00100) from PWM3 (RSEL 0011) gives T2HLT = 4,
' T2RST = 3, T2CON = ON | CKPS 1 = 144 [Registers 27-3, 27-4 p.312-313 of DS40001889E]. Timer2 with period 9 runs and sets its flag; Timer2Stop clears T2CON. Timer1Read of a running timer returns a count above zero.
' The flags are TMR0IF = PIR0 bit 5, TMR1IF = PIR4 bit 0 and TMR2IF = PIR4 bit 1, their enables PIE0 bit 5 and PIE4 bits 0 and 1 [Tables 26-3 p.289, 27-2 p.314]. The T1Gate*, T1Clk* and T2Rst* codes are those of Registers 26-3, 26-4 and 27-4
' (Timer1 clock Timer0 overflow = 9).
Program Lt
Device = 16F15356
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "timer"
Dim c0 As Byte
Dim c1 As Byte
Dim per As Byte
Dim t1 As Byte
Dim g1 As Byte
Dim clk1 As Byte
Dim t2 As Byte
Dim pr2v As Byte
Dim run As Byte
Dim gg As Byte
Dim t1g As Byte
Dim clkg As Byte
Dim gateg As Byte
Dim hlt As Byte
Dim rst As Byte
Dim t2l As Byte
Dim hit As Byte
Dim stp As Byte
Dim rd As Byte
Dim f0 As Byte
Dim f1 As Byte
Dim f2 As Byte
Dim fl0 As Byte
Dim fl1 As Byte
Dim fl2 As Byte
Dim i0 As Byte
Dim i1 As Byte
Dim i2 As Byte
Dim k1 As Byte
Dim k2 As Byte
Dim k3 As Byte
Dim k4 As Byte
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
clk1 = T1CLK
Timer.Timer1Stop()
Timer.Timer2Start(1, 2, 249)
t2 = T2CON
pr2v = T2PR
f = Timer.Timer2Running()
run = 0
If f Then
    run = 1
End If
Timer.Timer2Stop()
Timer.Timer1StartGated(Timer.T1ClkFosc, 0, Timer.T1GateTmr0, True)
gg = T1GCON
t1g = T1CON
clkg = T1CLK
gateg = T1GATE
Timer.Timer1Stop()
Timer.Timer2StartLimit(1, 0, 99, Timer.T2ModeResetRising, Timer.T2RstPwm3)
hlt = T2HLT
rst = T2RST
t2l = T2CON
Timer.Timer2Stop()
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
Timer.Timer1Stop()
PIR0 = 32
f = Timer.Timer0Expired()
f0 = 0
If f Then
    f0 = 1
End If
fl0 = PIR0 And 32
PIR4 = 1
f = Timer.Timer1Expired()
f1 = 0
If f Then
    f1 = 1
End If
fl1 = PIR4 And 1
PIR4 = 2
f = Timer.Timer2Expired()
f2 = 0
If f Then
    f2 = 1
End If
fl2 = PIR4 And 2
Timer.Timer0EnableInterrupt()
i0 = PIE0 And 32
Timer.Timer1EnableInterrupt()
i1 = PIE4 And 1
Timer.Timer2EnableInterrupt()
i2 = PIE4 And 2
k1 = Timer.T1GateCcp1
k2 = Timer.T1GateTmr2
k3 = Timer.T2RstPwm4
k4 = Timer.T1ClkTmr0
