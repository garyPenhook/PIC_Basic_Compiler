' expect: P4_INIT=1 P4_R1=1 P4_B3=9 P4_X3=0 P4_R3=1 P4_D2=11 P4_X1=0
' Pwm on the 40-pin PIC16(L)F15376 (DS40001866E Table 15-6 p.242): CCP1 and CCP2 reach ports B and C, PWM3 and PWM4 ports B and D. CCP1 on RB3 (pin 11) gives RB3PPS = 09h; PWM3 on RC2 (pin 18) is refused, on RD2 (pin 26) it gives
' RD2PPS = 0Bh; a CCP2 channel on RD0 (pin 24) is refused.
Program P4
Device = 16F15376
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "pwm"
Dim init As Byte
Dim r1 As Byte
Dim b3 As Byte
Dim x3 As Byte
Dim r3 As Byte
Dim d2 As Byte
Dim x1 As Byte
init = Pwm.PwmInit(5000)
r1 = Pwm.PwmStart(1, 11, 100)
b3 = RB3PPS
x3 = Pwm.PwmStart(3, 18, 100)
r3 = Pwm.PwmStart(3, 26, 100)
d2 = RD2PPS
x1 = Pwm.PwmStart(2, 24, 100)
