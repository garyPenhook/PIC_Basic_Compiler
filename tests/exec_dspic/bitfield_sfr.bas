' expect: BF_A=2 BF_B=5 BF_C=1 BF_D=3 BF_E=1 BF_F=0 BF_G=7 BF_H=2
' Named multi-bit fields of device registers read and write like a structure's Bits(n): the neighbouring bits stay,
' the field can be in the second byte of a 16-bit register, and Inc wraps inside the field. The program has an
' interrupt handler, so each write runs with the global interrupt enable off (the read-modify-write guard).
Program Bf
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW

Dim a As Byte
Dim b As Byte
Dim c As Byte
Dim d As Byte
Dim e As Byte
Dim f As Byte
Dim g As Byte
Dim h As Byte

Interrupt T1()
    IFS0.T1IF = 0
End Interrupt

T1CON.TCS = 1
T1CON.TCKPS = 2
a = T1CON.TCKPS
CLKDIV.FRCDIV = 5
b = CLKDIV.FRCDIV
c = T1CON.TCS
T1CON.TCKPS = 3
d = T1CON.TCKPS
e = T1CON.TCS
T1CON.TCKPS = 3
Inc(T1CON.TCKPS)
f = T1CON.TCKPS
CLKDIV.FRCDIV = 6
Inc(CLKDIV.FRCDIV)
g = CLKDIV.FRCDIV
h = OSCCON.COSC And 2
Terminate
