' expect: ID_FRQ=0 ID_CON=97
Program Id
Device = 18F27Q10
Clock = 0.5
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"
Dim frq As Byte
Dim con As Byte
' Clock = 0.5 -> HFINTOSC at 1 MHz (HFFRQ 0000), divider 1:2 (NDIV 0001).
frq = OSCFRQ And 15
con = OSCCON1
