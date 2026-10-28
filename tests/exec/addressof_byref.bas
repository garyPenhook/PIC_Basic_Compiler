' expect: T_G=4 T_R1=4
' expect-18F16Q41: T_G=1284 T_R1=1284
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x As Byte
Dim g As Word
Dim r1 As Word
Sub S(ByRef a As Byte)
    g = AddressOf(a)
End Sub
S(x)
r1 = @x
