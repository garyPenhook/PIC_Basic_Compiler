' expect: BF_A=2 BF_B=5 BF_C=1 BF_D=3 BF_E=1 BF_F=0 BF_G=9 BF_H=1
' devices: 18F27Q10
' Named multi-bit fields of device registers read and write like a structure's Bits(n): the neighbouring bits stay and Inc wraps
' inside the field. The program has an interrupt handler, so each write runs with the global interrupt enable off.
Program Bf
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a As Byte
Dim b As Byte
Dim c As Byte
Dim d As Byte
Dim e As Byte
Dim f As Byte
Dim g As Byte
Dim h As Byte

Interrupt T0()
End Interrupt

T2CON.ON = 1
T2CON.CKPS = 2
a = T2CON.CKPS
T2CON.OUTPS = 5
b = T2CON.OUTPS
c = T2CON.ON
T2CON.CKPS = 3
d = T2CON.CKPS
e = T2CON.ON
T2CON.CKPS = 7
Inc(T2CON.CKPS)
f = T2CON.CKPS
T0CON1.T0CKPS = 9
g = T0CON1.T0CKPS
h = T2CON.OUTPS And 1
