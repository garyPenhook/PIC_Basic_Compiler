' expect: P_BAD=0 P_OK=1 P_STEPS=800 P_FRQ=10000 P_S1=1 P_S2=1 P_S4=1 P_PER=799 P_DC1=400 P_CON1=32776 P_IO1=27 P_IO2=20 P_IO4=24 P_RP8=8704 P_X1=0 P_X2=0 P_INIT2=0 P_STOPPED=0 P_DONE=1
' Library pwm on the dsPIC33CK: four PWM generators (Clock = 8, 10 kHz: PGxPER = 799, 800 steps). Channel 1 on PWM1H (RB14 = pin 30) with a duty of 200 steps, then 400 by PwmDuty, then inverted (restart: POLH and POLL set); channel 2 on PWM2L (RB13 = 29);
' channel 4 on RC1 (pin 33 = RP49) through PPS (RPOR8 high byte = 34 = PWM4H). Checked: PG1CONL = ON | CLKSEL 01, PGxIOCONH = PMOD 01 | PENH or PENL | POL, PGxPER, PGxDC, a frequency above FOSC / 33, a pin that is not a channel's (RB12 for channel 1), a pin
' in use, PwmInit while a channel runs are refused, and PwmStop switches the generator off (PG4CONL = 0). **The waveform is not checked:** the simulator has no PWM model for this part.
Program P
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "pwm"
Dim BAD As Byte
Dim OK As Byte
Dim STEPS As Word
Dim FRQ As LongWord
Dim S1 As Byte
Dim S2 As Byte
Dim S4 As Byte
Dim PER As Word
Dim DC1 As Word
Dim CON1 As Word
Dim IO1 As Word
Dim IO2 As Word
Dim IO4 As Word
Dim RP8 As Word
Dim X1 As Byte
Dim X2 As Byte
Dim INIT2 As Byte
Dim STOPPED As Word
Dim DONE As Byte
BAD = Pwm.PwmInit(10000000)
OK = Pwm.PwmInit(10000)
STEPS = Pwm.PwmSteps()
FRQ = Pwm.PwmFrequency()
S1 = Pwm.PwmStart(1, 30, 200)
S2 = Pwm.PwmStart(2, 29, 400)
S4 = Pwm.PwmStart(4, 33, 100)
X1 = Pwm.PwmStart(1, 28, 100)
X2 = Pwm.PwmStart(3, 29, 100)
INIT2 = Pwm.PwmInit(20000)
Pwm.PwmDuty(1, 400)
PER = PG1PER
DC1 = PG1DC
CON1 = PG1CONL
IO2 = PG2IOCONH
IO4 = PG4IOCONH
RP8 = RPOR8
X1 = X1 + Pwm.PwmInvert(5, True)
Pwm.PwmInvert(1, True)
IO1 = PG1IOCONH
Pwm.PwmStop(4)
STOPPED = PG4CONL
DONE = 1
