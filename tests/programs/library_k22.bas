' Every library module but `dma` (the part has none) on the PIC18(L)F2x/4xK22, in one program: it must build with no warning on
' every part of the family with 768 bytes of RAM or more (library_k22_small.bas leaves out `oled` for the 512-byte parts).
' Pins are the fixed ones of the family: MSSP1 RC3/RC4/RC5 (19, 20, 21), CCP1 RC2 (18), CCP4 RB0 (8) on the 28-pin parts.
Program T
Device = 18F25K22
Clock = 64
Config FOSC = INTIO67, WDTEN = OFF, LVP = ON, MCLRE = EXTMCLR
Include "intosc"
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
Include "lcd"
Include "i2c"
Include "pwm"
Include "oled"
Include "aht30"
Include "rtcc"
Include "rtccspi"
Include "pulse"
Include "irremote"
Include "x10"
Include "onewire"
Include "softserial"
Include "format"
Include "bits"
Include "buttons"
Dim x As Word
Dim x10ok As Boolean
Dim r As Byte
Dim hz As LongWord
Dim ok As Boolean
Gpio.GpioAllDigital()
Gpio.GpioPullUps(0, 3, 0)
Delay.DelaySeconds(1)
ok = IntOsc.SetClock(16)
Timer.Timer0Start(1, 99)
x = Timer.Timer0Read()
Timer.Timer1Start(0)
x = Timer.Timer1Read()
Timer.Timer2Start(0, 0, 99)
r = Timer.Timer2Read()
hz = Timer.FreqCount(16, 10)
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
x = Adc.ADin(1)
x = Adc.AdcMillivolts(x, 3300)
r = Eeprom.EepromWrite(0, 5)
x = Eeprom.EepromReadWord(0)
r = Flashwrite.FlashEraseSector(Flashwrite.FlashLastSector)
x = Flashwrite.FlashReadWord(0)
r = Spi.SpiInit(1000000, 0, 19, 21, 20)
r = Spi.SpiTransfer(85)
hz = System.SysClockHz()
r = System.SysResetCause()
System.Snooze(1)
r = Lcd.LcdInit(8, 9, 10, 11, 12, 13, 2)
r = I2c.I2cInit(100000, 19, 20)
r = I2c.I2cStart()
r = I2c.I2cSend(112)
x = I2c.I2cReceive(False)
r = I2c.I2cStop()
r = Pwm.PwmInit(5000)
r = Pwm.PwmStart(1, 18, 100)
Pwm.PwmPercent(1, 50)
Pwm.PwmStop(1)
r = Oled.OledInitI2c(60, 255)
Aht30.Aht30Init()
r = Rtcc.RtccSet(24, 10, 31, 5, 14, 30, 15)
r = Rtcc.RtccRead()
r = Rtcc.RtccAlarm(0, 2, 1, 1, 1, 7, 0, 0)
r = Rtcc.RtccEeWrite(0, r)
r = Rtccspi.RtccspiInit(1)
r = Rtccspi.RtccspiSet(24, 10, 31, 5, 14, 30, 15)
r = Rtccspi.RtccspiRead()
r = Rtccspi.RtccspiAlarm(1, 5, 1, 1, 1, 7, 0, 0, 0)
r = Rtccspi.RtccspiEeWrite(0, r)
Pulse.PulseOut(8, 5)
x = Pulse.PulseIn(9, True)
x = Pulse.RCin(9, False)
r = Pulse.Pot(9, 255)
Pulse.Servo(10, 1500)
Pulse.PwmPin(10, 128, 4)
Pulse.Sound(11, 60, 10)
Pulse.Sound2(11, 12, 440, 880, 100)
x = Irremote.SonyIn(9)
x = Irremote.RC5In(9)
x10ok = X10.Xout(8, 9, 0, X10.UnitOn, 2)
x10ok = X10.Xin(8, 9, 10, x)
ok = Onewire.OwInit(12)
ok = Onewire.OwReset()
Onewire.OwWriteByte(204)
r = Onewire.OwReadByte()
ok = Softserial.SoftInit(13, 14, 9600, False)
Softserial.SoftWriteByte(65)
x = Buttons.Counter(15, 10)
