' expect: LRM_E1=0 LRM_E2=0 LRM_E3=0 LRM_E4=0 LRM_E5=0 LRM_E6=0 LRM_E7=0 LRM_E8=0 LRM_E9=0 LRM_E10=0 LRM_DONE=1
' Runs the `Rtcc` routines against a model of the chip (the `i2c.bas` next to this file replaces the bus driver).
Program Lrm
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "i2c"
Include "rtcc"
Dim e1 As Byte
Dim e2 As Byte
Dim e3 As Byte
Dim e4 As Byte
Dim e5 As Byte
Dim e6 As Byte
Dim e7 As Byte
Dim e8 As Byte
Dim e9 As Byte
Dim e10 As Byte
Dim done As Byte
Dim r As Byte
Dim v As Byte
Dim fl As Boolean
Dim mo As Byte
Dim dy As Byte
Dim hr As Byte
Dim mi As Byte

Sub Chk(ByRef e As Byte, ByVal got As Byte, ByVal want As Byte)
    If got <> want Then
        Inc(e)
    End If
End Sub

r = I2c.I2cInit(100000, 19, 20)
' 1. Set: the registers hold the BCD time, ST and OSCRUN are on, the weekday survived.
Chk(e1, Rtcc.RtccSet(24, 10, 31, 5, 14, 30, 15), 0)
Chk(e1, I2c.ModelReg(0), 149)
Chk(e1, I2c.ModelReg(1), 48)
Chk(e1, I2c.ModelReg(2), 20)
Chk(e1, I2c.ModelReg(3), 37)
Chk(e1, I2c.ModelReg(4), 49)
Chk(e1, I2c.ModelReg(5), 16)
Chk(e1, I2c.ModelReg(6), 36)
' 2. Argument checks: 31 February, 29 February in a non-leap year, bad hour; 29 February 2024 is fine.
Chk(e2, Rtcc.RtccSet(24, 2, 31, 1, 0, 0, 0), 5)
Chk(e2, Rtcc.RtccSet(25, 2, 29, 1, 0, 0, 0), 5)
Chk(e2, Rtcc.RtccSet(25, 4, 31, 1, 0, 0, 0), 5)
Chk(e2, Rtcc.RtccSet(25, 4, 30, 1, 24, 0, 0), 5)
Chk(e2, Rtcc.RtccSet(24, 2, 29, 7, 23, 59, 58), 0)
Chk(e2, I2c.ModelReg(3), 39)
Chk(e2, I2c.ModelReg(4), 41)
' 3. Read back and decode.
Chk(e3, Rtcc.RtccSet(24, 10, 31, 5, 14, 30, 15), 0)
Chk(e3, Rtcc.RtccRead(), 0)
Chk(e3, Rtcc.RtccYear(), 24)
Chk(e3, Rtcc.RtccMonth(), 10)
Chk(e3, Rtcc.RtccDay(), 31)
Chk(e3, Rtcc.RtccWeekday(), 5)
Chk(e3, Rtcc.RtccHour(), 14)
Chk(e3, Rtcc.RtccMinute(), 30)
Chk(e3, Rtcc.RtccSecond(), 15)
If Not Rtcc.RtccOscRun() Then
    Inc(e3)
End If
' 12-hour readings: 1 PM, 12 AM, 12 PM, 11 PM.
I2c.ModelPoke(2, 97)
Chk(e3, Rtcc.RtccRead(), 0)
Chk(e3, Rtcc.RtccHour(), 13)
I2c.ModelPoke(2, 82)
Chk(e3, Rtcc.RtccRead(), 0)
Chk(e3, Rtcc.RtccHour(), 0)
I2c.ModelPoke(2, 114)
Chk(e3, Rtcc.RtccRead(), 0)
Chk(e3, Rtcc.RtccHour(), 12)
I2c.ModelPoke(2, 113)
Chk(e3, Rtcc.RtccRead(), 0)
Chk(e3, Rtcc.RtccHour(), 23)
I2c.ModelPoke(2, 20)
' 4. Alarms: alarm 0 keeps ALMPOL, alarm 1 is at 0x11; hour mask 2 in the weekday register.
I2c.ModelPoke(13, 128)
Chk(e4, Rtcc.RtccAlarm(0, 2, 12, 25, 3, 7, 45, 10), 0)
Chk(e4, I2c.ModelReg(10), 16)
Chk(e4, I2c.ModelReg(11), 69)
Chk(e4, I2c.ModelReg(12), 7)
Chk(e4, I2c.ModelReg(13), 163)
Chk(e4, I2c.ModelReg(14), 37)
Chk(e4, I2c.ModelReg(15), 18)
Chk(e4, Rtcc.RtccAlarm(1, 7, 1, 2, 4, 23, 59, 58), 0)
Chk(e4, I2c.ModelReg(17), 88)
Chk(e4, I2c.ModelReg(18), 89)
Chk(e4, I2c.ModelReg(19), 35)
Chk(e4, I2c.ModelReg(20), 116)
Chk(e4, I2c.ModelReg(21), 2)
Chk(e4, I2c.ModelReg(22), 1)
Chk(e4, Rtcc.RtccAlarm(2, 0, 1, 1, 1, 0, 0, 0), 5)
Chk(e4, Rtcc.RtccAlarm(0, 5, 1, 1, 1, 0, 0, 0), 5)
Chk(e4, Rtcc.RtccAlarmEnable(1, True), 0)
Chk(e4, I2c.ModelReg(7) And 48, 32)
Chk(e4, Rtcc.RtccAlarmEnable(0, True), 0)
Chk(e4, I2c.ModelReg(7) And 48, 48)
Chk(e4, Rtcc.RtccAlarmEnable(1, False), 0)
Chk(e4, I2c.ModelReg(7) And 48, 16)
' The flag: set by the chip, read, cleared (the polarity bit stays).
I2c.ModelPoke(13, 171)
Chk(e4, Rtcc.RtccAlarmFlag(0, fl), 0)
If Not fl Then
    Inc(e4)
End If
Chk(e4, Rtcc.RtccAlarmClear(0), 0)
Chk(e4, I2c.ModelReg(13), 163)
Chk(e4, Rtcc.RtccAlarmFlag(0, fl), 0)
If fl Then
    Inc(e4)
End If
Chk(e4, Rtcc.RtccAlarmPolarity(False), 0)
Chk(e4, I2c.ModelReg(13), 35)
' Alarm hour in 12-hour mode: 15 h is 3 PM.
I2c.ModelPoke(2, 99)
Chk(e4, Rtcc.RtccAlarm(0, 2, 1, 1, 1, 15, 0, 0), 0)
Chk(e4, I2c.ModelReg(12), 99)
Chk(e4, Rtcc.RtccAlarm(0, 2, 1, 1, 1, 0, 0, 0), 0)
Chk(e4, I2c.ModelReg(12), 82)
I2c.ModelPoke(2, 20)
' 5. Outputs.
I2c.ModelPoke(7, 24)
Chk(e5, Rtcc.RtccSquareWave(2), 0)
Chk(e5, I2c.ModelReg(7), 90)
Chk(e5, Rtcc.RtccSquareWave(4), 5)
Chk(e5, Rtcc.RtccPinLevel(True), 0)
Chk(e5, I2c.ModelReg(7), 138)
Chk(e5, Rtcc.RtccPinLevel(False), 0)
Chk(e5, I2c.ModelReg(7), 10)
' 6. Trim.
Chk(e6, Rtcc.RtccTrim(-5, True), 0)
Chk(e6, I2c.ModelReg(8), 5)
Chk(e6, I2c.ModelReg(7), 14)
Chk(e6, Rtcc.RtccTrim(100, False), 0)
Chk(e6, I2c.ModelReg(8), 228)
Chk(e6, I2c.ModelReg(7), 10)
Chk(e6, Rtcc.RtccTrim(0, False), 0)
Chk(e6, I2c.ModelReg(8), 0)
Chk(e6, Rtcc.RtccTrim(128, False), 5)
Chk(e6, Rtcc.RtccTrim(-128, False), 5)
' 7. SRAM.
Chk(e7, Rtcc.RtccRamWrite(5, 90), 0)
Chk(e7, I2c.ModelReg(37), 90)
Chk(e7, Rtcc.RtccRamRead(5, v), 0)
Chk(e7, v, 90)
Chk(e7, Rtcc.RtccRamWrite(63, 7), 0)
Chk(e7, I2c.ModelReg(95), 7)
Chk(e7, Rtcc.RtccRamWrite(64, 7), 5)
Chk(e7, Rtcc.RtccRamRead(64, v), 5)
' 8. EEPROM (the model is busy for 3 polls after a write) and the protected block (needs the unlock).
Chk(e8, Rtcc.RtccEeWrite(10, 165), 0)
Chk(e8, Rtcc.RtccEeRead(10, v), 0)
Chk(e8, v, 165)
Chk(e8, I2c.ModelEe(10), 165)
Chk(e8, Rtcc.RtccEeWrite(127, 1), 0)
Chk(e8, Rtcc.RtccEeWrite(128, 1), 5)
Chk(e8, Rtcc.RtccIdWrite(3, 119), 0)
Chk(e8, I2c.ModelId(3), 119)
Chk(e8, Rtcc.RtccIdRead(3, v), 0)
Chk(e8, v, 119)
Chk(e8, Rtcc.RtccIdRead(8, v), 5)
' 9. Time stamps: 23:42 on 15 July, weekday bits in the month byte are ignored.
I2c.ModelPoke(24, 66)
I2c.ModelPoke(25, 35)
I2c.ModelPoke(26, 21)
I2c.ModelPoke(27, 167)
Chk(e9, Rtcc.RtccStamp(False, mo, dy, hr, mi), 0)
Chk(e9, mo, 7)
Chk(e9, dy, 15)
Chk(e9, hr, 23)
Chk(e9, mi, 42)
I2c.ModelPoke(28, 89)
I2c.ModelPoke(29, 9)
I2c.ModelPoke(30, 1)
I2c.ModelPoke(31, 1)
Chk(e9, Rtcc.RtccStamp(True, mo, dy, hr, mi), 0)
Chk(e9, mo, 1)
Chk(e9, dy, 1)
Chk(e9, hr, 9)
Chk(e9, mi, 59)
I2c.ModelPoke(7, 0)
' 10. Battery enable and PWRFAIL: both writes keep the weekday and the oscillator bit and clear PWRFAIL.
I2c.ModelPoke(3, 61)
Chk(e10, Rtcc.RtccBattery(True), 0)
Chk(e10, I2c.ModelReg(3), 45)
I2c.ModelPoke(3, 61)
Chk(e10, Rtcc.RtccClearPowerFail(), 0)
Chk(e10, I2c.ModelReg(3), 45)
Chk(e10, Rtcc.RtccBattery(False), 0)
Chk(e10, I2c.ModelReg(3), 37)
Chk(e10, Rtcc.RtccStop(), 0)
Chk(e10, I2c.ModelReg(0) And 128, 0)
Chk(e10, I2c.ModelReg(3) And 32, 0)
Chk(e10, Rtcc.RtccStart(), 0)
Chk(e10, I2c.ModelReg(3) And 32, 32)
done = 1
