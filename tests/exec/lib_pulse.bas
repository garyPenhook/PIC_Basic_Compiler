' expect: LP_RC=1 LP_T0=0 LP_LAT=0 LP_TB=8 LP_TC=1
' devices: 18F27Q10
' The pulse module in the simulator, which has no pin model: the set-up and the final pin states are checked (pulses end low,
' PwmPin leaves its pin an input), and RCin on a pin that is not at the level returns 1 at once. Pot is not run (it waits
' the full 65535 units on a pin that never rises).
Program Lp
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pulse"
Dim rc As Word
Dim t0 As Byte
Dim lat As Byte
Dim tb As Byte
Dim tc As Byte
TRISB = 255
TRISC = 0
ANSELB = 255
ANSELC = 255
LATB = 0
LATC = 0
Pulse.PulseOut(8, 5, True)
t0 = TRISB And 1
Pulse.PulseOut(9, 5)
Pulse.Servo(10, 120)
Pulse.PwmPin(11, 50, 2)
Pulse.Sound(12, 100, 1)
Pulse.Sound(13, 200, 1)
Pulse.Sound(14, 0, 1)
Pulse.Sound2(15, 14, 1000, 2000, 2)
lat = LATB
tb = TRISB
' A pin the part lacks, and equal pins: nothing happens.
Pulse.PulseOut(30, 5, True)
Pulse.Sound2(8, 8, 1000, 1000, 2)
rc = Pulse.RCin(16, True)
tc = TRISC And 1
