' expect: RTF_B=16 RTF_C=17 RTF_Y=5
' devices: 18F27Q10
' A Boolean copied from an inlined constant result and tested in the next statement (`Result = Ok(p) : If Result Then`): the copy's test
' `movf R, f` was dropped because `movf Ok, w` had set the same flags, and `pass_wreg` then dropped that load across the statement end, so the
' branch read the flags of an unrelated `clrf`. The Put call must run, and the Word result must be 5.
Program Rtf
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim b As Byte
Dim c As Byte
Dim y As Byte
Private Function Ok(ByVal p As Byte) As Boolean
    Result = p < 24
End Function
Private Sub Put(ByVal p As Byte)
    LATB = p
    LATC = p + 1
End Sub
Private Function Op(ByVal p As Byte) As Boolean
    Result = Ok(p)
    If Result Then
        Put(p)
    End If
End Function
Private Function Sp(ByVal p As Byte) As Word
    Result = 0
    If Op(p) Then
        Result = 5
    End If
End Function
y = Byte(Sp(16))
b = LATB
c = LATC
