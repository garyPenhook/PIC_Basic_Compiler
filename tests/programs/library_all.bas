' Every library module in one program: it must build with no warning.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "gpio"
Include "delay"
Include "timer"
Include "serial"
Include "serial2"
Include "adc"
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
Serial2.Serial2Init(115200)
Serial2.Serial2Write("hello")
Serial2.Serial2WriteWord(1234)
Serial2.Serial2WriteHex(171)
Serial2.Serial2NewLine()
Serial2.Serial2Flush()
r = Serial2.Serial2Read()
Adc.AdcInit()
Adc.AdcPin(0)
Adc.AdcRefVdd()
x = Adc.AdcRead(0)
x = Adc.AdcReadAvg(0, 8)
x = Adc.AdcMillivolts(x, 3300)
Adc.AdcRefFvr(1)
