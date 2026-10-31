' expect: LRS_E1=0 LRS_E2=0 LRS_E3=0 LRS_E4=0 LRS_E5=0 LRS_E6=0 LRS_E7=0 LRS_E8=0 LRS_E9=0 LRS_E10=0 LRS_E11=0 LRS_DONE=1
' Runs the `Rtccspi` routines against a model of the MCP795xx (the `spi.bas` and `pinio.bas` next to this file
' replace the bus drivers).
Program Lrs
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "spi"
Include "rtccspi"
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
Dim e11 As Byte
Dim done As Byte
Dim r As Byte
Dim v As Byte
Dim fl As Boolean
Dim fh As Boolean
Dim mo As Byte
Dim dy As Byte
Dim hr As Byte
Dim mi As Byte

Sub Chk(ByRef e As Byte, ByVal got As Byte, ByVal want As Byte)
    If got <> want Then
        Inc(e)
    End If
End Sub

' Before the chip select is given, nothing is sent.
Chk(e1, Rtccspi.RtccspiRead(), 4)
Chk(e1, Rtccspi.RtccspiInit(24), 0)
Chk(e1, Rtccspi.RtccspiInit(16), 1)
r = Spi.SpiInit(1000000, 0, 9, 10, 11)
' 1. Set: the TRIMSIGN bit of RTCHOUR and VBATEN survive, hundredths are cleared.
Spi.ModelPoke(3, 128)
Spi.ModelPoke(4, 8)
Chk(e1, Rtccspi.RtccspiSet(24, 10, 31, 5, 14, 30, 15), 0)
Chk(e1, Spi.ModelReg(0), 0)
Chk(e1, Spi.ModelReg(1), 149)
Chk(e1, Spi.ModelReg(2), 48)
Chk(e1, Spi.ModelReg(3), 148)
Chk(e1, Spi.ModelReg(4), 45)
Chk(e1, Spi.ModelReg(5), 49)
Chk(e1, Spi.ModelReg(6), 16)
Chk(e1, Spi.ModelReg(7), 36)
' 2. Argument checks.
Chk(e2, Rtccspi.RtccspiSet(24, 2, 31, 1, 0, 0, 0), 5)
Chk(e2, Rtccspi.RtccspiSet(25, 2, 29, 1, 0, 0, 0), 5)
Chk(e2, Rtccspi.RtccspiSet(25, 4, 30, 1, 24, 0, 0), 5)
Chk(e2, Rtccspi.RtccspiSet(24, 2, 29, 7, 23, 59, 58), 0)
Chk(e2, Spi.ModelReg(5), 41)
Chk(e2, Spi.ModelReg(4) And 7, 7)
' 3. Read back and decode (hundredths at 0, TRIMSIGN ignored in the hour).
Chk(e3, Rtccspi.RtccspiSet(24, 10, 31, 5, 14, 30, 15), 0)
Spi.ModelPoke(0, 66)
Chk(e3, Rtccspi.RtccspiRead(), 0)
Chk(e3, Rtccspi.RtccspiHundredths(), 42)
Chk(e3, Rtccspi.RtccspiYear(), 24)
Chk(e3, Rtccspi.RtccspiMonth(), 10)
Chk(e3, Rtccspi.RtccspiDay(), 31)
Chk(e3, Rtccspi.RtccspiWeekday(), 5)
Chk(e3, Rtccspi.RtccspiHour(), 14)
Chk(e3, Rtccspi.RtccspiMinute(), 30)
Chk(e3, Rtccspi.RtccspiSecond(), 15)
If Not Rtccspi.RtccspiOscRun() Then
    Inc(e3)
End If
Spi.ModelPoke(3, 225)
Chk(e3, Rtccspi.RtccspiRead(), 0)
Chk(e3, Rtccspi.RtccspiHour(), 13)
Spi.ModelPoke(3, 20)
' 4. Alarms: alarm 0 at 0x0C, alarm 1 (with hundredths) at 0x12; ALMxPIN kept.
Spi.ModelPoke(15, 128)
Chk(e4, Rtccspi.RtccspiAlarm(0, 2, 12, 25, 3, 7, 45, 10, 99), 0)
Chk(e4, Spi.ModelReg(12), 16)
Chk(e4, Spi.ModelReg(13), 69)
Chk(e4, Spi.ModelReg(14), 7)
Chk(e4, Spi.ModelReg(15), 163)
Chk(e4, Spi.ModelReg(16), 37)
Chk(e4, Spi.ModelReg(17), 18)
Spi.ModelPoke(22, 128)
Chk(e4, Rtccspi.RtccspiAlarm(1, 5, 1, 2, 4, 23, 59, 58, 42), 0)
Chk(e4, Spi.ModelReg(18), 66)
Chk(e4, Spi.ModelReg(19), 88)
Chk(e4, Spi.ModelReg(20), 89)
Chk(e4, Spi.ModelReg(21), 35)
Chk(e4, Spi.ModelReg(22), 212)
Chk(e4, Spi.ModelReg(23), 2)
Chk(e4, Rtccspi.RtccspiAlarm(0, 5, 1, 1, 1, 0, 0, 0, 0), 5)
Chk(e4, Rtccspi.RtccspiAlarm(2, 0, 1, 1, 1, 0, 0, 0, 0), 5)
Chk(e4, Rtccspi.RtccspiAlarm(0, 6, 1, 1, 1, 0, 0, 0, 0), 5)
Chk(e4, Rtccspi.RtccspiAlarmEnable(1, True), 0)
Chk(e4, Spi.ModelReg(8) And 48, 32)
Chk(e4, Rtccspi.RtccspiAlarmEnable(0, True), 0)
Chk(e4, Spi.ModelReg(8) And 48, 48)
Chk(e4, Rtccspi.RtccspiAlarmEnable(1, False), 0)
Chk(e4, Spi.ModelReg(8) And 48, 16)
Spi.ModelPoke(15, 171)
Chk(e4, Rtccspi.RtccspiAlarmFlag(0, fl), 0)
If Not fl Then
    Inc(e4)
End If
Chk(e4, Rtccspi.RtccspiAlarmClear(0), 0)
Chk(e4, Spi.ModelReg(15), 163)
Chk(e4, Rtccspi.RtccspiAlarmFlag(0, fl), 0)
If fl Then
    Inc(e4)
End If
Chk(e4, Rtccspi.RtccspiAlarmPin(0, False), 0)
Chk(e4, Spi.ModelReg(15), 35)
Chk(e4, Rtccspi.RtccspiAlarmPin(1, True), 0)
Chk(e4, Spi.ModelReg(22) And 128, 128)
' Alarm hour in 12-hour mode: 15 h is 3 PM (RTCHOUR has TRIMSIGN too, which the alarm hour does not).
Spi.ModelPoke(3, 227)
Chk(e4, Rtccspi.RtccspiAlarm(0, 2, 1, 1, 1, 15, 0, 0, 0), 0)
Chk(e4, Spi.ModelReg(14), 99)
Spi.ModelPoke(3, 20)
' 5. Square wave (bit 7 of CONTROL is left alone).
Spi.ModelPoke(8, 152)
Chk(e5, Rtccspi.RtccspiSquareWave(1), 0)
Chk(e5, Spi.ModelReg(8), 217)
Chk(e5, Rtccspi.RtccspiSquareWave(4), 5)
Chk(e5, Rtccspi.RtccspiSquareWaveOff(), 0)
Chk(e5, Spi.ModelReg(8), 153)
' 6. Trim: the sign is bit 7 of RTCHOUR and the hour survives; CRSTRIM is bit 2 of CONTROL.
Spi.ModelPoke(8, 0)
Chk(e6, Rtccspi.RtccspiTrim(-5, True), 0)
Chk(e6, Spi.ModelReg(9), 5)
Chk(e6, Spi.ModelReg(3), 20)
Chk(e6, Spi.ModelReg(8), 4)
Chk(e6, Rtccspi.RtccspiTrim(200, False), 0)
Chk(e6, Spi.ModelReg(9), 200)
Chk(e6, Spi.ModelReg(3), 148)
Chk(e6, Spi.ModelReg(8), 0)
Chk(e6, Rtccspi.RtccspiTrim(0, False), 0)
Chk(e6, Spi.ModelReg(3), 20)
Chk(e6, Rtccspi.RtccspiTrim(256, False), 5)
Chk(e6, Rtccspi.RtccspiTrim(-256, False), 5)
' 7. SRAM, and CLRRAM.
Chk(e7, Rtccspi.RtccspiRamWrite(5, 90), 0)
Chk(e7, Spi.ModelReg(37), 90)
Chk(e7, Rtccspi.RtccspiRamRead(5, v), 0)
Chk(e7, v, 90)
Chk(e7, Rtccspi.RtccspiRamWrite(64, 7), 5)
Chk(e7, Rtccspi.RtccspiRamRead(64, v), 5)
Chk(e7, Rtccspi.RtccspiRamClear(), 0)
Chk(e7, Spi.ModelReg(37), 0)
Chk(e7, Spi.ModelReg(5), 49)
' 8. EEPROM: needs EEWREN (the driver sends it) and waits out WIP; the upper 128 bytes of a MCP7952X are real.
Chk(e8, Rtccspi.RtccspiEeWrite(10, 165), 0)
Chk(e8, Rtccspi.RtccspiEeRead(10, v), 0)
Chk(e8, v, 165)
Chk(e8, Spi.ModelEe(10), 165)
Chk(e8, Rtccspi.RtccspiEeWrite(255, 7), 0)
Chk(e8, Spi.ModelEe(255), 7)
Chk(e8, Rtccspi.RtccspiEeProtect(2), 0)
Chk(e8, Spi.ModelBp(), 2)
Chk(e8, Rtccspi.RtccspiEeProtect(4), 5)
' 9. Protected EEPROM: 16 bytes, written after EEWREN and the two UNLOCKs.
Chk(e9, Rtccspi.RtccspiIdWrite(12, 119), 0)
Chk(e9, Spi.ModelId(12), 119)
Chk(e9, Rtccspi.RtccspiIdRead(12, v), 0)
Chk(e9, v, 119)
Chk(e9, Rtccspi.RtccspiIdWrite(16, 1), 5)
Chk(e9, Rtccspi.RtccspiIdRead(16, v), 5)
' 10. Time stamps, battery, PWRFAIL, stop and start.
Spi.ModelPoke(24, 66)
Spi.ModelPoke(25, 35)
Spi.ModelPoke(26, 21)
Spi.ModelPoke(27, 167)
Chk(e10, Rtccspi.RtccspiStamp(False, mo, dy, hr, mi), 0)
Chk(e10, mo, 7)
Chk(e10, dy, 15)
Chk(e10, hr, 23)
Chk(e10, mi, 42)
Spi.ModelPoke(4, 61)
Chk(e10, Rtccspi.RtccspiBattery(True), 0)
Chk(e10, Spi.ModelReg(4), 45)
Spi.ModelPoke(4, 61)
Chk(e10, Rtccspi.RtccspiClearPowerFail(), 0)
Chk(e10, Spi.ModelReg(4), 45)
Chk(e10, Rtccspi.RtccspiBattery(False), 0)
Chk(e10, Spi.ModelReg(4), 37)
Spi.ModelPoke(8, 0)
Chk(e10, Rtccspi.RtccspiStop(), 0)
Chk(e10, Spi.ModelReg(1) And 128, 0)
Chk(e10, Spi.ModelReg(4) And 32, 0)
Chk(e10, Rtccspi.RtccspiStart(), 0)
Chk(e10, Spi.ModelReg(4) And 32, 32)
' 11. Watchdog and event detection (W parts), raw register access.
Chk(e11, Rtccspi.RtccspiWdt(True, 4, False, True), 0)
Chk(e11, Spi.ModelReg(10), 148)
Chk(e11, Rtccspi.RtccspiWdt(False, 8, False, False), 5)
Chk(e11, Rtccspi.RtccspiWdtClear(), 0)
Chk(e11, Spi.ModelWdtClears(), 1)
Spi.ModelPoke(10, 212)
Chk(e11, Rtccspi.RtccspiWdtFlag(fl), 0)
If Not fl Then
    Inc(e11)
End If
Chk(e11, Rtccspi.RtccspiWdtFlagClear(), 0)
Chk(e11, Spi.ModelReg(10), 148)
Chk(e11, Rtccspi.RtccspiEvents(True, False, 2), 0)
Chk(e11, Spi.ModelReg(11), 50)
Chk(e11, Rtccspi.RtccspiEvents(False, True, 255), 0)
Chk(e11, Spi.ModelReg(11), 4)
Chk(e11, Rtccspi.RtccspiEvents(False, False, 4), 5)
Spi.ModelPoke(11, 242)
Chk(e11, Rtccspi.RtccspiEventFlags(fl, fh, False), 0)
If Not fl Or Not fh Then
    Inc(e11)
End If
Chk(e11, Spi.ModelReg(11), 242)
Chk(e11, Rtccspi.RtccspiEventFlags(fl, fh, True), 0)
Chk(e11, Spi.ModelReg(11), 50)
Chk(e11, Rtccspi.RtccspiReadReg(11, v), 0)
Chk(e11, v, 50)
Chk(e11, Rtccspi.RtccspiReadReg(96, v), 5)
Chk(e11, Rtccspi.RtccspiWriteReg(96, 1), 5)
done = 1
