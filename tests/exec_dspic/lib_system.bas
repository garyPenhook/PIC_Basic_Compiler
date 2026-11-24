' expect: SY_CAUSE=1 SY_FLAGS=3 SY_WAKE0=0 SY_HZ=100000000 SY_OK=1 SY_CAUSE2=0 SY_WAKE1=2 SY_WAKE2=3 SY_WAKE3=1 SY_DONE=1
' Library system on the dsPIC33CK: reset cause after a power-on Reset (POR and BOR set), clock check at 100 MHz, SysWakeFrom codes, and the flags after SysClearResetFlags.
Program Sy
Device = dsPIC33CK64MC105
Clock = 100
Config FWDTEN = ON_SW, FCKSM = CSECMD
Include "intosc"
Include "system"
Dim CAUSE As Byte
Dim FLAGS As Byte
Dim WAKE0 As Byte
Dim HZ As LongWord
Dim OK As Byte
Dim CAUSE2 As Byte
Dim WAKE1 As Byte
Dim WAKE2 As Byte
Dim WAKE3 As Byte
Dim DONE As Byte
CAUSE = System.SysResetCause()
FLAGS = System.SysResetFlags() And 3
WAKE0 = System.SysWakeCause()
HZ = System.SysClockHz()
OK = 0
If System.SysClockOk() Then
    OK = 1
End If
System.SysClearResetFlags()
CAUSE2 = System.SysResetCause()
WAKE1 = System.SysWakeFrom(24)
WAKE2 = System.SysWakeFrom(16)
WAKE3 = System.SysWakeFrom(8)
DONE = 1
