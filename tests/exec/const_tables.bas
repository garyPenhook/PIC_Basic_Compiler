' expect: CT_R1=0 CT_R2=49 CT_R3=255 CT_R4=128 CT_R5=256 CT_R6=218 CT_R7=3 CT_R8=5 CT_R9=45 CT_R10=25 CT_R11=4096 CT_R12=0
Program Ct
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Const N = 16
Const Base = 10
' squares, with the index named i
Const Sq(8) As Byte = Table(i, i * i)
' a 16-step sine wave centred on 128: the compiler works out Sin
Const Wave(N) As Byte = Table(k, Byte(Round(127.5 + 127.5 * Sin(k * 6.2831853 / N))))
' powers of 16; Pow and Log2 are worked out by the compiler
Const Pw(4) As Word = Table(e, Round(Pow(2, e * 4)))
Const Lg(3) As Byte = Table(j, Round(Log2(Pow(2, j + 3))))
' other constants and Min can be used
Const Cl(4) As Byte = Table(c, Min(Base + c * 15, 45))
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Word
Dim r6 As Byte
Dim r7 As Byte
Dim r8 As Byte
Dim r9 As Byte
Dim r10 As Byte
Dim r11 As Word
Dim r12 As Byte
Dim ix As Byte
ix = 7
r1 = Sq(0)
r2 = Sq(ix)
r3 = Wave(4)
r4 = Wave(0)
r5 = Pw(2)
r6 = Wave(2)
r7 = Lg(0)
r8 = Lg(2)
r9 = Cl(3)
r10 = Cl(1)
r11 = Pw(3)
r12 = Wave(12)
End
