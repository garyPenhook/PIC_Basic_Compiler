' expect: T_A=252 T_B=1 T_C=241 T_WB=3 T_WC=5 T_WA=0 T_N=0
' devices: 18F27Q10
' PinMode with the pin number in a variable: each pin of PORTA, PORTB and PORTC is picked by number; a number past the last port changes nothing.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim p, n, a, b, c, wa, wb, wc As Byte
TRISA = 0
TRISB = 255
TRISC = 0
WPUA = 0
WPUB = 0
WPUC = 0
For p = 2 To 7
    PinMode(p, Input)
Next
p = 8
PinMode(p, Output)
For p = 1 To 7
    PinMode(p + 8, Output)
Next
For n = 4 To 7
    PinMode(n + 16, Input)
Next
p = 9
PinMode(p, PullUp)
p = 8
PinMode(p, Input_PullUp)
PinMode(p + 8, Input_PullUp)
p = 2 * 8 + 2
PinMode(p, PullUp)
p = 200
PinMode(p, Input)
n = 0
a = TRISA
b = TRISB
c = TRISC
wa = WPUA
wb = WPUB
wc = WPUC
