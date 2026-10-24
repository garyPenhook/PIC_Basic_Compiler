' expect: LTH_R1=0 LTH_R2=35 LTH_R3=0 LTH_R4=1 LTH_R5=192 LTH_R6=19 LTH_R7=188 LTH_G1=8 LTH_G2=0 LTH_G3=144 LTH_RUN0=1 LTH_RUN1=0 LTH_RUN2=1
' Timer1 external clock and gate, Timer2 hardware-limit modes. Register values follow the
' datasheet: T1CON = 0x23 (CKPS 1:4, RD16, ON), T1CLK = 0 (T1CKI pin); gated: T1GATE = 1 (TMR0),
' T1GCON = GE | GPOL = 0xC0; pulse: GE | GTM | GSPM | GGO = 0xB8, plus GVAL (bit 2, pin low and
' active-low = gate active) = 0xBC; Timer2: T2HLT = 8 (one-shot), T2CON = 0x90. A one-shot
' Timer2 (period 99, 1:2) is on right after the start and has cleared ON after 200 cycles (the
' data sheet does not say it sets the flag, so that is not checked); a software-mode timer is
' still on.
Program Lth
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "timer"
Include "gpio"
Dim g1 As Byte
Dim g2 As Byte
Dim g3 As Byte
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Byte
Dim r7 As Byte
Dim run0 As Byte
Dim run1 As Byte
Dim run2 As Byte
Dim n As Byte
Gpio.GpioAllDigital()
Timer.Timer1StartCounter(2)
r1 = T1CLK
r2 = T1CON
r3 = T1GCON
Timer.Timer1Stop()
Timer.Timer1StartGated(Timer.T1ClkFosc4, 1, Timer.T1GateTmr0, True)
r4 = T1GATE
r5 = T1GCON
r6 = T1CON
Timer.Timer1Stop()
Timer.Timer1StartPulse(Timer.T1ClkFosc4, 0, Timer.T1GatePin, False, True)
r7 = T1GCON
Timer.Timer1Stop()
Timer.Timer2StartLimit(1, 0, 99, Timer.T2ModeOneShot, Timer.T2RstPin)
g1 = T2HLT
g2 = T2RST
g3 = T2CON
If Timer.Timer2Running() Then
    run0 = 1
End If
While n < 255
    Inc(n)
Wend
If Timer.Timer2Running() Then
    run1 = 1
End If
Timer.Timer2Stop()
Timer.Timer2StartLimit(1, 0, 99, Timer.T2ModeSoftware, Timer.T2RstPin)
n = 0
While n < 255
    Inc(n)
Wend
If Timer.Timer2Running() Then
    run2 = 1
End If
Timer.Timer2Stop()
