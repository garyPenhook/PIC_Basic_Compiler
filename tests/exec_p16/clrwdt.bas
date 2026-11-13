' expect: CW_CW_A=3 CW_CW_B=7
' ClrWdt() is one clrwdt instruction; a statement, no arguments, usable in a loop and in a Sub.
Program Cw
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = SWDTEN, LVP = ON
Dim cw_a As Byte
Dim cw_b As Byte
Dim i As Byte

Sub Kick()
    ClrWdt()
    cw_b = cw_b + 1
End Sub

For i = 1 To 3
    ClrWdt()
    cw_a = cw_a + 1
Next
For i = 1 To 7
    Kick()
Next
