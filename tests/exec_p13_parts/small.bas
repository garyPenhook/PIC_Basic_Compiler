' Builds for every member of the PIC16F13145 family, down to the 8-pin PIC16F13113 (port A only, 256 bytes of RAM, 2K words of flash):
' Serial (RA4 / RA5 where there is no port C), Adc on RA2, Timer1 and Flashwrite.
Program Small
Device = 16F13113
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "serial"
Include "adc"
Include "timer"
Include "flashwrite"
Dim v As Word
Dim w As Word
Serial.SerialInit(9600)
Serial.SerialWriteByte(65)
Adc.AdcInit()
Adc.AdcPin(2)
v = Adc.AdcRead(2)
Timer.Timer1Start(0)
w = Flashwrite.FlashReadWord(0)
