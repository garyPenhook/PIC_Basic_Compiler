' expect: PB_TD=247 PB_AD=247 PB_LD=8 PB_TE=13 PB_AE=5 PB_LE=2 PB_TF=191 PB_AF=191 PB_LF=64 PB_G46=1 PB_G33=1 PB_OK47=1 PB_OK48=0 PB_OKA=1 PB_TD2=255 PB_LA=0 PB_PD=90 PB_PF=170 PB_AE2=0 PB_EQD=1 PB_EQF=1
' Pinio on the PIC16(L)F15386, which has ports A to F (DS40001866E Table 1 p.3, Table 15-4 p.239): the pin numbers go on past port C, RD0..RD7 = 24..31, RE0..RE7 = 32..39, RF0..RF7 = 40..47, the numbers of the PPS input
' register values and of the ADC channels. PinOutput clears the ANSELx bit and the TRISx bit, PinSet writes LATx, PinInput gives the pin back. A pin of a port the part lacks (48 and above) is refused by PinOk and ignored by the routines.
' Port E has four pins (RE0..RE3, RE3 input only with no ANSELE bit), so TRISE reads back 13 and ANSELE 5 after the 253 written through the pin routines. LATA..LATF, PORTA..PORTF and TRISA..TRISF are consecutive on the part (device file), and the RxyPPS registers of port F are not, which Pinio does not use.
Program Pb
Device = 16F15386
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "pinio"
Dim td As Byte
Dim ad As Byte
Dim ld As Byte
Dim te As Byte
Dim ae As Byte
Dim le As Byte
Dim tf As Byte
Dim af As Byte
Dim lf As Byte
Dim g46 As Byte
Dim g33 As Byte
Dim ok47 As Byte
Dim ok48 As Byte
Dim oka As Byte
Dim td2 As Byte
Dim la As Byte
Dim pd As Byte
Dim pf As Byte
Dim ae2 As Byte
Dim eqd As Byte
Dim eqf As Byte
Dim f As Boolean
ANSELD = 255
ANSELE = 255
ANSELF = 255
TRISD = 255
TRISE = 255
TRISF = 255
LATD = 0
LATE = 0
LATF = 0
Pinio.PinOutput(27)
Pinio.PinOutput(33)
Pinio.PinOutput(46)
Pinio.PinSet(27, True)
Pinio.PinSet(33, True)
Pinio.PinSet(46, True)
td = TRISD
ad = ANSELD
ld = LATD
te = TRISE
ae = ANSELE
le = LATE
tf = TRISF
af = ANSELF
lf = LATF
f = Pinio.PinGet(46)
g46 = 0
If f Then
    g46 = 1
End If
f = Pinio.PinGet(33)
g33 = 0
If f Then
    g33 = 1
End If
ok47 = 0
If Pinio.PinOk(47) Then
    ok47 = 1
End If
ok48 = 0
If Pinio.PinOk(48) Then
    ok48 = 1
End If
oka = 0
If Pinio.PinOk(0) Then
    oka = 1
End If
Pinio.PinInput(27)
td2 = TRISD
LATA = 0
Pinio.PinSet(48, True)
Pinio.PinSet(100, True)
la = LATA
Pinio.PortWrite(24, 90)
pd = LATD
Pinio.PortWrite(40, 170)
pf = LATF
Pinio.PortDigital(32)
ae2 = ANSELE
eqd = 0
If Pinio.PortRead(24) = PORTD Then
    eqd = 1
End If
eqf = 0
If Pinio.PortRead(40) = PORTF Then
    eqf = 1
End If
