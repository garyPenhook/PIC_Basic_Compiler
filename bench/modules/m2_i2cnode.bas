' I2C node: bus scan, 16-bit register read from the first client found (a temperature sensor layout), four-sample
' average, Timer1 stamp, serial report, alarm pin. Modules: gpio, pinio, serial, i2c (hardware MSSP1), timer.
Program M2
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "gpio"
Include "pinio"
Include "serial"
Include "i2c"
Include "timer"
Dim addr As Byte
Dim found As Byte
Dim st As Byte
Dim i As Byte
Dim good As Byte
Dim t As Word
Dim sum As Word
Dim avg As Word
Dim stamp As Word

Gpio.GpioAllDigital()
Serial.SerialInit(115200)
Pinio.PinOutput(8)
st = I2c.I2cInit(100000, 19, 20)
found = 0
For addr = 8 To 119
    If I2c.I2cPing(addr) Then
        Serial.SerialWrite("0x")
        Serial.SerialWriteHex(addr)
        Serial.SerialNewLine()
        If found = 0 Then
            found = addr
        End If
    End If
Next
Timer.Timer1Start(3)
While True
    If Timer.Timer1Expired() Then
        sum = 0
        good = 0
        For i = 1 To 4
            st = I2c.I2cReadRegs(found, 0, 2)
            If st = 0 Then
                t = I2c.I2cBuf(0)
                t = t * 256 + I2c.I2cBuf(1)
                sum = sum + (t >> 4)
                good = good + 1
            End If
        Next
        stamp = Timer.Timer1Read()
        If good > 0 Then
            avg = sum / good
            Serial.SerialWrite("T=")
            Serial.SerialWriteWord(avg)
            Serial.SerialWrite(" @")
            Serial.SerialWriteWord(stamp)
            Serial.SerialNewLine()
            Pinio.PinSet(8, avg > 400)
        Else
            Serial.SerialWrite("ERR")
            Serial.SerialWriteHex(st)
            Serial.SerialNewLine()
            Pinio.PinSet(8, True)
        End If
    End If
Wend
