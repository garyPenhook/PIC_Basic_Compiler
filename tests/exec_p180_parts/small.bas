' Builds for both members of the PIC16F18056/76 family (28 and 40 pins, 2 KB of RAM, 16K words of flash): Serial and Serial2 (RC6/RC7, RB6/RB7), Adc on RA0 and, where the part has
' ports D and E (PIC16F18076), RD1 and RE1, Timer1 and Timer2, Pwm, Spi and I2c on port B and C pins, the internal oscillator, the system module, Eeprom and Flashwrite.
Program Small
Device = 16F18056
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "intosc"
Include "system"
Include "gpio"
Include "serial"
Include "serial2"
Include "adc"
Include "timer"
Include "pwm"
Include "spi"
Include "i2c"
Include "eeprom"
Include "flashwrite"
Dim v As Word
Dim ok As Byte
Dim b As Byte
Gpio.GpioAllDigital()
Serial.SerialInit(9600)
Serial.SerialWriteByte(65)
Serial2.Serial2Init(9600)
Serial2.Serial2WriteByte(66)
Adc.AdcInit()
Adc.AdcPin(0)
Adc.AdcPin(25)
Adc.AdcPin(33)
v = Adc.AdcRead(0)
Timer.Timer1Start(0)
Timer.Timer2Start(1, 0, 99)
ok = Pwm.PwmInit(1000)
ok = Pwm.PwmStart(1, 16, 5)
ok = Pwm.PwmStart(3, 8, 100)
ok = Spi.SpiInit(100000, 0, 19, 20, 21)
ok = I2c.I2cInit(100000, 9, 10)
b = Eeprom.EepromRead(0)
ok = Eeprom.EepromWrite(1, 2)
v = Flashwrite.FlashReadWord(0)
