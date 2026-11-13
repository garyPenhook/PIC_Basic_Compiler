' expect: LQ_STEPS=572 LQ_H37=52 LQ_L37=192 LQ_H100=143 LQ_L100=0 LQ_H1=1 LQ_L1=64 LQ_H0=0 LQ_L0=0 LQ_HOVER=143 LQ_LOVER=0 LQ_H99=141 LQ_L99=128
' PwmPercent works out steps * pct / 100 as (steps / 4) * pct / 25 in a Word (steps is 4 * n, n at most 256). 7 kHz at 64 MHz: n = 143, steps = 572.
' duty = 572 * 37 / 100 = 211 (211.64 rounded down): CCPR1H = 211 >> 2 = 52, CCPR1L = (211 and 3) << 6 = 192. 572 * 1 / 100 = 5, 572 * 99 / 100 = 566.
' 100 percent is 572 (143, 0); above 100 is 100 percent.
Program Lq
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pwm"
Dim ok As Byte
Dim steps As Word
Dim h37 As Byte
Dim l37 As Byte
Dim h100 As Byte
Dim l100 As Byte
Dim h1 As Byte
Dim l1 As Byte
Dim h0 As Byte
Dim l0 As Byte
Dim hover As Byte
Dim lover As Byte
Dim h99 As Byte
Dim l99 As Byte
ok = Pwm.PwmInit(7000)
steps = Pwm.PwmSteps()
ok = Pwm.PwmStart(1, 18, 0)
Pwm.PwmPercent(1, 37)
h37 = CCPR1H
l37 = CCPR1L
Pwm.PwmPercent(1, 100)
h100 = CCPR1H
l100 = CCPR1L
Pwm.PwmPercent(1, 1)
h1 = CCPR1H
l1 = CCPR1L
Pwm.PwmPercent(1, 0)
h0 = CCPR1H
l0 = CCPR1L
Pwm.PwmPercent(1, 150)
hover = CCPR1H
lover = CCPR1L
Pwm.PwmPercent(1, 99)
h99 = CCPR1H
l99 = CCPR1L
