' expect: LY_C0=0 LY_C1=1 LY_C2=2 LY_C12=1 LY_C3=3 LY_C4=4 LY_C5=5 LY_C6=6 LY_C7=7 LY_C8=8 LY_C78=7 LY_RAW=61 LY_CLR=63 LY_HZ32=32000000 LY_HZ16=16000000 LY_HZ1=1000000 LY_HZ8=8000000 LY_HZR=0 LY_HZR2=0 LY_HZ4D=125000 LY_HZB=32000000 LY_HZP=0 LY_HZX=0 LY_HZH=32000000 LY_OK=1
' System library on the PIC16F153xx (PIC16F15356; DS40001866E, DS40001897C chapters 5 and 9). PCON0 has the window violation flag nWDTWV (bit 5), so the pattern with only that bit clear is cause 5 and PCON0 reads back whole (61 reads 61,
' the cleared state 63 reads 63). Clock: COSC 110 and 000 are the HFINTOSC at OSCFRQ.HFFRQ 0..6 = 1, 2, 4, 8, 12, 16, 32 MHz (7 reserved), COSC 001 is the HFINTOSC with the 2x PLL, which runs from 16 MHz (HFFRQ 101) to 32 MHz, CDIV divides by 1 to 512
' [Register 5-1 p.76, Tables 9-1 and 9-2 p.111, Register 9-6 p.114 of DS40001897C]; any other source (LFINTOSC 101, external 111, reserved 011) gives 0. RSTOSC = HFINT32 starts the part at 32 MHz (COSC 000, HFFRQ 110).
Program Ly
Device = 16F15356
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
Dim hz1 As LongWord
Dim hz8 As LongWord
Dim hzr As LongWord
Dim hzr2 As LongWord
Dim hz4d As LongWord
Dim hzb As LongWord
Dim hzp As LongWord
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
hz32 = System.SysClockFrom(0, 0, 6)
hz16 = System.SysClockFrom(6, 0, 5)
hz1 = System.SysClockFrom(0, 0, 0)
hz8 = System.SysClockFrom(0, 0, 3)
hzr = System.SysClockFrom(0, 0, 7)
hzr2 = System.SysClockFrom(0, 0, 8)
hz4d = System.SysClockFrom(6, 3, 0)
hzb = System.SysClockFrom(1, 0, 5)
hzp = System.SysClockFrom(1, 0, 6)
hzx = System.SysClockFrom(3, 0, 5)
' The simulator leaves OSCFRQ at 1 MHz at reset instead of the 32 MHz of RSTOSC = 000 (Register 5-1), so it is set here.
OSCFRQ = 6
hzh = System.SysClockHz()
f = System.SysClockOk()
ok = 0
If f Then
    ok = 1
End If
