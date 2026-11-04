' expect: SL_SL_A=1 SL_SL_B=0
' The Sleep routine is compiled and linked, but not run (the simulator would sleep for ever): the call is not taken.
Program Sl
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "system"
Dim go As Byte
Dim sl_a As Byte
Dim sl_b As Byte
go = 1
sl_a = 1
If go = 0 Then
    System.Sleep()
    sl_b = 9
End If
