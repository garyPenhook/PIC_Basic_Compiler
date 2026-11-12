' Multi-sensor logger: ADC (3 channels, averaged, to millivolts), Timer0 tick, EEPROM ring log with a saved
' pointer, serial report, GPIO. Modules: gpio, serial, adc, eeprom, timer.
Program M1
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "gpio"
Include "serial"
Include "adc"
Include "eeprom"
Include "timer"
Dim slot As Byte
Dim ch As Byte
Dim raw As Word
Dim mv As Word
Dim hi As Word
Dim lo As Word
Dim addr As Word
Dim ok As Byte

Sub Report(ByVal c As Byte, ByVal v As Word)
    Serial.SerialWrite("CH")
    Serial.SerialWriteWord(c)
    Serial.SerialWrite("=")
    Serial.SerialWriteWord(v)
    Serial.SerialNewLine()
End Sub

Gpio.GpioAllDigital()
TRISB = 0
Serial.SerialInit(115200)
Adc.AdcInit()
For ch = 0 To 2
    Adc.AdcPin(ch)
Next
slot = Eeprom.EepromRead(1000)
If slot >= 100 Then
    slot = 0
End If
lo = 65535
hi = 0
Timer.Timer0Start(15, 249)
While True
    If Timer.Timer0Expired() Then
        For ch = 0 To 2
            raw = Adc.AdcReadAvg(ch, 8)
            mv = Adc.AdcMillivolts(raw, 3300)
            Report(ch, mv)
            If mv > hi Then
                hi = mv
            End If
            If mv < lo Then
                lo = mv
            End If
            addr = slot
            addr = addr * 6 + ch * 2
            ok = Eeprom.EepromWriteWord(addr, mv)
        Next
        slot = slot + 1
        If slot >= 100 Then
            slot = 0
        End If
        ok = Eeprom.EepromWrite(1000, slot)
        LATB = Byte(hi >> 4)
        LATC = Byte(lo >> 4) Or ok
    End If
Wend
