' expect: LY_C0=0 LY_C1=1 LY_C2=2 LY_C12=1 LY_C3=3 LY_C4=4 LY_C5=0 LY_C6=6 LY_C7=7 LY_C8=8 LY_C78=7 LY_RAW=29 LY_CLR=31 LY_HZ32=32000000 LY_HZ16=16000000 LY_HZ1=1000000 LY_HZ8=8000000 LY_HZR=0 LY_HZR2=0 LY_HZ4D=0 LY_HZB=0 LY_HZX=0 LY_HZH=32000000 LY_OK=1
' System library on the PIC16F152xx (PIC16F15244; DS40002195E chapters 10 and 11). PCON0 has no window violation flag (bit 5 is unimplemented, p.73), so the pattern that would be cause 5 elsewhere
' gives 0 here, and PCON0 reads back without bit 5 (61 reads 29, the cleared state 63 reads 31). Clock: COSC 00 and 10 are the HFINTOSC at OSCFRQ.FRQ 0, 3, 4, 5 = 1, 8, 16, 32 MHz [Table 11-1 p.77, OSCFRQ p.85];
' there is no divider (any divider code gives 0), FRQ 6 and 7 are reserved and any other source (LFINTOSC 01, external 11) gives 0. RSTOSC = HFINTOSC_32MHZ starts the part at 32 MHz (COSC 00, FRQ 5).
Program Ly
Device = 16F15244
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHZ, WDTE = OFF, LVP = ON
Include "system"
Dim c0 As Byte
Dim c1 As Byte
Dim c2 As Byte
Dim c12 As Byte
Dim c3 As Byte
Dim c4 As Byte
Dim c5 As Byte
Dim c6 As Byte
Dim c7 As Byte
Dim c8 As Byte
Dim c78 As Byte
Dim raw As Byte
Dim clr As Byte
Dim hz32 As LongWord
Dim hz16 As LongWord
Dim hz1 As LongWord
Dim hz8 As LongWord
Dim hzr As LongWord
Dim hzr2 As LongWord
Dim hz4d As LongWord
Dim hzb As LongWord
Dim hzx As LongWord
Dim hzh As LongWord
Dim ok As Byte
Dim f As Boolean
PCON0 = 63
c0 = System.SysResetCause()
PCON0 = 61
c1 = System.SysResetCause()
raw = System.SysResetFlags()
PCON0 = 62
c2 = System.SysResetCause()
PCON0 = 60
c12 = System.SysResetCause()
PCON0 = 55
c3 = System.SysResetCause()
PCON0 = 47
c4 = System.SysResetCause()
PCON0 = 31
c5 = System.SysResetCause()
PCON0 = 59
c6 = System.SysResetCause()
PCON0 = 191
c7 = System.SysResetCause()
PCON0 = 127
c8 = System.SysResetCause()
PCON0 = 255
c78 = System.SysResetCause()
System.SysClearResetFlags()
clr = PCON0 And 63
hz32 = System.SysClockFrom(0, 0, 5)
hz16 = System.SysClockFrom(2, 0, 4)
hz1 = System.SysClockFrom(0, 0, 0)
hz8 = System.SysClockFrom(0, 0, 3)
hzr = System.SysClockFrom(0, 0, 6)
hzr2 = System.SysClockFrom(0, 0, 7)
hz4d = System.SysClockFrom(0, 3, 0)
hzb = System.SysClockFrom(1, 0, 5)
hzx = System.SysClockFrom(3, 0, 5)
' The simulator leaves OSCFRQ at 1 MHz at reset instead of the 32 MHz of RSTOSC = 00 (Table 11-1), so it is set here.
OSCFRQ = 5
hzh = System.SysClockHz()
f = System.SysClockOk()
ok = 0
If f Then
    ok = 1
End If
