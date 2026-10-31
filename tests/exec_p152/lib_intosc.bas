' expect: LO_FRQ=4 LO_HZ=16000000 LO_OK=1 LO_R8=1 LO_F8=3 LO_R12=0 LO_F12=3 LO_RD=0 LO_FD=3 LO_R32=1 LO_F32=5 LO_H32=32000000
' Intosc library on the PIC16F152xx (PIC16F15244; DS40002195E chapter 11): the part has no clock switching and no divider, so the module only writes OSCFRQ.FRQ (1, 2, 4, 8, 16, 32 MHz = 0..5, p.85) while
' the system clock is the HFINTOSC (RSTOSC = HFINTOSC_32MHZ, COSC = 00). Clock = 16 gives FRQ = 4 at start-up and the clock check agrees. SetClock(8) and SetClock(32) work; 12 MHz does not exist (False, FRQ unchanged);
' a divider (SetClockDiv(8, 1)) does not exist either (False, FRQ unchanged).
Program Lo
Device = 16F15244
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHZ, WDTE = OFF, LVP = ON
Include "intosc"
Include "system"
Dim frq As Byte
Dim hz As LongWord
Dim ok As Byte
Dim r8 As Byte
Dim f8 As Byte
Dim r12 As Byte
Dim f12 As Byte
Dim rd As Byte
Dim fd As Byte
Dim r32 As Byte
Dim f32 As Byte
Dim h32 As LongWord
Dim b As Boolean
frq = OSCFRQ And 7
hz = System.SysClockHz()
ok = 0
b = System.SysClockOk()
If b Then
    ok = 1
End If
r8 = 0
b = IntOsc.SetClock(8)
If b Then
    r8 = 1
End If
f8 = OSCFRQ And 7
r12 = 0
b = IntOsc.SetClock(12)
If b Then
    r12 = 1
End If
f12 = OSCFRQ And 7
rd = 0
b = IntOsc.SetClockDiv(8, 1)
If b Then
    rd = 1
End If
fd = OSCFRQ And 7
r32 = 0
b = IntOsc.SetClock(32)
If b Then
    r32 = 1
End If
f32 = OSCFRQ And 7
h32 = System.SysClockHz()
