Module Rtcc
Include "i2c"
' Microchip I2C real-time clock/calendars, over the `I2c` module (the bus is set up by the caller first, at
' most 400 kHz and only above 2.5 V; 100 kHz below that [DS20002266K, FCLK], with pull-ups). The
' module owns no pins. One register map serves the whole family [DS20005010J Table 5-1, DS20002292C Table 4-1,
' DS20005009 Table 5-1, DS20002266K Table 5-1]:
'   MCP7940M   low cost: RTCC, alarms, 64 bytes SRAM. No battery input, no time stamps, no EEPROM.
'   MCP7940N   adds the VBAT input and the power-fail/power-up time stamps.
'   MCP79400/1/2  the same RTCC and SRAM, and 8 bytes of protected EEPROM (MCP79401 EUI-48, MCP79402 EUI-64).
'   MCP79410/1/2  as the MCP794xx above with 128 bytes of EEPROM and the 8 protected bytes (MCP79411 EUI-48,
'                 MCP79412 EUI-64).
' The RTCC and SRAM answer at 7-bit address 0x6F (control byte 0xDE / 0xDF) and the EEPROM at 0x57 (0xAE / 0xAF)
' [DS20002266K 5.1]. The RTCC and SRAM routines are not acknowledged and return status 3 on a part that lacks them;
' the EEPROM and ID routines wait up to 20 ms for the control byte to be acknowledged (a write cycle is 5 ms), so on a
' part without EEPROM they return 6 after that time.
' All fields of RtccAlarm must be valid (month 1..12, day 1..31) even when the mask does not compare them.
'
' Status codes (the first four are those of `I2c`): 0 ok, 1 timeout, 2 bus collision, 3 no acknowledge (device
' absent, or the block is not on this part), 4 I2c not initialised, 5 an argument out of range (nothing was
' sent), 6 a wait ended without the expected state (oscillator did not start or stop, EEPROM write still busy).
' The module is not reentrant, and uses `I2c`: do not call it from a handler and from the main program (an alarm
' interrupt handler that clears the flag must not run while the main program is inside a call).
' RtccStart, RtccStop, RtccBattery and RtccClearPowerFail read a time register and write it back, on a clock
' that is running: if the register rolls over in between (the seconds, or the weekday at midnight) the old value
' is written back, so the clock can lose a second, or keep yesterday's weekday for a day. Call them with the
' clock stopped or away from those instants. RtccSet blocks up to 2 s: clear the watchdog around it.
'
' Time is kept in 24-hour BCD in the chip; the routines here take and give plain binary numbers. Years are
' 0..99 (2000..2099, the chip compensates leap years [DS20002266K 5.3]), months 1..12, days 1..31, weekday 1..7
' (the meaning of the numbers is yours), hours 0..23. A clock that another program put in 12-hour mode is read
' correctly (RtccHour converts); RtccSet always writes 24-hour mode.
'
' Reading is a snapshot: RtccRead() copies the seven timekeeping registers in one transfer, and the chip buffers
' them at the start of the read so the copy cannot straddle a rollover [DS20002266K 5.3]; the accessors RtccYear,
' RtccMonth, RtccDay, RtccWeekday, RtccHour, RtccMinute, RtccSecond and the flags RtccOscRun, RtccPowerFail,
' RtccBatteryOn, RtccLeap decode that copy and cost no bus time.
'
' RtccSet follows the loading order of the silicon errata: the oscillator is stopped (ST and EXTOSC cleared) and
' OSCRUN waited out before the time is loaded [DS20002266K 5.3 note 2, DS80000611F issue 1 (date increments at
' noon in 12-hour mode: avoided by writing 24-hour mode)], the date is written again after month and year
' [issue 3], and the weekday is written again once the oscillator runs [issue 4: a weekday written while it is
' stopped can read back different]. It blocks until the oscillator runs (typically a few hundred ms, at most 2 s)
' and returns 6 if it does not. The 12-hour alarm and minute/hour alarm errata (issue 2: spurious minute or hour
' match with a slowing trim, TRIMVAL > 0 and SIGN = 0) are not worked around: use RtccTrim only with the second
' or date masks, or recheck the time in the alarm handler.
Dim frame(8) As Byte
Dim buf(8) As Byte

Function ToBcd(ByVal v As Byte) As Byte
    Result = ((v / 10) << 4) Or (v Mod 10)
End Function

Function FromBcd(ByVal b As Byte) As Byte
    Result = (b >> 4) * 10 + (b And 15)
End Function

' Hours 0..23 from an RTCHOUR-style byte (bit 6 = 12-hour mode, bit 5 = PM or the tens of 24-hour hours).
Function DecHour(ByVal b As Byte) As Byte
    If (b And 64) <> 0 Then
        Result = FromBcd(b And 31)
        If Result = 12 Then
            Result = 0
        End If
        If (b And 32) <> 0 Then
            Result = Result + 12
        End If
    Else
        Result = FromBcd(b And 63)
    End If
End Function

' The hour byte for hours 0..23 in the clock's mode (twelve = True: 12-hour with the PM bit).
Function EncHour(ByVal h As Byte, ByVal twelve As Boolean) As Byte
    If Not twelve Then
        Result = ToBcd(h)
    Else
        Result = 64
        If h >= 12 Then
            Result = Result Or 32
            h = h - 12
        End If
        If h = 0 Then
            h = 12
        End If
        Result = Result Or ToBcd(h)
    End If
End Function

' Start, control byte `ctl`, register/address byte `reg`. Leaves the bus started.
Function Open(ByVal ctl As Byte, ByVal reg As Byte) As Byte
    Result = I2c.I2cStart()
    If Result = 0 Then
        Result = I2c.I2cSend(ctl)
    End If
    If Result = 0 Then
        Result = I2c.I2cSend(reg)
    End If
End Function

' Reads n (1..8) bytes from `reg` of the block with control byte `ctl` into buf(0..n-1).
Function ReadBlock(ByVal ctl As Byte, ByVal reg As Byte, ByVal n As Byte) As Byte
    Dim i As Byte
    Dim s As Byte
    Result = Open(ctl, reg)
    If Result = 0 Then
        Result = I2c.I2cRestart()
    End If
    If Result = 0 Then
        Result = I2c.I2cSend(ctl Or 1)
    End If
    i = 0
    While Result = 0 And i < n
        buf(i) = I2c.I2cReceive(i < n - 1)
        Result = I2c.I2cStatus()
        Inc(i)
    Wend
    s = I2c.I2cStop()
    If Result = 0 Then
        Result = s
    End If
End Function

' Writes buf(0..n-1) (n 1..8) from `reg` of the block with control byte `ctl`.
Function WriteBlock(ByVal ctl As Byte, ByVal reg As Byte, ByVal n As Byte) As Byte
    Dim i As Byte
    Dim s As Byte
    Result = Open(ctl, reg)
    i = 0
    While Result = 0 And i < n
        Result = I2c.I2cSend(buf(i))
        Inc(i)
    Wend
    s = I2c.I2cStop()
    If Result = 0 Then
        Result = s
    End If
End Function

' Reads register `reg` of the RTCC block into buf(0).
Function RdReg(ByVal reg As Byte) As Byte
    Result = ReadBlock(222, reg, 1)
End Function

' Writes `v` to register `reg` of the RTCC block.
Function WrReg(ByVal reg As Byte, ByVal v As Byte) As Byte
    buf(0) = v
    Result = WriteBlock(222, reg, 1)
End Function

' Copies the time and date registers 0x00..0x06 for the accessors below. Returns the status.
Public Function RtccRead() As Byte
    Dim i As Byte
    Result = ReadBlock(222, 0, 7)
    If Result = 0 Then
        i = 0
        While i < 7
            frame(i) = buf(i)
            Inc(i)
        Wend
    End If
End Function

Public Function RtccSecond() As Byte
    Result = FromBcd(frame(0) And 127)
End Function

Public Function RtccMinute() As Byte
    Result = FromBcd(frame(1) And 127)
End Function

Public Function RtccHour() As Byte
    Result = DecHour(frame(2))
End Function

Public Function RtccWeekday() As Byte
    Result = frame(3) And 7
End Function

Public Function RtccDay() As Byte
    Result = FromBcd(frame(4) And 63)
End Function

Public Function RtccMonth() As Byte
    Result = FromBcd(frame(5) And 31)
End Function

Public Function RtccYear() As Byte
    Result = FromBcd(frame(6))
End Function

' True when the oscillator runs (OSCRUN) [DS20002266K Register 5-4].
Public Function RtccOscRun() As Boolean
    Result = (frame(3) And 32) <> 0
End Function

' True after the primary supply was lost and the time stamps were loaded (PWRFAIL; MCP7940N and MCP794xx).
Public Function RtccPowerFail() As Boolean
    Result = (frame(3) And 16) <> 0
End Function

' True when the VBAT input is enabled (VBATEN; MCP7940N and MCP794xx).
Public Function RtccBatteryOn() As Boolean
    Result = (frame(3) And 8) <> 0
End Function

' True when the chip says the year is a leap year (LPYR).
Public Function RtccLeap() As Boolean
    Result = (frame(5) And 32) <> 0
End Function

' Days in the month of a year 0..99 (2000..2099).
Function DaysIn(ByVal year As Byte, ByVal month As Byte) As Byte
    Result = 31
    If month = 2 Then
        Result = 28
        If (year And 3) = 0 Then
            Result = 29
        End If
    ElseIf month = 4 Or month = 6 Or month = 9 Or month = 11 Then
        Result = 30
    End If
End Function

' Sets the clock and starts it (see the header for the sequence). Returns the status; 5 when an argument is
' out of range or the day does not exist in that month (leap years 2000..2099 are 0, 4, ..., 96).
Public Function RtccSet(ByVal year As Byte, ByVal month As Byte, ByVal day As Byte, ByVal weekday As Byte, ByVal hour As Byte, ByVal minute As Byte, ByVal second As Byte) As Byte
    Dim ctl As Byte
    Dim vb As Byte
    Dim n As Byte
    Result = 5
    If year > 99 Or month < 1 Or month > 12 Or day < 1 Or weekday < 1 Or weekday > 7 Or hour > 23 Or minute > 59 Or second > 59 Then
        Exit
    End If
    If day > DaysIn(year, month) Then
        Exit
    End If
    ' VBATEN (RTCWKDAY bit 3) and the CONTROL register survive.
    Result = ReadBlock(222, 3, 5)
    If Result <> 0 Then
        Exit
    End If
    vb = buf(0) And 8
    ctl = buf(4)
    ' Stop the oscillator: EXTOSC = 0 and ST = 0, and wait for OSCRUN to clear (TOSF is at least 1 ms).
    Result = WrReg(7, ctl And 247)
    If Result = 0 Then
        Result = WrReg(0, 0)
    End If
    n = 0
    While Result = 0 And n < 100
        Result = RdReg(3)
        If Result = 0 Then
            If (buf(0) And 32) = 0 Then
                Break
            End If
            DelayMs(1)
        End If
        Inc(n)
    Wend
    If Result <> 0 Then
        Exit
    End If
    If (buf(0) And 32) <> 0 Then
        Result = 6
        Exit
    End If
    buf(0) = ToBcd(second)
    buf(1) = ToBcd(minute)
    buf(2) = ToBcd(hour)
    buf(3) = weekday Or vb
    buf(4) = ToBcd(day)
    buf(5) = ToBcd(month)
    buf(6) = ToBcd(year)
    Result = WriteBlock(222, 0, 7)
    If Result = 0 Then
        Result = WrReg(4, ToBcd(day))
    End If
    If Result = 0 Then
        If (ctl And 8) <> 0 Then
            Result = WrReg(7, ctl)
        Else
            Result = WrReg(0, ToBcd(second) Or 128)
        End If
    End If
    ' Wait for the oscillator to run (OSCRUN), then write the weekday again.
    n = 0
    While Result = 0 And n < 200
        Result = RdReg(3)
        If Result = 0 Then
            If (buf(0) And 32) <> 0 Then
                Break
            End If
            DelayMs(10)
        End If
        Inc(n)
    Wend
    If Result = 0 Then
        If (buf(0) And 32) = 0 Then
            Result = 6
        Else
            Result = WrReg(3, weekday Or vb)
        End If
    End If
End Function

' Starts the oscillator (ST = 1) without touching the time.
Public Function RtccStart() As Byte
    Result = RdReg(0)
    If Result = 0 Then
        Result = WrReg(0, buf(0) Or 128)
    End If
End Function

' Stops the oscillator (ST = 0); the time is kept but does not advance. OSCRUN clears about 1 ms later.
Public Function RtccStop() As Byte
    Result = RdReg(0)
    If Result = 0 Then
        Result = WrReg(0, buf(0) And 127)
    End If
End Function

' Writes RTCWKDAY with the weekday kept and VBATEN = vb (8, 0, or 255 = as it is). Writing RTCWKDAY always
' clears PWRFAIL and so resets the power-fail time stamps [DS20002266K Register 5-4 note 2].
Function WkWrite(ByVal vb As Byte) As Byte
    Result = RdReg(3)
    If Result = 0 Then
        If vb = 255 Then
            vb = buf(0) And 8
        End If
        Result = WrReg(3, (buf(0) And 7) Or vb)
    End If
End Function

' Enables or disables the VBAT input (MCP7940N, MCP794xx). Also clears PWRFAIL.
Public Function RtccBattery(ByVal en As Boolean) As Byte
    If en Then
        Result = WkWrite(8)
    Else
        Result = WkWrite(0)
    End If
End Function

' Clears PWRFAIL (and so the time stamps) so that the next power loss is logged.
Public Function RtccClearPowerFail() As Byte
    Result = WkWrite(255)
End Function

' Reads the power-down (up = False) or power-up (up = True) time stamp [DS20002266K 5.7.1] as month, day, hour
' (0..23) and minute. MCP7940N and MCP794xx only.
Public Function RtccStamp(ByVal up As Boolean, ByRef month As Byte, ByRef day As Byte, ByRef hour As Byte, ByRef minute As Byte) As Byte
    If up Then
        Result = ReadBlock(222, 28, 4)
    Else
        Result = ReadBlock(222, 24, 4)
    End If
    If Result = 0 Then
        minute = FromBcd(buf(0) And 127)
        hour = DecHour(buf(1))
        day = FromBcd(buf(2) And 63)
        month = FromBcd(buf(3) And 31)
    End If
End Function

' Programs alarm n (0 or 1) [DS20002266K 5.4]. `mask` selects what must match: 0 seconds, 1 minutes, 2 hours,
' 3 weekday, 4 date, 7 seconds + minutes + hours + weekday + date + month (5 and 6 are reserved). The values
' not used by the mask are still stored. The alarm flag is cleared by the write; the alarm is armed with
' RtccAlarmEnable (disable it first when reprogramming a running alarm). ALMPOL is kept (see RtccAlarmPolarity).
Public Function RtccAlarm(ByVal n As Byte, ByVal mask As Byte, ByVal month As Byte, ByVal day As Byte, ByVal weekday As Byte, ByVal hour As Byte, ByVal minute As Byte, ByVal second As Byte) As Byte
    Dim pol As Byte
    Dim base As Byte
    Result = 5
    If n > 1 Or mask = 5 Or mask = 6 Or mask > 7 Or month < 1 Or month > 12 Or day < 1 Or day > 31 Or weekday < 1 Or weekday > 7 Or hour > 23 Or minute > 59 Or second > 59 Then
        Exit
    End If
    pol = 0
    If n = 0 Then
        Result = RdReg(13)
        If Result <> 0 Then
            Exit
        End If
        pol = buf(0) And 128
    End If
    Result = RdReg(2)
    If Result <> 0 Then
        Exit
    End If
    buf(2) = EncHour(hour, (buf(0) And 64) <> 0)
    buf(0) = ToBcd(second)
    buf(1) = ToBcd(minute)
    buf(3) = pol Or (mask << 4) Or weekday
    buf(4) = ToBcd(day)
    buf(5) = ToBcd(month)
    base = 10 + 7 * n
    Result = WriteBlock(222, base, 6)
End Function

' Arms (arm = True) or disarms alarm n (ALMxEN). The MFP pin follows the alarm flags when an alarm is armed
' and the square wave is off [DS20002266K Table 5-7].
Public Function RtccAlarmEnable(ByVal n As Byte, ByVal arm As Boolean) As Byte
    Dim m As Byte
    Result = 5
    If n > 1 Then
        Exit
    End If
    m = 16 << n
    Result = RdReg(7)
    If Result = 0 Then
        If arm Then
            Result = WrReg(7, buf(0) Or m)
        Else
            Result = WrReg(7, buf(0) And (m Xor 255))
        End If
    End If
End Function

' flag = True when alarm n has matched (ALMxIF). Clear it with RtccAlarmClear. The flag is set again at once if
' the match condition still holds.
Public Function RtccAlarmFlag(ByVal n As Byte, ByRef flag As Boolean) As Byte
    Result = 5
    If n > 1 Then
        Exit
    End If
    Result = RdReg(13 + 7 * n)
    If Result = 0 Then
        flag = (buf(0) And 8) <> 0
    End If
End Function

' Clears the alarm flag of alarm n by rewriting its weekday register (any write clears ALMxIF) [Register 5-11].
Public Function RtccAlarmClear(ByVal n As Byte) As Byte
    Dim r As Byte
    Result = 5
    If n > 1 Then
        Exit
    End If
    r = 13 + 7 * n
    Result = RdReg(r)
    If Result = 0 Then
        Result = WrReg(r, buf(0))
    End If
End Function

' Sets the polarity of the alarm output on MFP: activeHigh = True gives a high level when asserted (ALMPOL = 1).
' Both alarms share it; the write also clears the flag of alarm 0.
Public Function RtccAlarmPolarity(ByVal activeHigh As Boolean) As Byte
    Result = RdReg(13)
    If Result = 0 Then
        If activeHigh Then
            Result = WrReg(13, buf(0) Or 128)
        Else
            Result = WrReg(13, buf(0) And 127)
        End If
    End If
End Function

' Square wave on MFP: sel 0 = 1 Hz, 1 = 4.096 kHz, 2 = 8.192 kHz, 3 = 32.768 kHz (SQWEN = 1). It takes
' precedence over the alarm output. All but 32.768 kHz are shortened by digital trimming [Register 5-14 note 1].
Public Function RtccSquareWave(ByVal sel As Byte) As Byte
    Result = 5
    If sel > 3 Then
        Exit
    End If
    Result = RdReg(7)
    If Result = 0 Then
        Result = WrReg(7, (buf(0) And 252) Or 64 Or sel)
    End If
End Function

' MFP as a general purpose output (SQWEN = 0, both alarms disarmed): level True = high. The pin is open drain,
' so it needs a pull-up to VCC [DS20002266K 5.5].
Public Function RtccPinLevel(ByVal level As Boolean) As Byte
    Result = RdReg(7)
    If Result = 0 Then
        If level Then
            Result = WrReg(7, (buf(0) And 15) Or 128)
        Else
            Result = WrReg(7, buf(0) And 15)
        End If
    End If
End Function

' Digital trim [DS20002266K 5.6, Register 5-15]: steps -127..127. Positive steps add 2 clock cycles per step
' (a slow clock is sped up: SIGN = 1), negative steps remove them; 0 turns trimming off. With coarse = False one
' step is about 1.017 ppm (once a minute); with coarse = True (CRSTRIM = 1) the correction is applied 128 times
' a second, and MFP can give the trimmed 64 Hz clock. Sets the CRSTRIM bit to `coarse`.
Public Function RtccTrim(ByVal steps As Integer, ByVal coarse As Boolean) As Byte
    Dim v As Byte
    Result = 5
    If steps < -127 Or steps > 127 Then
        Exit
    End If
    If steps < 0 Then
        v = Byte(-steps)
    Else
        v = Byte(steps)
        If steps > 0 Then
            v = v Or 128
        End If
    End If
    Result = WrReg(8, v)
    If Result = 0 Then
        Result = RdReg(7)
    End If
    If Result = 0 Then
        If coarse Then
            Result = WrReg(7, buf(0) Or 4)
        Else
            Result = WrReg(7, buf(0) And 251)
        End If
    End If
End Function

' SRAM, 64 bytes at RTCC addresses 0x20..0x5F; not cleared by a reset; kept on VBAT. addr 0..63.
Public Function RtccRamRead(ByVal addr As Byte, ByRef value As Byte) As Byte
    Result = 5
    If addr > 63 Then
        Exit
    End If
    Result = RdReg(32 + addr)
    If Result = 0 Then
        value = buf(0)
    End If
End Function

Public Function RtccRamWrite(ByVal addr As Byte, ByVal value As Byte) As Byte
    Result = 5
    If addr > 63 Then
        Exit
    End If
    Result = WrReg(32 + addr, value)
End Function

' Waits for the end of a running EEPROM write cycle (TWC is 5 ms): the EEPROM does not acknowledge its control
' byte until then [DS20002266K 6.2.2]. 6 if it is still busy after 20 ms.
Function EeReady() As Byte
    Dim n As Byte
    Dim s As Byte
    Result = 6
    n = 0
    While n < 20
        s = I2c.I2cStart()
        If s = 0 Then
            s = I2c.I2cSend(174)
        End If
        I2c.I2cStop()
        If s = 0 Then
            Result = 0
            Exit
        End If
        If s <> 3 Then
            Result = s
            Exit
        End If
        DelayMs(1)
        Inc(n)
    Wend
End Function

' EEPROM, 128 bytes (MCP79410/1/2 only), addr 0..127. A write starts a 5 ms cycle; the next EEPROM call waits
' for it. The RTCC and SRAM can be used meanwhile. Writes to the area protected by RtccEeProtect are not
' acknowledged (status 3).
Public Function RtccEeRead(ByVal addr As Byte, ByRef value As Byte) As Byte
    Result = 5
    If addr > 127 Then
        Exit
    End If
    Result = EeReady()
    If Result = 0 Then
        Result = ReadBlock(174, addr, 1)
    End If
    If Result = 0 Then
        value = buf(0)
    End If
End Function

Public Function RtccEeWrite(ByVal addr As Byte, ByVal value As Byte) As Byte
    Result = 5
    If addr > 127 Then
        Exit
    End If
    Result = EeReady()
    If Result = 0 Then
        buf(0) = value
        Result = WriteBlock(174, addr, 1)
    End If
End Function

' Write protection of the EEPROM array (STATUS register BP<1:0>, nonvolatile) [Table 6-1]: 0 none, 1 upper
' quarter (0x60..0x7F), 2 upper half (0x40..0x7F), 3 all.
Public Function RtccEeProtect(ByVal level As Byte) As Byte
    Result = 5
    If level > 3 Then
        Exit
    End If
    Result = EeReady()
    If Result = 0 Then
        buf(0) = level << 2
        Result = WriteBlock(174, 255, 1)
    End If
End Function

' Protected EEPROM, 8 bytes at 0xF0..0xF7 (MCP79400/1/2 and MCP79410/1/2): i = 0..7. On the EUI parts it holds
' the node address, preprogrammed [DS20002266K 6.3]. Reading needs no unlock.
Public Function RtccIdRead(ByVal i As Byte, ByRef value As Byte) As Byte
    Result = 5
    If i > 7 Then
        Exit
    End If
    Result = EeReady()
    If Result = 0 Then
        Result = ReadBlock(174, 240 + i, 1)
    End If
    If Result = 0 Then
        value = buf(0)
    End If
End Function

' Writes one byte of the protected EEPROM after the unlock sequence: 0x55 then 0xAA to EEUNLOCK (RTCC address
' 0x09), each its own transfer, then the data [DS20002266K 6.3.1]. The block locks again after each write.
Public Function RtccIdWrite(ByVal i As Byte, ByVal value As Byte) As Byte
    Result = 5
    If i > 7 Then
        Exit
    End If
    Result = EeReady()
    If Result = 0 Then
        Result = WrReg(9, 85)
    End If
    If Result = 0 Then
        Result = WrReg(9, 170)
    End If
    If Result = 0 Then
        buf(0) = value
        Result = WriteBlock(174, 240 + i, 1)
    End If
End Function
