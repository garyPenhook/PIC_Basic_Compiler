' expect: BW_A=300 BW_B=904 BW_C=300 BW_D=0 BW_E=7 BW_F=0 BW_H=300 BW_I=1 BW_J=300 BW_K=38400 BW_L=0
' Named register fields wider than a byte (PLLFBD.PLLFBDIV, 12 bits) or across two bytes (REFOTRIMH.ROTRIM, bits 7 to 15)
' read and write as the 16-bit word: the neighbouring bits stay, Inc wraps inside the field, and the
' write runs with the global interrupt enable off because the program has an interrupt handler.
Program Bw
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW

Dim a As Word
Dim b As Word
Dim c As Word
Dim d As Word
Dim e As Word
Dim f As Word
Dim g As Word
Dim h As Word
Dim i As Word
Dim j As Word
Dim k As Word
Dim l As Word

Interrupt T1()
    IFS0.T1IF = 0
End Interrupt

PLLFBD = 0
PLLFBD.PLLFBDIV = 300
a = PLLFBD.PLLFBDIV
c = PLLFBD
PLLFBD.PLLFBDIV = 5000
b = PLLFBD.PLLFBDIV
PLLFBD.PLLFBDIV = 4095
Inc(PLLFBD.PLLFBDIV)
d = PLLFBD.PLLFBDIV
PLLFBD.PLLFBDIV = 3
Inc(PLLFBD.PLLFBDIV, 4)
e = PLLFBD.PLLFBDIV
Clear(PLLFBD.PLLFBDIV)
f = PLLFBD
PLLFBD.PLLFBDIV = 300
h = PLLFBD.PLLFBDIV
i = PLLFBD.PLLFBDIV.2
REFOTRIMH = 0
REFOTRIMH.ROTRIM = 300
j = REFOTRIMH.ROTRIM
k = REFOTRIMH
Inc(REFOTRIMH.ROTRIM, 212)
l = REFOTRIMH.ROTRIM
Terminate
