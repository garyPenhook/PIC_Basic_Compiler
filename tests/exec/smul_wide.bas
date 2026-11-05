' Signed 16 x 16 -> 32 multiply of two Integer operands (shared routine with hardware multiplies): the
' extreme values, signs of every combination, and an accumulating form.
' expect: T_R0=1073741824 T_R1=-1073709056 T_R2=1 T_R3=0 T_R4=-60000 T_R5=-3962745 T_R6=1073676289 T_R7=-32768 T_R8=-32768 T_R9=63 T_R10=90000 T_R11=-65280 T_ACC=1069645560
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim R0 As LongInt
Dim R1 As LongInt
Dim R2 As LongInt
Dim R3 As LongInt
Dim R4 As LongInt
Dim R5 As LongInt
Dim R6 As LongInt
Dim R7 As LongInt
Dim R8 As LongInt
Dim R9 As LongInt
Dim R10 As LongInt
Dim R11 As LongInt
Dim ACC As LongInt

Function MulP(ByVal a As Integer, ByVal b As Integer) As LongInt
    Dim p As LongInt
    p = 0
    p = p + a * b
Result = p
End Function

R0 = MulP(-32768, -32768)
R1 = MulP(32767, -32768)
R2 = MulP(-1, -1)
R3 = MulP(0, -5)
R4 = MulP(300, -200)
R5 = MulP(-12345, 321)
R6 = MulP(32767, 32767)
R7 = MulP(-32768, 1)
R8 = MulP(1, -32768)
R9 = MulP(7, 9)
R10 = MulP(-300, -300)
R11 = MulP(255, -256)
ACC = 0
ACC = ACC + MulP(-32768, -32768)
ACC = ACC + MulP(32767, -32768)
ACC = ACC + MulP(-1, -1)
ACC = ACC + MulP(0, -5)
ACC = ACC + MulP(300, -200)
ACC = ACC + MulP(-12345, 321)
ACC = ACC + MulP(32767, 32767)
ACC = ACC + MulP(-32768, 1)
ACC = ACC + MulP(1, -32768)
ACC = ACC + MulP(7, 9)
ACC = ACC + MulP(-300, -300)
ACC = ACC + MulP(255, -256)
End
