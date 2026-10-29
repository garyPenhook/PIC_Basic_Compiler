' expect: T_G=114 T_R1=114
Program T
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Dim x As Byte
Dim g As Word
Dim r1 As Word
Sub S(ByRef a As Byte)
    g = AddressOf(a)
End Sub
S(x)
r1 = @x
