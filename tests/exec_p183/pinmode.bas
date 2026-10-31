' expect: P_A=62 P_C=49 P_WA=8 P_WC=5 P_RA=62 P_RC=49 P_RWA=8 P_RWC=5
' PinMode on the PIC16F18326 (ports A and C; DS40001839): a port bit, a constant pin number and a pin number held in a variable. TRISx is set for Input and cleared for
' Output, WPUx is set for PullUp and Input_PullUp. The first block gives the static forms, the second the same pins by number in a variable.
Program P
Device = 16F18326
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Dim n, a, c, wa, wc, ra, rc, rwa, rwc As Byte
TRISA = 255
TRISC = 0
WPUA = 0
WPUC = 0
PinMode(PORTA.0, Output)
PinMode(PORTA.5, Output)
PinMode(PORTC.0, Input_PullUp)
PinMode(PORTC.4, Input)
PinMode(5, Input)
PinMode(16 + 5, Input)
PinMode(18, PullUp)
PinMode(PORTA.3, PullUp)
a = TRISA
c = TRISC
wa = WPUA
wc = WPUC
TRISA = 255
TRISC = 0
WPUA = 0
WPUC = 0
n = 0
PinMode(n, Output)
n = 5
PinMode(n, Output)
PinMode(n, Input)
n = 16
PinMode(n, Input_PullUp)
For n = 20 To 21
    PinMode(n, Input)
Next
n = 18
PinMode(n, PullUp)
n = 3
PinMode(n, PullUp)
ra = TRISA
rc = TRISC
rwa = WPUA
rwc = WPUC
