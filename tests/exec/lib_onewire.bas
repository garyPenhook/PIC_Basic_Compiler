' expect: OWT_OWT_A=1 OWT_OWT_B=0 OWT_OWT_C=158 OWT_OWT_D=0 OWT_OWT_E=0 OWT_OWT_F=1 OWT_OWT_G=0
' devices: 18F27Q10 16F17146 16F15244
' 1-Wire master: the pin is accepted (a pin above 23 is not), a reset on a line that reads low (RA1; nothing drives the
' simulated pin, so no pull-up) is refused, a read slot on it gives 0 and a search finds nothing, the CRC8 of a ROM code
' (28 01 02 03 04 05 06) is 158 and with that byte appended it comes out 0, and the global interrupt enable is as it was.
' The slot timing and the answers of slaves are checked by `scripts/test_onewire.py`.
Program Owt
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "onewire"
Dim owt_a As Boolean
Dim owt_b As Boolean
Dim owt_c As Byte
Dim owt_d As Byte
Dim owt_e As Boolean
Dim owt_f As Boolean
Dim owt_g As Boolean
Dim gie As INTCON.7
Dim i As Byte
Dim c As Byte
owt_g = OwInit(30)
owt_a = OwInit(1)
gie = 1
owt_b = OwReset()
owt_e = OwReadBit()
c = 0
c = OwCrc8(c, $28)
For i = 1 To 6
    c = OwCrc8(c, i)
Next
owt_c = c
c = OwCrc8(c, c)
owt_d = c
owt_f = Not OwSearchFirst()
owt_f = owt_f And gie = 1
