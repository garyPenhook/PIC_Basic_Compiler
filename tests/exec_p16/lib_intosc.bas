' expect: IP_FRQ=4 IP_F8=3 IP_R12=0 IP_F12=3 IP_FD=3 IP_CD=97 IP_F32=5
' Intosc library on the PIC16F171xx (OSCFRQ.FRQ 1, 2, 4, 8, 16, 32 MHz = 0..5): Clock = 16 gives FRQ = 4 at start-up; SetClock(8) and SetClock(32) switch,
' 12 MHz does not exist (False, FRQ unchanged), SetClockDiv(8, 1) writes divider 1:2 (OSCCON1 = 97). The registers are checked, not the True results of the
' switches: the simulator does not raise OSCCON3.ORDY / OSCSTAT.HFOR for this part, so those calls return False there (the same with the previous library).
Program Ip
Device = 16F17146
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"
Dim frq As Byte
Dim f8 As Byte
Dim r12 As Byte
Dim f12 As Byte
Dim fd As Byte
Dim cd As Byte
Dim f32 As Byte
frq = OSCFRQ And 15
r12 = 0
IntOsc.SetClock(8)
f8 = OSCFRQ And 15
If IntOsc.SetClock(12) Then
    r12 = 1
End If
f12 = OSCFRQ And 15
IntOsc.SetClockDiv(8, 1)
fd = OSCFRQ And 15
cd = OSCCON1
IntOsc.SetClockDiv(32, 0)
f32 = OSCFRQ And 15
