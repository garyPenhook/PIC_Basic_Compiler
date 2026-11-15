' AHT30 temperature and humidity on an OLED
'
' Reads an AHT30 sensor about once a second and shows the temperature and the relative humidity on a
' 128 x 64 SSD1309 OLED. Both parts share one I2C bus on the hardware host (MSSP1). If a reading fails,
' line 5 shows its status code and the last good values stay (manual, aht30: 3 = no acknowledge, 5 = busy,
' 6 = CRC mismatch).
'
' Device:  PIC18F25K22 (28-pin), 16 MHz from the internal oscillator (Config FOSC = INTIO67).
' Parts:   AHT30 (I2C address 0x38), SSD1309 128 x 64 OLED module on I2C (address 0x3C).
' Connect: SCL = RC3 (package pin 14) and SDA = RC4 (pin 15) to both parts; the K22 has no PPS, so MSSP1
'          is on these pins only (DS40001412H Table 1-2). One pull-up per line to VDD, 2.0 to 4.7 kOhm.
'          AHT30: VDD and GND. OLED: VDD, GND, and RES# tied high (the program passes 255: no reset pin);
'          its panel supply (about 12 V) is external on a bare SSD1309 module.
' Expect:  line 0 "AHT30 + OLED", line 2 "Temp  25.12 C", line 3 "Hum   45.60 %RH" (your values), updated
'          about once a second. Below 0 C the temperature shows a minus sign.
' Status:  built and run in basil-sim with aht30_oled_display.stim.toml (a simulated OLED, and a sensor that
'          answers one reading, 25.12 C and 45.60 %RH: the display shows them, then "Sensor error 5" once the
'          simulated sensor has no more data); not yet run on a real chip.

Program Aht30OledDisplay
Device = 18F25K22
Clock = 16
Config FOSC = INTIO67, WDTEN = OFF, LVP = ON, MCLRE = EXTMCLR
Include "intosc"
Include "i2c"
Include "aht30"
Include "oled"
Include "format"

Dim t As Integer                ' 1/100 degree C
Dim rh As Word                  ' 1/100 %RH
Dim st As Byte
Dim a As Word

' "25.12" for 2512: the whole part, a point and two digits.
Sub WriteHundredths(ByVal v As Word)
    FmtDec(v / 100, 0, " ")
    OledWrite(FmtBuf)
    OledWrite(".")
    FmtDec(v Mod 100, 2, "0")    ' Word, as above: one form of FmtDec is linked
    OledWrite(FmtBuf)
End Sub

st = I2cInit(100000, 19, 20)    ' 100 kHz on SCL = RC3 (pin number 19), SDA = RC4 (20)
st = OledInitI2c(60, 255)       ' 0x3C, no reset pin
OledClear()
OledTextGoto(0, 0)
OledWrite("AHT30 + OLED")
Aht30Init()

While True
    st = Aht30Measure(t, rh)    ' start, wait 80 ms, read and check the CRC
    If st = 0 Then
        OledTextGoto(0, 2)
        OledWrite("Temp ")
        If t < 0 Then
            OledWrite("-")
            a = Word(0 - t)
        Else
            OledWrite(" ")
            a = Word(t)
        End If
        WriteHundredths(a)
        OledWrite(" C   ")      ' the spaces clear a longer old value
        OledTextGoto(0, 3)
        OledWrite("Hum   ")
        WriteHundredths(rh)
        OledWrite(" %RH  ")
        OledTextGoto(0, 5)
        OledWrite("                     ")
    Else
        OledTextGoto(0, 5)
        OledWrite("Sensor error ")
        FmtDec(Word(st), 0, " ")
        OledWrite(FmtBuf)
        OledWrite("  ")
    End If
    DelayMS(920)                ' with the 80 ms of the measurement: one reading a second
Wend
