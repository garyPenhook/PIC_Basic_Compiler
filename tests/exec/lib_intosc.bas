' expect: IC_FRQ0=5 IC_CON0=96 IC_FRQ1=3 IC_CON1=96 IC_FRQ2=2 IC_CON2=99 IC_BAD1=0 IC_FRQ3=2 IC_BAD2=0 IC_CON3=99 IC_FRQ4=8 IC_CON4=96
Program Ic
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"
Dim frq0 As Byte
Dim con0 As Byte
Dim frq1 As Byte
Dim con1 As Byte
Dim frq2 As Byte
Dim con2 As Byte
Dim bad1 As Boolean
Dim frq3 As Byte
Dim bad2 As Boolean
Dim con3 As Byte
Dim frq4 As Byte
Dim con4 As Byte
Dim r As Boolean
' Start-up code: Clock = 16 -> HFFRQ 0101, NOSC = HFINTOSC, divider 1:1.
frq0 = OSCFRQ And 15
con0 = OSCCON1
' The simulator does not model ORDY/HFOR (they read 0) or OSCCON2, so the routines wait out their bound and
' answer False; what is checked is what they wrote and that they refuse what the part does not have.
r = IntOsc.SetClock(8)
frq1 = OSCFRQ And 15
con1 = OSCCON1
r = IntOsc.SetClockDiv(4, 3)
frq2 = OSCFRQ And 15
con2 = OSCCON1
' Not oscillator settings: refused, nothing written.
bad1 = IntOsc.SetClock(20)
frq3 = OSCFRQ And 15
bad2 = IntOsc.SetClockDiv(8, 10)
con3 = OSCCON1
r = IntOsc.SetClock(64)
frq4 = OSCFRQ And 15
con4 = OSCCON1
