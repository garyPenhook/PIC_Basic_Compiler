' expect: LS_INIT=1 LS_BAD=0 LS_NOSPI=4 LS_ARG=5 LS_ARG2=5 LS_ARG3=5 LS_VAL=77
Program Ls
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "spi"
Include "rtccspi"
Dim init As Byte
Dim bad As Byte
Dim nospi As Byte
Dim arg As Byte
Dim arg2 As Byte
Dim arg3 As Byte
Dim val As Byte
val = 77
' A pin the part does not have is refused; a good one is made the chip select.
bad = Rtccspi.RtccspiInit(24)
init = Rtccspi.RtccspiInit(16)
' Spi not initialised: the bus routines answer 4 and leave the outputs alone.
nospi = Rtccspi.RtccspiRead()
' Bad arguments are refused before anything is sent: 5.
arg = Rtccspi.RtccspiSet(24, 2, 30, 1, 0, 0, 0)
arg2 = Rtccspi.RtccspiAlarm(2, 0, 1, 1, 1, 0, 0, 0, 0)
arg3 = Rtccspi.RtccspiRamRead(64, val)
