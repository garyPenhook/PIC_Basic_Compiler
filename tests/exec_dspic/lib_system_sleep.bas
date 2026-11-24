' expect: SY_SLP=2 SY_N=0 SY_DONE=1
' Library system on the dsPIC33CK: the sleep routines (pwrsav, clrwdt, WDTCONL.ON) assemble and link, and SLPDIV reads back 2 from Config SWDTPS = PS4. They are not run: the MDB simulator does not wake the part from a watchdog Sleep.
Program Sy
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW, SWDTPS = PS4
Include "system"
Dim SLP As Word
Dim N As Byte
Dim DONE As Byte
SLP = (WDTCONL >> 1) And 31
N = 0
If SLP = 99 Then
    System.Snooze(0)
    System.Sleep(1)
    System.Sleep()
    N = System.SysWakeCause()
End If
DONE = 1
