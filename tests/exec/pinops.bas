' expect: T_A=42 T_B=248 T_C=111 T_WA=127 T_WB=245 T_WC=132 T_WB2=0
' devices: 18F27Q10
' PinSet / PinClear (latch only) and PinPullup (WPUx) on a port bit, a port, a constant pin number and a run-time pin number.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim p, a, b, c, wa, wb, wb2, wc As Byte
LATA = 0
LATB = 255
LATC = 0
WPUA = 0
WPUB = 255
WPUC = 0
PinSet(PORTA.3)
PinClear(PORTB.0)
PinSet(PORTC)
PinClear(PORTC.7)
PinSet(1)
PinClear(9)
p = 10
PinClear(p)
p = 20
PinClear(p)
p = 5
PinSet(p)
p = 200
PinSet(p)
PinPullup(PORTA.0)
PinPullup(Enable, PORTA)
PinPullup(Disable, PORTA.7)
PinPullup(Disable, 9)
p = 11
PinPullup(Off, p)
PinPullup(On, PORTC.2)
p = 23
PinPullup(Enable, p)
a = LATA
b = LATB
c = LATC
wa = WPUA
wb = WPUB
wc = WPUC
PinPullup(Disable, PORTB)
wb2 = WPUB
