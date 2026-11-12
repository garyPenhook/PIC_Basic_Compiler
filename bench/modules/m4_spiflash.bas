' SPI flash reader: JEDEC id (9Fh) and a 32-byte read (03h) from a 25-series part on MSSP1 at 8 MHz, hex dump and
' checksum on the serial port, id cached in EEPROM, read time taken with Timer1. Chip select on RB0.
' Modules: gpio, pinio, spi, serial, eeprom, timer.
Program M4
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "gpio"
Include "pinio"
Include "spi"
Include "serial"
Include "eeprom"
Include "timer"
Dim id(3) As Byte
Dim i As Byte
Dim v As Byte
Dim ok As Byte
Dim sum As Word
Dim t0 As Word
Dim t1 As Word

Sub ReadId()
    Pinio.PinSet(8, False)
    Spi.SpiWrite($9F)
    id(0) = Spi.SpiRead()
    id(1) = Spi.SpiRead()
    id(2) = Spi.SpiRead()
    Pinio.PinSet(8, True)
End Sub

Sub Dump(ByVal addr As Word)
    Pinio.PinSet(8, False)
    Spi.SpiWrite(3)
    Spi.SpiWrite(Byte(addr >> 8))
    Spi.SpiWrite(Byte(addr))
    Spi.SpiWrite(0)
    sum = 0
    For i = 0 To 31
        v = Spi.SpiRead()
        sum = sum + v
        Serial.SerialWriteHex(v)
        Serial.SerialWrite(" ")
    Next
    Pinio.PinSet(8, True)
    Serial.SerialNewLine()
End Sub

Gpio.GpioAllDigital()
Serial.SerialInit(115200)
Pinio.PinOutput(8)
Pinio.PinSet(8, True)
ok = Spi.SpiInit(8000000, 0, 19, 21, 20)
Timer.Timer1Start(0)
ReadId()
For i = 0 To 2
    Serial.SerialWriteHex(id(i))
Next
Serial.SerialNewLine()
For i = 0 To 2
    ok = Eeprom.EepromWrite(16 + i, id(i))
Next
t0 = Timer.Timer1Read()
Dump(0)
t1 = Timer.Timer1Read()
Serial.SerialWrite("SUM=")
Serial.SerialWriteWord(sum)
Serial.SerialWrite(" CLK=")
Serial.SerialWriteWord(t1 - t0)
Serial.SerialNewLine()
Spi.SpiOff(19, 21)
While True
Wend
