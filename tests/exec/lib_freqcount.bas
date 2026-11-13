' expect: FC_FC_N=20 FC_FC_Z=0 FC_FC_W=11
' expect-16F17146: FC_FC_N=10
' expect-16F18346: FC_FC_N=10
' expect-16F15244: FC_FC_N=10
' stim: lib_freqcount.stim.toml
' Timer.FreqCount on RC1, driven with a square wave of 4000 instruction cycles a period: 5 ms is 80000 instruction cycles at 64 MHz
' (the PIC18 parts: 20 rising edges) and 40000 cycles at 32 MHz (the PIC16 parts: 10 edges). A pin the part lacks (24) counts nothing.
Program Fc
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "timer"
Dim fc_n As Byte
Dim fc_z As Byte
Dim c As LongWord
Dim fc_w As Word
Dim wa As Word
Dim wb As Word
c = Timer.FreqCount(17, 5)
fc_n = Byte(c)
fc_z = Byte(Timer.FreqCount(24, 5))
' the wrap of the 16-bit difference FreqCount adds up: 5 - 65530 is 11 in a Word
wa = 65530
wb = 5
fc_w = wb - wa
