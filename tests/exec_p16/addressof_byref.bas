' expect: T_G=113 T_R1=113
' expect-O0: T_G=114 T_R1=114
' S has one call, so the optimiser names x in place of the ByRef pointer (propagate_ref_params): the pointer's RAM
' goes and x moves down a byte. AddressOf through the parameter must still be x's address.
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
