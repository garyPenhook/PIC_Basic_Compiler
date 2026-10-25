' expect: LY_C0=0 LY_C1=1 LY_C2=2 LY_C12=1 LY_C3=3 LY_C4=4 LY_C5=5 LY_C6=6 LY_C7=7 LY_C8=8 LY_C78=7 LY_RAW=61 LY_CLR=63 LY_HZ=64000000 LY_OK=1 LY_HZ8=8000000 LY_OK8=1 LY_HZ1=1953 LY_HZB=0 LY_HZR=6000000 LY_HZ12=3000000
Program Ly
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
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
Dim hz As LongWord
Dim ok As Byte
Dim hz8 As LongWord
Dim ok8 As Byte
Dim hz1 As LongWord
Dim hzb As LongWord
Dim hzr As LongWord
Dim hz12 As LongWord
' Each case writes the PCON0 pattern a Reset would leave and reads the cause back.
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
clr = PCON0
' Clock: the simulator does not load the oscillator registers from RSTOSC (they read 0) and OSCCON2 is read-only, so
' the conversion is tested through SysClockFrom with the values of Table 5-1 / 5.6.5; SysClockHz must agree with it.
hz = System.SysClockFrom(6, 0, 8)
ok = Bit(System.SysClockHz() = System.SysClockFrom((OSCCON2 >> 4) And 7, OSCCON2 And 15, OSCFRQ And 15))
hz8 = System.SysClockFrom(6, 0, 3)
ok8 = Bit(System.SysClockFrom(6, 1, 3) = 4000000)
hz1 = System.SysClockFrom(6, 9, 0)
hzb = System.SysClockFrom(6, 0, 9) + System.SysClockFrom(6, 10, 8) + System.SysClockFrom(5, 0, 8) + System.SysClockFrom(7, 0, 8)
hzr = System.SysClockFrom(6, 3, 7)
hz12 = System.SysClockFrom(6, 2, 4)
