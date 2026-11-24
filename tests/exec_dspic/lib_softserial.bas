' expect: S_OK1=1 S_OK2=0 S_OK3=1 S_V=-1 S_DONE=1
' cycles: 14800 16400
' Library softserial on the dsPIC33CK: a byte at 9600 baud takes ten bit times of 416.7 instruction cycles (FOSC / 2, Clock = 8), a baud rate too high for the clock is refused, and SoftReadByte(1) on an idle line gives -1 after two poll milliseconds (2 x 4000 cycles); the total, with the three SoftInit calls, is 15.6 thousand cycles (15.3 at -O0), so the window of +-5 % holds the bit times to about 5 %.
Program S
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "softserial"
Dim OK1 As Byte
Dim OK2 As Byte
Dim OK3 As Byte
Dim V As Integer
Dim DONE As Byte
OK1 = 0
OK2 = 0
OK3 = 0
If Softserial.SoftInit(16, 17, 9600, False) Then
    OK1 = 1
End If
Softserial.SoftWriteByte($A5)
If Softserial.SoftInit(16, 17, 2000000, False) Then
    OK2 = 1
End If
If Softserial.SoftInit(255, 17, 9600, True) Then
    OK3 = 1
End If
V = Softserial.SoftReadByte(1)
DONE = 1
