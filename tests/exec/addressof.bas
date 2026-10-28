' expect: T_P1=12 T_P2=28 T_P3=13 T_P4=15 T_P5=3981 T_PR=172 T_PT=176
' expect-18F16Q41: T_P1=1292 T_P2=1308 T_P3=1293 T_P4=1295 T_P5=1231
' AddressOf and @: RAM variables, registers, arrays and elements give a Word; a routine and a constant table give a LongWord program-memory address. Values are the symbol addresses in the .S file.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Const tbl(3) As Byte = (1, 2, 3)
Dim x As Byte
Dim y As Word
Dim arr(4) As Byte
Dim p1 As Word
Dim p2 As Word
Dim p3 As Word
Dim p4 As Word
Dim p5 As Word
Dim pr As LongWord
Dim pt As LongWord
Dim k As Byte
Sub Foo()
    Inc(x)
End Sub
k = 2
p1 = AddressOf(x)
p2 = @y
p3 = AddressOf(arr)
p4 = @arr(k)
p5 = AddressOf(PORTB)
pr = AddressOf(Foo)
pt = AddressOf(tbl)
