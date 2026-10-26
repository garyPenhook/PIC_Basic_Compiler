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
Include "eeprom"
Include "flashwrite"
Include "pwm"
Include "i2c"
Include "spi"
Include "system"
Include "lcd"
Include "oled"
Include "aht30"
Dim x As Word
Dim r As Byte
Dim ti As Integer
Dim rhw As Word
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
r = Eeprom.EepromRead(0)
r = Eeprom.EepromWrite(0, r)
x = Eeprom.EepromReadWord(2)
r = Eeprom.EepromWriteWord(2, x)
x = Flashwrite.FlashReadWord(Flashwrite.FlashSectorAddr(Flashwrite.FlashLastSector))
r = Flashwrite.FlashEraseSector(Flashwrite.FlashLastSector)
r = Flashwrite.FlashWriteWord(65408, x)
r = Flashwrite.FlashUpdateWord(65408, x)
r = Pwm.PwmInit(5000)
r = Pwm.PwmStart(1, 18, 100)
r = Pwm.PwmStart(3, 0, 200)
r = Pwm.PwmInvert(3, True)
Pwm.PwmDuty(1, 300)
Pwm.PwmPercent(3, 25)
x = Word(Pwm.PwmFrequency())
x = Pwm.PwmSteps()
Pwm.PwmStop(1)
Pwm.PwmStop(3)
r = I2c.I2cInit(100000, 19, 20)
r = I2c.I2cStart()
r = I2c.I2cSend(160)
r = I2c.I2cReceive(True)
r = I2c.I2cRestart()
r = I2c.I2cStop()
r = I2c.I2cStatus()
If I2c.I2cPing(80) Then
    r = I2c.I2cWriteReg(80, 1, 2)
    r = I2c.I2cReadReg(80, 1)
End If
I2c.I2cOff(19, 20)
r = Spi.SpiInit(1000000, 0, 19, 20, 21)
r = Spi.SpiTransfer(1)
Spi.SpiWrite(2)
r = Spi.SpiRead()
r = Spi.SpiStatus()
Spi.SpiOff(19, 20)
r = System.SysResetCause()
r = System.SysResetFlags()
System.SysClearResetFlags()
If System.SysClockOk() Then
    x = Word(System.SysClockHz() / 1000)
End If
r = Lcd.LcdInit(16, 17, 18, 19, 20, 21, 2)
Lcd.LcdClear()
Lcd.LcdHome()
Lcd.LcdDisplay(True, False, False)
Lcd.LcdShift(False, True)
Lcd.LcdSetAddress(0)
Lcd.LcdGoto(0, 1)
Lcd.LcdWrite("hi")
Lcd.LcdWriteChar(65)
Lcd.LcdWriteWord(123)
Lcd.LcdWriteHex(171)
Lcd.LcdCustomRow(0, 0, 31)
Lcd.LcdCommand(1)
r = Oled.OledInitI2c(60, 255)
r = Oled.OledInitSpi(16, 17, 18)
r = Oled.OledStatus()
Oled.OledClearStatus()
Oled.OledOn(True)
Oled.OledContrast(100)
Oled.OledInvert(False)
Oled.OledAllOn(False)
Oled.OledFlip(False)
Oled.OledGoto(0, 0)
Oled.OledTextGoto(0, 1)
Oled.OledData(1)
Oled.OledFill(0)
Oled.OledClear()
Oled.OledWriteChar(65)
Oled.OledWrite("hi")
Oled.OledWriteWord(123)
Oled.OledWriteHex(171)
r = Oled.FontByte(0)
Aht30.Aht30Init()
r = Aht30.Aht30Start()
r = Aht30.Aht30Fetch(ti, rhw)
r = Aht30.Aht30Measure(ti, rhw)
