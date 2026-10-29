' expect: T_HI=128 T_V0=11 T_V2=33 T_ROUT=0
' AddressOf of a Const array is an FSR address on the PIC16F17146: the word address with bit 7 of the high byte set
' (DS40002343F section 9.1.1.2), so FSR1 loaded with it reads the table through INDF1. A routine's address is the plain
' program word address (bit 7 clear): T_ROUT is bit 15 of it. Offsets of the table are added to the value.
Program T
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Const Tbl(3) As Byte = (11, 22, 33)
Dim p As LongWord
Dim hi As Byte
Dim v0 As Byte
Dim v2 As Byte
Dim rout As Byte
Dim r As LongWord
Sub Blink()
    Inc(PORTC)
End Sub
p = AddressOf(Tbl)
hi = Byte(p >> 8) And 128
Asm
    movf T_P, w
    movwf FSR1L
    movf T_P+1, w
    movwf FSR1H
    moviw 0[FSR1]
    movwf T_V0
    moviw 2[FSR1]
    movwf T_V2
End Asm
r = AddressOf(Blink)
rout = Byte(r >> 8) And 128
