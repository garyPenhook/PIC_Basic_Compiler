' expect: O_INIT=1 O_PRES=0 O_BAD=0 O_RB=1 O_DONE=1
' stim: lib_onewire.scl
' cycles: 27000 29800
' Library onewire on the dsPIC33CK at Clock = 32 (16 MIPS) on RB0 (pin 16) with the line pulled high and no device: OwInit succeeds, OwReset sees no presence pulse (False), a pin the part lacks (RA5 = 5) is refused, and OwReadBit reads the
' released line high. The cycle window holds the timing of one reset (490 + 70 + 410 us) and of the bit slots (about 75 us each) to a few per cent: at 16 MIPS 970 us is 15520 cycles and a slot about 1200: 28384 cycles in all (1.77 ms).
Program O
Device = dsPIC33CK64MC105
Clock = 32
Config FWDTEN = ON_SW
Include "onewire"
Dim INIT As Byte
Dim PRES As Byte
Dim BAD As Byte
Dim RB As Byte
Dim DONE As Byte
BAD = 0
If Onewire.OwInit(5) Then
    BAD = 1
End If
INIT = 0
If Onewire.OwInit(16) Then
    INIT = 1
End If
PRES = 0
If Onewire.OwReset() Then
    PRES = 1
End If
Onewire.OwWriteByte($A5)
RB = 0
If Onewire.OwReadBit() Then
    RB = 1
End If
DONE = 1
