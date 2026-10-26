Program OledFloat
Device = 18F16Q41 
Clock = 64

Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, PPS1WAY = OFF, WDTE = OFF

Include "gpio"
Include "i2c"
Include "oled"

' SSD1309 OLED on I2C: SCL = RC3 (pin 19), SDA = RC4 (pin 20), address 0x3C.
Const SclPin As Byte = 19
Const SdaPin As Byte = 20

Dim led As PORTB.0
Dim ok As Byte
Dim a, b, C As Float
Dim pass As Byte

' Writes a Float with two decimals, e.g. -12.34 (range +/-21474835).
Sub WriteFloat(ByVal f As Float)
    Dim whole As LongInt
    Dim frac As LongInt
    Dim neg As Boolean
    neg = f < 0
    If neg Then
        f = -f
    End If
    whole = LongInt(f)
    frac = LongInt((f - Float(whole)) * 100.0 + 0.5)
    If frac >= 100 Then
        Inc(whole)
        frac = frac - 100
    End If
    If neg Then
        Oled.OledWriteChar(45)
    End If
    Oled.OledWriteWord(Word(whole))
    Oled.OledWriteChar(46)
    If frac < 10 Then
        Oled.OledWriteChar(48)
    End If
    Oled.OledWriteWord(Word(frac))
End Sub

' One result line: label, value, then * if it is not within 0.01 of the expected value.
Sub ShowLine(ByVal line As Byte, ByRefConst label As String(8), ByVal v As Float, ByVal expect As Float)
    Dim d As Float
    Oled.OledTextGoto(0, line)
    Oled.OledWrite(label)
    WriteFloat(v)
    d = Abs(v - expect)
    If d > 0.01 Then
        Oled.OledWriteChar(42)
        pass = 0
    End If
End Sub

Gpio.GpioAllDigital()
Output(led)
I2c.I2cInit(400000, SclPin, SdaPin)
ok = Oled.OledInitI2c(60, 255)
If ok = 0 Then
    ' No acknowledge from the display: blink fast forever.
    Do
        Toggle(led)
        DelayMs(100)
    Loop
End If

Do
    pass = 1
    Oled.OledClear()
    Oled.OledTextGoto(0, 0)
    Oled.OledWrite("Float test")

    a = 3.14159
    b = 2.5
    ShowLine(1, "a+b  ", a + b, 5.64159)
    ShowLine(2, "a-b  ", a - b, 0.64159)
    ShowLine(3, "a*b  ", a * b, 7.853975)
    ShowLine(4, "a/b  ", a / b, 1.256636)
    C = 1.0 / 3.0
    ShowLine(5, "1/3  ", C, 0.333333)
    C = -a * 2
    ShowLine(6, "-a*2 ", C, -6.28318)

    Oled.OledTextGoto(0, 7)
    If pass = 1 Then
        Oled.OledWrite("ALL PASS")
    Else
        Oled.OledWrite("FAIL (*)")
    End If

    Toggle(led)
    DelayMs(1000)
Loop
