' Builds for every member of the PIC16F183xx family, down to the 8-pin PIC16F18313 (port A only, 256 bytes of RAM, 2K words of flash):
' Serial (RA4 / RA5 where there is no port C), Adc on RA2, Timer1 and Timer2, Pwm and Spi and I2c on port A pins, Eeprom and Flashwrite.
Program Small
Device = 16F18313
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "serial"
Include "adc"
Include "timer"
Include "eeprom"
Include "flashwrite"
Include "pwm"
Include "spi"
Include "i2c"
Dim v As Word
Dim w As Word
Dim b As Byte
Dim ok As Byte
Serial.SerialInit(9600)
Serial.SerialWriteByte(65)
Adc.AdcInit()
Adc.AdcPin(2)
v = Adc.AdcRead(2)
Timer.Timer1Start(0)
Timer.Timer2Start(1, 0, 99)
w = Flashwrite.FlashReadWord(0)
b = Eeprom.EepromRead(0)
ok = Eeprom.EepromWrite(1, b)
ok = Pwm.PwmInit(1000)
ok = Pwm.PwmStart(1, 5, 100)
ok = Spi.SpiInit(100000, 0, 5, 4, 2)
ok = I2c.I2cInit(100000, 1, 2)
