' Motor / LED drive: potentiometer on AN0 sets a duty target, ramped at a Timer0 tick onto two complementary PWM
' outputs (CCP1, CCP2 on Timer2); the duty is shown on a 74HC595; a button saves it to EEPROM.
' Modules: gpio, pinio, adc, pwm, shift, eeprom, timer.
Program M3
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "gpio"
Include "pinio"
Include "adc"
Include "pwm"
Include "shift"
Include "eeprom"
Include "timer"
Dim raw As Word
Dim target As Byte
Dim cur As Byte
Dim saved As Byte
Dim ok As Byte

Sub Show(ByVal v As Byte)
    Pinio.PinSet(10, False)
    Shift.ShiftOut(v, 8, 9, False, 8)
    Pinio.PinSet(10, True)
End Sub

Gpio.GpioAllDigital()
Gpio.GpioPullUps(0, 8, 0)
Pinio.PinOutput(10)
Pinio.PinInput(11)
Adc.AdcInit()
Adc.AdcPin(0)
ok = Pwm.PwmInit(20000)
ok = Pwm.PwmStart(1, 18, 0)
ok = Pwm.PwmStart(2, 17, 0)
saved = Eeprom.EepromRead(0)
cur = 0
If saved <= 100 Then
    cur = saved
End If
Timer.Timer0Start(9, 124)
While True
    If Timer.Timer0Expired() Then
        raw = Adc.AdcRead(0)
        target = Byte(raw / 10)
        If target > 100 Then
            target = 100
        End If
        If cur < target Then
            cur = cur + 1
        ElseIf cur > target Then
            cur = cur - 1
        End If
        Pwm.PwmPercent(1, cur)
        Pwm.PwmPercent(2, 100 - cur)
        Show(cur)
        If Not Pinio.PinGet(11) Then
            If cur <> saved Then
                ok = Eeprom.EepromWrite(0, cur)
                saved = cur
            End If
        End If
    End If
Wend
