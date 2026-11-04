' expect: TW_TW_ACC=237 TW_TW_ACC2=87
' A routine whose last statement calls a routine that takes its Byte argument in WREG, placed right after it: the call
' becomes a fall-through, and the load of that argument must survive (regression: `movf C, w` was dropped as dead at the
' statement end that sat between the two).
Program Tw
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim tw_acc As Byte
Dim tw_acc2 As Byte
Declare Sub Rec(ByVal v As Byte)
Sub Two(ByVal c As Byte, ByVal a As Byte, ByVal b As Byte)
    Rec(a)
    Rec(b)
    Rec(c)
End Sub
Sub Rec(ByVal v As Byte)
    tw_acc = (tw_acc << 2) + v
    tw_acc2 = tw_acc2 + v
End Sub
tw_acc = 0
tw_acc2 = 0
Two(3, 1, 2)
Two(1, 2, 3)
tw_acc2 = tw_acc2 * 5 + 27
