' expect: PPIF_A=1 PPIF_B=2 PPIF_C=3 PPIF_D=4 PPIF_F=6
Program PpIf
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
Dim a As Byte
Dim b As Byte
Dim c As Byte
Dim d As Byte
Dim e As Byte
Dim f As Byte
#if _clock = 16
a = 1
#else
a = 99
#endif
#if _clock < 8
b = 99
#elseif _clock >= 16 and _device = 18F27Q10
b = 2
#else
b = 98
#endif
#if _clock in (1, 2, 4) or not(_device in (18F27Q10, 18F26Q10))
c = 99
#elseif _clock in (8, 16, 32)
c = 3
#endif
#if 0
d = 99
#if 1
d = 98
#endif
#elseif _device <> 18F27Q10
d = 97
#elseif (_clock = 16)
d = 4
#elseif 1
d = 96
#endif
#if not(_clock = 16)
e = 99
#endif
#if _clock = 0.5 or _clock = 12
f = 99
#else
f = 6
#endif
