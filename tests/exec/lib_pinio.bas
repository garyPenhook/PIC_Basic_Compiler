' expect: LP_A=170 LP_B=255 LP_C=1 LP_A2=128 LP_B2=191 LP_C2=0 LP_G2=0 LP_G3=0 LP_G5=0
' devices: 18F27Q10
Program Lp
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pinio"
Dim a As Byte
Dim b As Byte
Dim c As Byte
Dim a2 As Byte
Dim b2 As Byte
Dim c2 As Byte
Dim g1 As Boolean
Dim g2 As Boolean
Dim g3 As Boolean
Dim g4 As Boolean
Dim g5 As Boolean
Dim i As Byte
LATA = 0
LATB = 0
LATC = 0
For i = 1 To 7 Step 2
    Pinio.PinSet(i, True)
Next
Pinio.PinSet(7, True)
a = LATA
For i = 8 To 15
    Pinio.PinSet(i, True)
Next
b = LATB
Pinio.PinSet(16, True)
c = LATC
' clear bit 3 of A and bit 6 of B; pin 24 and above change nothing
Pinio.PinSet(3, False)
Pinio.PinSet(5, False)
Pinio.PinSet(1, False)
Pinio.PinSet(14, False)
Pinio.PinSet(24, True)
Pinio.PinSet(200, True)
Pinio.PinSet(16, False)
a2 = LATA
b2 = LATB
c2 = LATC
' PinGet reads PORTx. MDB does not mirror LATx into PORTx, so only the picsim engine sees g1 = g4 = 1 (checked by hand with --engine sim);
' the pins read low or are refused here.
TRISA = 0
TRISB = 0
TRISC = 0
LATC = 16
g1 = Pinio.PinGet(20)
g2 = Pinio.PinGet(21)
g3 = Pinio.PinGet(24)
LATA = 128
g4 = Pinio.PinGet(7)
g5 = Pinio.PinGet(6)
