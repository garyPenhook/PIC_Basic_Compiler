' expect: PW_INIT=1 PW_R1=1 PW_F4=9 PW_R3=1 PW_B1=11 PW_R4=1 PW_D2=12 PW_R2=1 PW_C2=10 PW_X1=0 PW_X2=0 PW_X3=0 PW_X4=0 PW_X5=0 PW_X6=0
' Pwm on the PIC16(L)F15386, whose PPS routes each signal to two ports only (DS40001866E Table 15-7 p.243): CCP1 and CCP2 reach ports C and F, PWM3 and PWM4 ports B and D. Channel 1 (CCP1) on RF4 (pin 44) gives RF4PPS = 09h, channel 3
' (PWM3) on RB1 (pin 9) RB1PPS = 0Bh, channel 4 (PWM4) on RD2 (pin 26) RD2PPS = 0Ch, channel 2 (CCP2) on RC2 (pin 18) RC2PPS = 0Ah. Refused: CCP2 on RA0 (0), RB3 (11), RD0 (24) and RE3 (35, input only), PWM3 on RC2 is not tried
' while PWM3 runs; the pin of a part that has no such port (48) is refused too.
Program Pw
Device = 16F15386
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "pwm"
Dim init As Byte
Dim r1 As Byte
Dim f4 As Byte
Dim r3 As Byte
Dim b1 As Byte
Dim r4 As Byte
Dim d2 As Byte
Dim r2 As Byte
Dim c2 As Byte
Dim x1 As Byte
Dim x2 As Byte
Dim x3 As Byte
Dim x4 As Byte
Dim x5 As Byte
Dim x6 As Byte
init = Pwm.PwmInit(5000)
r1 = Pwm.PwmStart(1, 44, 100)
f4 = RF4PPS
r3 = Pwm.PwmStart(3, 9, 50)
b1 = RB1PPS
r4 = Pwm.PwmStart(4, 26, 50)
d2 = RD2PPS
x1 = Pwm.PwmStart(2, 0, 100)
x2 = Pwm.PwmStart(2, 11, 100)
x3 = Pwm.PwmStart(2, 24, 100)
x4 = Pwm.PwmStart(2, 35, 100)
x5 = Pwm.PwmStart(2, 48, 100)
r2 = Pwm.PwmStart(2, 18, 100)
c2 = RC2PPS
x6 = Pwm.PwmStart(2, 3, 100)
