' Every library module in one program: it must build with no warning.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "gpio"
Include "delay"
Include "timer"
Include "serial"
Dim x As Word
Dim r As Byte
Gpio.GpioAllDigital()
Gpio.GpioPullUps(0, 3, 0)
Delay.DelaySeconds(1)
Timer.Timer0Start(1, 99)
x = Timer.Timer0Read()
Timer.Timer1Start(0)
x = Timer.Timer1Read()
Timer.Timer2Start(0, 0, 99)
r = Timer.Timer2Read()
Serial.SerialInit(115200)
Serial.SerialWrite("hello")
Serial.SerialWriteWord(1234)
Serial.SerialWriteHex(171)
Serial.SerialNewLine()
Serial.SerialFlush()
r = Serial.SerialRead()
