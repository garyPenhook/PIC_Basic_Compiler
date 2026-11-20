' expect: T_G=6 T_R1=6 T_H=7 T_R2=7 T_K=8 T_R3=8
' expect-18F16Q41: T_G=1286 T_R1=1286 T_H=1287 T_R2=1287 T_K=1288 T_R3=1288
' AddressOf of a ByRef parameter is the address of the variable passed. S is called with two variables, so it
' reads its pointer; Once has one call, so the optimiser names its variable directly (propagate_ref_params) and the
' address must still be that variable's.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x As Byte
Dim y As Byte
Dim z As Byte
Dim g As Word
Dim h As Word
Dim k As Word
Dim r1 As Word
Dim r2 As Word
Dim r3 As Word
Sub S(ByRef a As Byte)
    g = AddressOf(a)
End Sub
Sub Once(ByRef a As Byte)
    k = AddressOf(a)
End Sub
S(y)
h = g
S(x)
Once(z)
r1 = @x
r2 = @y
r3 = @z
