' expect: LY_C0=0 LY_C1=1 LY_C2=2 LY_C12=1 LY_C3=3 LY_C4=4 LY_C5=0 LY_C6=6 LY_C7=7 LY_C8=8 LY_C78=7 LY_RAW=29 LY_CLR=31 LY_HZ32=32000000 LY_HZ16=16000000 LY_HZ24=24000000 LY_HZ1=1000000 LY_HZ4D=125000 LY_HZR=0 LY_HZR2=0 LY_HZ7=32000000 LY_HZ12=3000000 LY_HZB=0 LY_HZH=32000000 LY_OK=1
' System library on the PIC16F183xx (PIC16F18326; DS40001839E chapters 6 and 7). PCON0 has no window violation flag (bit 5 is unimplemented, Table 6-5 p.77), so the pattern that would be cause 5 elsewhere
' gives 0 here. Clock: COSC 000 (HFINTOSC with the 2x PLL) with HFFRQ 6, 5 = 32, 24 MHz, COSC 110 (HFINTOSC) with HFFRQ 6, 0, 3 = 16, 1, 4 MHz divided by CDIV (3 = 8: 125 kHz); bit 5 is unimplemented, so PCON0 reads back without it (61 reads 29, the cleared state 63 reads 31), HFFRQ 7 = 32 MHz, and the
' reserved codes (HFFRQ 2 with COSC 110, HFFRQ 3 with COSC 000) and any other source give 0 [Table 7-1, Register 7-6 p.93]. RSTOSC = HFINT32 starts the part at 32 MHz through the PLL (COSC 000, OSCFRQ 6).
Program Ly
Device = 16F18326
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
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
Dim hz24 As LongWord
Dim hz1 As LongWord
Dim hz4d As LongWord
Dim hzr As LongWord
Dim hzr2 As LongWord
Dim hz7 As LongWord
Dim hz12 As LongWord
Dim hzb As LongWord
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
hz32 = System.SysClockFrom(0, 0, 6)
hz16 = System.SysClockFrom(6, 0, 6)
hz24 = System.SysClockFrom(0, 0, 5)
hz1 = System.SysClockFrom(6, 0, 0)
hz4d = System.SysClockFrom(6, 3, 0)
hzr = System.SysClockFrom(6, 0, 2)
hzr2 = System.SysClockFrom(0, 0, 3)
hz7 = System.SysClockFrom(6, 0, 7)
hz12 = System.SysClockFrom(6, 2, 5)
hzb = System.SysClockFrom(4, 0, 6)
hzh = System.SysClockHz()
f = System.SysClockOk()
ok = 0
If f Then
    ok = 1
End If
