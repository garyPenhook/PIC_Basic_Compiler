' expect: LQ_I=1 LQ_ACC=17 LQ_BAD=0 LQ_OK255=0 LQ_R1=1 LQ_R2=1 LQ_P2A=0 LQ_P2B=12 LQ_TRIS2A=32 LQ_R3=1 LQ_R4=0 LQ_R5=1 LQ_P4=14 LQ_P1=11 LQ_H1=200 LQ_SAME=1 LQ_I0=0 LQ_F0=0 LQ_S0=0 LQ_I1=1 LQ_F1=487 LQ_S1=32854 LQ_I2=1 LQ_F2=487 LQ_S2=32787 LQ_I3=1 LQ_F3=977 LQ_S3=32753 LQ_I4=1 LQ_F4=1000 LQ_S4=32000 LQ_I5=1 LQ_F5=7000 LQ_S5=4571 LQ_I6=1 LQ_F6=100000 LQ_S6=320 LQ_I7=1 LQ_F7=1000000 LQ_S7=32
' Module review 17 (pwm), PIC16F17146 (the 16-bit PWM modules): every pin of the part is routed alone through RxyPPS (RA0PPS + pin through FSR0) and gives it back when its channel stops, a restart on another pin releases the
' old pin, a pin of a running channel is refused to another channel, and the frequency and steps the init arithmetic reports for several requests (from the original search for the prescale and period).
Program Lq
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "pwm"
Dim i As Byte
Dim acc As Byte
Dim bad As Byte
Dim ok255 As Byte
Dim r1 As Byte
Dim r2 As Byte
Dim p2a As Byte
Dim p2b As Byte
Dim tris2a As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim p4 As Byte
Dim p1 As Byte
Dim h1 As Byte
Dim same As Byte
Dim p As Byte
Dim i0 As Byte
Dim f0 As LongWord
Dim s0 As Word
Dim i1 As Byte
Dim f1 As LongWord
Dim s1 As Word
Dim i2 As Byte
Dim f2 As LongWord
Dim s2 As Word
Dim i3 As Byte
Dim f3 As LongWord
Dim s3 As Word
Dim i4 As Byte
Dim f4 As LongWord
Dim s4 As Word
Dim i5 As Byte
Dim f5 As LongWord
Dim s5 As Word
Dim i6 As Byte
Dim f6 As LongWord
Dim s6 As Word
Dim i7 As Byte
Dim f7 As LongWord
Dim s7 As Word

' RxyPPS of pin q (0 for a pin the part does not have).
Function PpsOf(ByVal q As Byte) As Byte
    Result = 0
    If q = 0 Then
        Result = RA0PPS
    ElseIf q = 1 Then
        Result = RA1PPS
    ElseIf q = 2 Then
        Result = RA2PPS
    ElseIf q = 4 Then
        Result = RA4PPS
    ElseIf q = 5 Then
        Result = RA5PPS
    ElseIf q = 12 Then
        Result = RB4PPS
    ElseIf q = 13 Then
        Result = RB5PPS
    ElseIf q = 14 Then
        Result = RB6PPS
    ElseIf q = 15 Then
        Result = RB7PPS
    ElseIf q = 16 Then
        Result = RC0PPS
    ElseIf q = 17 Then
        Result = RC1PPS
    ElseIf q = 18 Then
        Result = RC2PPS
    ElseIf q = 19 Then
        Result = RC3PPS
    ElseIf q = 20 Then
        Result = RC4PPS
    ElseIf q = 21 Then
        Result = RC5PPS
    ElseIf q = 22 Then
        Result = RC6PPS
    ElseIf q = 23 Then
        Result = RC7PPS
    End If
End Function

Function PpsSum() As Word
    Dim q As Byte
    Result = 0
    q = 0
    While q < 24
        Result = Result + PpsOf(q)
        Inc(q)
    Wend
End Function

i0 = Pwm.PwmInit(1)
f0 = Pwm.PwmFrequency()
s0 = Pwm.PwmSteps()
i1 = Pwm.PwmInit(487)
f1 = Pwm.PwmFrequency()
s1 = Pwm.PwmSteps()
i2 = Pwm.PwmInit(488)
f2 = Pwm.PwmFrequency()
s2 = Pwm.PwmSteps()
i3 = Pwm.PwmInit(977)
f3 = Pwm.PwmFrequency()
s3 = Pwm.PwmSteps()
i4 = Pwm.PwmInit(1000)
f4 = Pwm.PwmFrequency()
s4 = Pwm.PwmSteps()
i5 = Pwm.PwmInit(7000)
f5 = Pwm.PwmFrequency()
s5 = Pwm.PwmSteps()
i6 = Pwm.PwmInit(99999)
f6 = Pwm.PwmFrequency()
s6 = Pwm.PwmSteps()
i7 = Pwm.PwmInit(1000000)
f7 = Pwm.PwmFrequency()
s7 = Pwm.PwmSteps()
i = Pwm.PwmInit(5000)
acc = 0
bad = 0
p = 0
While p < 26
    If Pwm.PwmStart(1, p, 50) = 1 Then
        Inc(acc)
        If PpsOf(p) <> 11 Or PpsSum() <> 11 Then
            bad = bad + 1
        End If
        Pwm.PwmStop(1)
        If PpsSum() <> 0 Then
            bad = bad + 1
        End If
    End If
    p = p + 1
Wend
ok255 = Pwm.PwmStart(1, 255, 50)
' restart of channel 2 on another pin gives the old pin back (an input again)
r1 = Pwm.PwmStart(2, 13, 50)
r2 = Pwm.PwmStart(2, 14, 50)
p2a = PpsOf(13)
tris2a = TRISB And 32
p2b = PpsOf(14)
' a pin of a running channel is refused to another channel, and free again once that channel stops
r3 = Pwm.PwmStart(3, 20, 50)
r4 = Pwm.PwmStart(4, 20, 50)
Pwm.PwmStop(3)
r5 = Pwm.PwmStart(4, 20, 50)
p4 = PpsOf(20)
Pwm.PwmStop(4)
Pwm.PwmStop(2)
' the same channel on the same pin again keeps the routing and takes the new duty
r1 = Pwm.PwmStart(1, 23, 50)
same = Pwm.PwmStart(1, 23, 200)
p1 = PpsOf(23)
h1 = PWM1S1P1L
Pwm.PwmStop(1)
