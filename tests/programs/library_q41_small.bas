' Every library module but `oled` and `aht30` (their buffers do not fit 1 KB of RAM) on the PIC18-Q41, in one program: it must build with no warning on
' every part of the family (the 14-pin parts have no port B).
Program T
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "gpio"
Include "delay"
Include "timer"
Include "serial"
Include "serial2"
Include "adc"
Include "eeprom"
Include "flashwrite"
Include "spi"
Include "system"
Include "dma"
Include "lcd"
Include "i2c"
Include "pwm"
Dim x As Word
Dim r As Byte
Dim hz As LongWord
Gpio.GpioAllDigital()
Gpio.GpioPullUps(0, 0, 3)
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
Serial2.Serial2Init(9600)
Serial2.Serial2WriteByte(65)
r = Serial2.Serial2Read()
Adc.AdcInit()
x = Adc.AdcRead(0)
x = Adc.AdcMillivolts(x, 3300)
r = Eeprom.EepromWrite(0, 5)
x = Eeprom.EepromReadWord(0)
r = Flashwrite.FlashEraseSector(Flashwrite.FlashLastSector)
x = Flashwrite.FlashReadWord(0)
r = Spi.SpiInit(1000000, 0, 16, 17, 21)
r = Spi.SpiTransfer(85)
hz = System.SysClockHz()
r = System.SysResetCause()
r = Lcd.LcdInit(16, 17, 18, 19, 20, 21, 2)
r = I2c.I2cInit(100000, 16, 17)
r = I2c.I2cStart()
r = I2c.I2cSend(112)
x = I2c.I2cReceive(False)
r = I2c.I2cStop()
r = Pwm.PwmInit(5000)
r = Pwm.PwmStart(1, 18, 100)
Pwm.PwmPercent(1, 50)
Pwm.PwmStop(1)
r = Dma.DmaCopy(1, @x, @hz, 2)
r = Dma.DmaDone(1)
Dma.DmaStop(1)
