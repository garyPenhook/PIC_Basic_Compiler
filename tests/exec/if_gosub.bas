' expect: IG_A=5 IG_B=1 IG_C=0
Program Ig
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x As Byte
Dim a As Byte
Dim b As Byte
Dim c As Byte
x = 3
If x = 3 GoSub Bump
If x = 4 GoSub Bump
If x > 100 GoSub Skipped
If x <> 3 And a = 2 GoSub Skipped
If x = 5 Then
    b = 1
EndIf
a = x
GoTo Done
Bump:
x = x + 1
Return
Skipped:
c = 9
Return
Done:
