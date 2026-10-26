' expect: LP_INIT=1 LP_HZ=5000 LP_STEPS=12800 LP_PRL=255 LP_PRH=49 LP_CP=0 LP_OK1=1 LP_CON1=128 LP_CLK=2 LP_P1L=0 LP_P1H=25 LP_PPS1=10 LP_TRIS1=0 LP_OK2=1 LP_P2L=128 LP_P2H=12 LP_PPS2=11 LP_OK5=1 LP_CON3=128 LP_PPS5=14 LP_BAD0=0 LP_BAD1=0 LP_BAD2=0 LP_BAD3=0 LP_CON1B=128 LP_CON1C=0 LP_PPS1C=0 LP_REINIT=1
' PWM library on the PIC18F16Q41 at 64 MHz: PwmInit(5000) gives 12800 clocks per period (PR = 12799 = 31FFh, no
' prescale). Channel 1 (PWM1S1P1) on RC0 at 6400 steps = 50 % (P1 = 1900h), channel 2 (PWM1S1P2) on RC1 at 3200,
' channel 5 (PWM3S1P1) on RC2. RxyPPS = 9 + channel. Stopping channel 1 leaves PWM1 running for channel 2; stopping
' channel 2 disables PWM1. Bad channel, a pin used twice, RA3 and a pin the part lacks are refused.
Program Lp
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pwm"
Dim init As Byte
Dim hz As LongWord
Dim steps As Word
Dim prl As Byte
Dim prh As Byte
Dim cp As Byte
Dim ok1 As Byte
Dim con1 As Byte
Dim clk As Byte
Dim p1l As Byte
Dim p1h As Byte
Dim pps1 As Byte
Dim tris1 As Byte
Dim ok2 As Byte
Dim p2l As Byte
Dim p2h As Byte
Dim pps2 As Byte
Dim ok5 As Byte
Dim con3 As Byte
Dim pps5 As Byte
Dim bad0 As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim con1b As Byte
Dim con1c As Byte
Dim pps1c As Byte
Dim reinit As Byte
init = Pwm.PwmInit(5000)
hz = Pwm.PwmFrequency()
steps = Pwm.PwmSteps()
ok1 = Pwm.PwmStart(1, 16, 6400)
prl = PWM1PRL
prh = PWM1PRH
cp = PWM1CPRE
con1 = PWM1CON
clk = PWM1CLK
p1l = PWM1S1P1L
p1h = PWM1S1P1H
pps1 = RC0PPS
tris1 = TRISC And 1
ok2 = Pwm.PwmStart(2, 17, 3200)
p2l = PWM1S1P2L
p2h = PWM1S1P2H
pps2 = RC1PPS
ok5 = Pwm.PwmStart(5, 18, 100)
con3 = PWM3CON And 128
pps5 = RC2PPS
bad0 = Pwm.PwmStart(0, 19, 1)
bad1 = Pwm.PwmStart(3, 16, 1)
bad2 = Pwm.PwmStart(3, 3, 1)
bad3 = Pwm.PwmStart(7, 19, 1)
Pwm.PwmStop(1)
con1b = PWM1CON And 128
Pwm.PwmStop(2)
con1c = PWM1CON And 128
pps1c = RC0PPS
Pwm.PwmStop(5)
reinit = Pwm.PwmInit(1000)
