' expect: SC_SC_A=1 SC_SC_B=1 SC_SC_C=1 SC_SC_D=65 SC_SC_E=113 SC_SC_F=1 SC_SC_G=1
Program Sc
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim s As String(13) = "Hello, World1"
Dim names(3) As String(6) = ("abC", "xYz", "")
Dim c As Char = "a"
Dim d As Char = "Q"
Dim i As Byte = 1
Dim sc_a As Byte
Dim sc_b As Byte
Dim sc_c As Byte
Dim sc_d As Byte
Dim sc_e As Byte
Dim sc_f As Byte
Dim sc_g As Byte
ToUpper(s)
If s = "HELLO, WORLD1" Then
    sc_a = 1
EndIf
ToLower(s)
If s = "hello, world1" Then
    sc_b = 1
EndIf
ToUpper(names(i))
If names(i) = "XYZ" And names(0) = "abC" Then
    sc_c = 1
EndIf
ToUpper(c)
sc_d = Byte(c)
ToLower(d)
sc_e = Byte(d)
ToLower(names(2))
If names(2) = "" Then
    sc_f = 1
EndIf
d = "["
ToLower(d)
If d = "[" Then
    sc_g = 1
EndIf
