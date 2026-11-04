' expect: E-TYPE
Program Sp
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a(4) As Byte
Dim n As Byte
Sub F(ByRef p() As Byte)
    n = SizeOf(p)
End Sub
F(a)
