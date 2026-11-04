' expect: SN_SN_A=1 SN_SN_B=0
' Snooze and the timed Sleep are compiled and linked, but not run (the simulator would sleep): the calls are not taken.
Program Sn
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = SWDTEN, LVP = ON
Include "system"
Dim go As Byte
Dim sn_a As Byte
Dim sn_b As Byte
go = 1
sn_a = 1
If go = 0 Then
    System.Snooze(6)
    System.Sleep(3)
    sn_b = 9
End If
