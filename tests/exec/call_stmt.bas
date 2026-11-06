' expect: CS_A=7 CS_B=12 CS_C=3
Program Cs
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a As Byte
Dim b As Byte
Dim c As Byte
Dim call As Byte
Sub SetA(v As Byte)
    a = v
End Sub
Sub AddB(x As Byte, y As Byte)
    b = x + y
End Sub
Sub Three()
    c = 3
End Sub
Call SetA(7)
CALL AddB(5, 7)
Call Three()
call = 1
