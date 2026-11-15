' engine: sim
' expect: KP_INIT=1 KP_OK=1 KP_CON=28 KP_RL=100 KP_PR=199 KP_T2=6 KP_HALF=1 KP_EDGES=1 KP_QUART=1 KP_INV=1 KP_OK4=1 KP_HALF4=1 KP_BAD=0
' PWM on the PIC18(L)F2x/4xK22 (DS40001412H chapter 14), sampled on the pins (basil-sim drives a CCP's fixed pin from the module):
' 5 kHz at 64 MHz is Timer2 at 1:16 with PR2 = 199 (800 steps, T2CON = TMR2ON | T2CKPS 1x = 6). PwmStart(1, 18, 401): CCPR1L = 100,
' DC1B = 01, CCP1M = 1100, so CCP1CON = 28, and RC2 is high about half the time. 200 steps is a quarter; PwmInvert (CCP1M = 1110, P1A
' active low) makes it three quarters. CCP4 drives RB0 on the 28-pin parts. Channel 2 on a pin other than its Config one is refused.
Program Kp
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "pwm"
Dim init As Byte
Dim ok As Byte
Dim con As Byte
Dim rl As Byte
Dim pr As Byte
Dim t2 As Byte
Dim half As Byte
Dim edges As Byte
Dim quart As Byte
Dim inv As Byte
Dim ok4 As Byte
Dim half4 As Byte
Dim bad As Byte
Dim hi As Word
Dim e As Word
Dim n As Word
Dim last As Byte
Dim cur As Byte

' Samples pin bit `m` of PORTC (port 2) or PORTB (port 1) 3000 times: hi = samples high, e = changes.
Sub Sample(ByVal port As Byte, ByVal m As Byte)
    hi = 0
    e = 0
    last = 0
    For n = 1 To 3000
        If port = 2 Then
            cur = PORTC And m
        Else
            cur = PORTB And m
        End If
        If cur <> 0 Then
            hi = hi + 1
        End If
        If cur <> last Then
            e = e + 1
        End If
        last = cur
    Next
End Sub

init = Pwm.PwmInit(5000)
ok = Pwm.PwmStart(1, 18, 401)
con = CCP1CON
rl = CCPR1L
pr = PR2
t2 = T2CON
Sample(2, 4)
If hi > 1200 And hi < 1800 Then
    half = 1
End If
If e >= 10 Then
    edges = 1
End If
Pwm.PwmDuty(1, 200)
Sample(2, 4)
If hi > 450 And hi < 1050 Then
    quart = 1
End If
inv = Pwm.PwmInvert(1, True)
Sample(2, 4)
If hi > 1950 And hi < 2550 Then
    inv = inv + 0
Else
    inv = 0
End If
Pwm.PwmStop(1)
ok4 = Pwm.PwmStart(4, 8, 401)
Sample(1, 1)
If hi > 1200 And hi < 1800 Then
    half4 = 1
End If
Pwm.PwmStop(4)
bad = Pwm.PwmStart(2, 11, 100)
