' expect: LT_N=3 LT_CFG0=128 LT_CFG1=65 LT_PERIOD=99 LT_OK=1
' Timer library on the PIC18F16Q41: Timer0Start(1, 99) runs an 8-bit Timer0 from FOSC/4 with a 1:2
' prescaler, so it overflows every 100 * 2 = 200 instruction cycles; Timer0Expired reports and clears
' each overflow (TMR0IF is PIR3 bit 7). The 16-bit mode counts up and Timer0Read sees it move.
Program Lt
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "timer"
Include "gpio"
Include "delay"
Dim n As Byte
Dim cfg0 As Byte
Dim cfg1 As Byte
Dim period As Byte
Dim a As Word
Dim b As Word
Dim ok As Byte
Gpio.GpioAllDigital()
Timer.Timer0Start(1, 99)
cfg0 = T0CON0
cfg1 = T0CON1
period = TMR0H
While n < 3
    If Timer.Timer0Expired() Then
        Inc(n)
    End If
Wend
Timer.Timer0Stop()
Timer.Timer0Start16(0)
a = Timer.Timer0Read()
Delay.DelayNop()
Delay.DelayNop()
b = Timer.Timer0Read()
If b > a Then
    ok = 1
End If
