' expect: LT12_N1=2 LT12_N2=3 LT12_C1=19 LT12_K1=1 LT12_C2=147 LT12_K2=1 LT12_P2=49 LT12_OK=1
' Timer1/Timer2 library: Timer1Start(1) runs the 16-bit Timer1 from FOSC/4 with a 1:2 prescaler
' (T1CON = 0x13) and overflows every 131072 cycles; Timer2Start(1, 3, 49) runs Timer2 with a 1:2
' prescaler and a 1:4 postscaler (T2CON = 0x93), so its flag is set every 50 * 2 * 4 = 400 cycles.
' Both flags are read and cleared with the Expired routines; Timer1Read sees the count move.
Program Lt12
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "timer"
Include "delay"
Dim n1 As Byte
Dim n2 As Byte
Dim c1 As Byte
Dim k1 As Byte
Dim c2 As Byte
Dim k2 As Byte
Dim p2 As Byte
Dim a As Word
Dim b As Word
Dim ok As Byte
Timer.Timer2Start(1, 3, 49)
c2 = T2CON
k2 = T2CLKCON
p2 = T2PR
While n2 < 3
    If Timer.Timer2Expired() Then
        Inc(n2)
    End If
Wend
Timer.Timer2Stop()
Timer.Timer1Start(1)
c1 = T1CON
k1 = T1CLK
a = Timer.Timer1Read()
Delay.DelayNop()
Delay.DelayNop()
b = Timer.Timer1Read()
If b > a Then
    ok = 1
End If
While n1 < 2
    If Timer.Timer1Expired() Then
        Inc(n1)
    End If
Wend
Timer.Timer1Stop()
