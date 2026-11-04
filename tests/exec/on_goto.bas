' expect: OG_OG_A=21 OG_OG_B=32 OG_OG_C=0 OG_OG_D=5 OG_OG_E=7
Program Og
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Byte
Dim w As Word
Dim og_a As Byte
Dim og_b As Byte
Dim og_c As Byte
Dim og_d As Byte
Dim og_e As Byte

i = 1
On (i + 0) GoTo l0, l1, l2
og_a = 99
Stop
l0:
og_a = 10
GoTo done1
l1:
og_a = 21
GoTo done1
l2:
og_a = 32
done1:
i = 2
Branch i, m0, m1, m2
og_b = 99
GoTo done2
m0:
og_b = 10
GoTo done2
m1:
og_b = 21
GoTo done2
m2:
og_b = 32
done2:
' out of range falls through
i = 9
On i GoTo n0, n1
og_c = 0
GoTo done3
n0:
og_c = 1
GoTo done3
n1:
og_c = 2
done3:
' a Word index
w = 3
Branch w, p0, p1, p2, p3
og_d = 1
GoTo done4
p0:
p1:
p2:
og_d = 2
GoTo done4
p3:
og_d = 5
done4:
og_e = 7
