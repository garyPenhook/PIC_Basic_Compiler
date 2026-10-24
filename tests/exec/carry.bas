' expect: T_A=1256 T_B=744 T_C=65536 T_D=1256 T_E=66 T_F=65 T_G=5
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a, b, d As Word
Dim c As LongWord
Dim k As Byte
Dim e, f As Byte
Dim g As Byte
Dim ch As Char = "A"
Sub Q(ByVal x As Char = "B")
    e = Byte(x)
End Sub
a = 1000 : k = 200 : k = k + 100 : a = a + 256
b = 1000 : b = b - 256
c = 0 : c = c + 65536
d = 1000 : d = d + 256
Q()
f = Byte(ch)
Asm
    movlw 5
    movwf T_G, c
End Asm
