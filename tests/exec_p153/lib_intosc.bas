' expect: LO_FRQ=5 LO_F8=3 LO_R12=0 LO_F12=4 LO_R48=0 LO_F48=4 LO_FD=3 LO_CD=97 LO_F32=6 LO_R64=0 LO_F64=6
' Intosc library on the PIC16F153xx (PIC16F15356; DS40001897C chapter 9): the registers of the PIC18F27Q10 with the HFFRQ codes 0..6 = 1, 2, 4, 8, 12, 16, 32 MHz (7 reserved) [Register 9-6 p.114].
' Clock = 16 gives HFFRQ = 5 at start-up. SetClock(8) and SetClock(12) write codes 3 and 4 (12 MHz exists here, unlike on the PIC16F171xx); 48 and 64 MHz do not exist on this part (False, HFFRQ unchanged, where the Q10 would write the reserved code 7);
' SetClockDiv(8, 1) writes divider 1:2 (OSCCON1 = NOSC 110 << 4 | NDIV 1 = 97); SetClock(32) writes code 6. The registers are checked, not the True results of the switches: the simulator does not raise OSCCON3.ORDY /
' OSCSTAT.HFOR for this part, so those calls return False there.
Program Lo
Device = 16F15356
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINT32, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"
Dim frq As Byte
Dim f8 As Byte
Dim r12 As Byte
Dim f12 As Byte
Dim r48 As Byte
Dim f48 As Byte
Dim fd As Byte
Dim cd As Byte
Dim f32 As Byte
Dim r64 As Byte
Dim f64 As Byte
frq = OSCFRQ And 15
r12 = 0
r48 = 0
r64 = 0
IntOsc.SetClock(8)
f8 = OSCFRQ And 15
If IntOsc.SetClock(12) Then
    r12 = 1
End If
f12 = OSCFRQ And 15
If IntOsc.SetClock(48) Then
    r48 = 1
End If
f48 = OSCFRQ And 15
IntOsc.SetClockDiv(8, 1)
fd = OSCFRQ And 15
cd = OSCCON1
IntOsc.SetClockDiv(32, 0)
f32 = OSCFRQ And 15
If IntOsc.SetClock(64) Then
    r64 = 1
End If
f64 = OSCFRQ And 15
