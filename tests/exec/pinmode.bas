' expect: T_B=255 T_WB=34 T_A=126 T_C=176 T_WC=128
' devices: 18F27Q10
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a, b, c, wb, wc As Byte
Dim led As PORTA.0
TRISA = 255
TRISB = 0
WPUB = 0
TRISC = 0
PinMode(PORTB.0, Input)
PinMode(PORTB.1, PullUp)
PinMode(PORTB.5, Input_PullUp)
PinMode(PORTB, Input)
PinMode(led, Output)
PinMode(6, Input)
PinMode(7, Output)
PinMode(16 + 4, Input)
PinMode(2 * 8 + 5, Input)
PinMode(23, Input_PullUp)

a = TRISA
b = TRISB
c = TRISC
wb = WPUB
wc = WPUC
