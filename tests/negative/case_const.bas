' expect: E-ARGS
Program Cc
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim s As String(5) = "abc"
Sub Up(ByRefConst t As String)
    ToUpper(t)
End Sub
Up(s)
