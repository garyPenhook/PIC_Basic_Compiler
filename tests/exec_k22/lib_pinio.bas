' expect: KQ_COUNT=40 KQ_OKD=1 KQ_OKE=1 KQ_BADP=0 KQ_LD=4 KQ_TD=251 KQ_LE=2 KQ_TE=5 KQ_GET=1 KQ_AD=0
' Pin numbers on the 40/44-pin PIC18(L)F2x/4xK22: ports D and E are pins 24..31 and 32..34 (PinCount 40). PinOutput(26) clears TRISD2 and
' ANSELD2, PinSet(26, True) sets LATD2; PinSet(33, True) and PinOutput(33) drive RE1; a pin above 39 is refused. PORTx, LATx and TRISx
' are consecutive (PORTA F80h, LATA F89h, TRISA F92h from the device file), which the PIC18 routines rely on.
' devices: 18F45K22
Program Kq
Device = 18F45K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "pinio"
Dim count As Byte
Dim okd As Byte
Dim oke As Byte
Dim badp As Byte
Dim ld As Byte
Dim td As Byte
Dim le As Byte
Dim te As Byte
Dim get As Byte
Dim ad As Byte
count = Pinio.PinCount
' PinOk(40) is folded to False at compile time, so the store below goes; this one keeps the symbol for the harness.
badp = 0
If Pinio.PinOk(30) Then
    okd = 1
End If
If Pinio.PinOk(34) Then
    oke = 1
End If
If Pinio.PinOk(40) Then
    badp = 1
End If
Pinio.PinOutput(26)
Pinio.PinSet(26, True)
ld = LATD
td = TRISD
ad = ANSELD And 4
Pinio.PinOutput(33)
Pinio.PinSet(33, True)
le = LATE And 7
te = TRISE And 7
If Pinio.PinGet(33) Then
    get = 1
End If
