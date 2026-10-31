' expect: LP_INIT=1 LP_HZ=5000 LP_STEPS=400 LP_PR=99 LP_T2C=6 LP_TMRS=85 LP_OK1=1 LP_CON1=156 LP_H1=100 LP_L1=64 LP_PPS1=12 LP_TRIS1=0 LP_OK3=1 LP_CON3=128 LP_H3=50 LP_L3=0 LP_PPS3=2 LP_POL3=144 LP_OKP=0 LP_OKA=0 LP_OKB=0 LP_REINIT=0 LP_OK2=1 LP_CON2=156 LP_PPS2=13 LP_H2=50 LP_CON1B=0 LP_PPS1B=0 LP_TRIS1B=4 LP_T2B=6 LP_T2C0=0 LP_CON2B=0 LP_INV2=0 LP_INIT2=1 LP_STEPS2=512 LP_BADHZ=0 LP_BADHZ2=0
' The PIC16F183xx (PIC16F18346; DS40001839E chapters 18, 28 and 29): CCP1, CCP2, PWM5 and PWM6 on Timer2 (channels 1..4); RxyPPS = 0Ch, 0Dh, 02h, 03h [Register 13-2 p.163].
' The read-only OUT bit (bit 5 of CCPxCON and PWMxCON) follows the pin level and is masked out of the readings. Timer2 has prescalers 1, 4, 16, 64: 5 kHz at 32 MHz needs prescale 16 (T2CKPS = 2, T2CON = TMR2ON | 2 = 6),
' PR2 + 1 = 100, 400 steps; CCPTMRS is written to 55h (all CCP on Timer2, reset value 55h).
Program Lp
Device = 16F18346
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "pwm"
Dim init As Byte
Dim hz As LongWord
Dim steps As Word
Dim pr As Byte
Dim t2c As Byte
Dim tmrs As Byte
Dim ok1 As Byte
Dim con1 As Byte
Dim h1 As Byte
Dim l1 As Byte
Dim pps1 As Byte
Dim tris1 As Byte
Dim ok3 As Byte
Dim con3 As Byte
Dim h3 As Byte
Dim l3 As Byte
Dim pps3 As Byte
Dim pol3 As Byte
Dim okp As Byte
Dim oka As Byte
Dim okb As Byte
Dim reinit As Byte
Dim ok2 As Byte
Dim con2 As Byte
Dim pps2 As Byte
Dim h2 As Byte
Dim con1b As Byte
Dim pps1b As Byte
Dim tris1b As Byte
Dim t2b As Byte
Dim t2c0 As Byte
Dim con2b As Byte
Dim inv2 As Byte
Dim init2 As Byte
Dim steps2 As Word
Dim badhz As Byte
Dim badhz2 As Byte
' 5 kHz at 32 MHz: prescale 16, PR2 + 1 = 100, 400 steps.
init = Pwm.PwmInit(5000)
hz = Pwm.PwmFrequency()
steps = Pwm.PwmSteps()
' CCP1 on RC2 (pin 18) at 401 steps: high byte 100, low bits 01 in bits 7:6.
ok1 = Pwm.PwmStart(1, 18, 401)
pr = PR2
t2c = T2CON
tmrs = CCPTMRS
con1 = CCP1CON And 223
h1 = CCPR1H
l1 = CCPR1L
pps1 = RC2PPS
tris1 = TRISC And 4
' PWM5 (channel 3) on RA0 (pin 0) at 200 steps, then inverted.
ok3 = Pwm.PwmStart(3, 0, 200)
con3 = PWM5CON And 223
h3 = PWM5DCH
l3 = PWM5DCL
pps3 = RA0PPS
ok3 = Pwm.PwmInvert(3, True)
pol3 = PWM5CON And 223
' Refused: RA3 is not a CCP1 pin, RC2 is in use, a channel 5 does not exist; Init refuses while running.
okp = Pwm.PwmStart(1, 3, 0)
oka = Pwm.PwmStart(3, 18, 0)
okb = Pwm.PwmStart(5, 18, 0)
reinit = Pwm.PwmInit(1000)
ok2 = Pwm.PwmStart(2, 13, 100)
con2 = CCP2CON And 223
pps2 = RB5PPS
Pwm.PwmPercent(2, 50)
h2 = CCPR2H
Pwm.PwmStop(1)
con1b = CCP1CON And 223
pps1b = RC2PPS
tris1b = TRISC And 4
t2b = T2CON
Pwm.PwmStop(2)
Pwm.PwmStop(3)
t2c0 = T2CON
con2b = CCP2CON And 223
inv2 = Pwm.PwmInvert(2, True)
' 15.625 kHz: prescale 4, PR2 = 127, 512 steps (prescale 2 does not exist). Frequencies out of range are refused.
init2 = Pwm.PwmInit(15625)
steps2 = Pwm.PwmSteps()
badhz = Pwm.PwmInit(0)
badhz2 = Pwm.PwmInit(1)
