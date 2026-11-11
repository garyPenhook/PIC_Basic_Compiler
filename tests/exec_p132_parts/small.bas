' Builds for every member of the PIC16F13214/15/24/25/44/45 family (8, 14 and 20 pins), down to the 8-pin PIC16F13214 (port A only, 512 bytes of RAM, 4K words of flash):
' both EUSARTs (Serial on RA4 / RA5 and Serial2 on RA2 / RA1 where there is no port C), Adc on RA2, Timer1, the data EEPROM, Flashwrite, the 16-bit PWM, I2c and Spi on port A pins.
Program Small
Device = 16F13214
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "serial"
Include "serial2"
Include "adc"
Include "timer"
Include "eeprom"
Include "flashwrite"
Include "pwm"
Include "i2c"
Include "spi"
Dim v As Word
Dim w As Word
Dim b As Byte
Dim ok As Byte
Serial.SerialInit(9600)
Serial.SerialWriteByte(65)
Serial2.Serial2Init(9600)
Serial2.Serial2WriteByte(66)
Adc.AdcInit()
Adc.AdcPin(2)
v = Adc.AdcRead(2)
Timer.Timer1Start(0)
ok = Eeprom.EepromWrite(1, 2)
b = Eeprom.EepromRead(1)
w = Flashwrite.FlashReadWord(0)
ok = Pwm.PwmInit(1000)
ok = Pwm.PwmStart(1, 0, 100)
ok = I2c.I2cInit(100000, 1, 2)
ok = Spi.SpiInit(1000000, 0, 0, 1, 2)
