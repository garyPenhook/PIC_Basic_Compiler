Module Rtccspi
Include "spi"
Include "pinio"
' Microchip SPI real-time clock/calendars, over the `Spi` module: MCP79510/11/12 and MCP79520/21/22
' (MCP7951X/MCP7952X, DS20002300E) and MCP795W10/11/12 and MCP795W20/21/22 (MCP795W1X/MCP795W2X, DS20002280F).
' Section and table numbers below are from DS20002300E unless a DS number is given. The parts differ in the
' EEPROM (the 1 at the end of the 5 digits: 1 Kbit = 128 bytes, 2: 2 Kbit = 256 bytes), in the node address in
' the protected EEPROM (X1: EUI-48, X2: EUI-64, X0: blank) and the W parts add a watchdog and event detection.
'
' WARNING: the parts run from 1.8 V to 3.6 V (DS20002300E, DS20002280F first page), so a 5 V PIC cannot talk
' to them directly. SCK is at most 5 MHz at 2.5 V and above and 3 MHz below [FCLK]; data are latched
' on the rising edge of SCK [4.0], so set `Spi` up in mode 0 (SCK idles low): Spi.SpiInit(hz, 0, sck, sdo, sdi).
' The chip select is a pin of this module's choosing (`Pinio` numbering: RA0 = 0, RB0 = 8, RC0 = 16), given to
' RtccspiInit, which makes it an output and drives it high. SPI is shared: other devices on the bus need their
' own selects, and nothing else may use the bus during a call.
'
' Status codes: 0 ok, 1 timeout of the SPI hardware, 4 `Spi` or the chip select not initialised, 5 an argument
' out of range (nothing was sent), 6 a wait ended without the expected state (oscillator did not start or stop,
' EEPROM write still busy). Routines for a block the part lacks (WDT on a MCP7951X/2X) write registers that do
' not exist, which the chip ignores; they read back as they were reset.
' The module is not reentrant (do not use it from a handler and from the main program), and RtccspiStart,
' RtccspiStop, RtccspiBattery, RtccspiClearPowerFail and RtccspiTrim read a time register and write it back on a
' running clock, so a rollover in between writes the old value back (see the I2C module `Rtcc`). RtccspiSet blocks
' up to 2 s.
'
' The register map differs from the I2C parts [Table 5-1]: hundredths of a second sit at address 0, the time
' registers follow at 1..7, CONTROL is 8 and OSCTRIM 9. The routines take plain binary numbers (years 0..99 for
' 2000..2099, months 1..12, days 1..31, weekday 1..7, hours 0..23); RtccspiSet always writes 24-hour mode, and a
' clock left in 12-hour mode is read correctly.
'
' Reading is a snapshot: RtccspiRead() copies registers 0x00..0x07 in one transfer; the accessors decode that copy.
' Silicon errata (DS80000680E for MCP795XX, DS80000542 for MCP795WXX): date increments at noon in 12-hour mode
' [issue 1: 24-hour mode only is used], the date is lost after a month or year write [issue 2: date written
' again], the weekday resets to 1 if it is written as 7 while the oscillator is stopped [issue 3: the weekday
' is written again once it runs], the hundredths of a second are not in step with the seconds until the first
' minute rollover after setting [issue 4] and can read the same twice [issue 5: read twice, or let 120 us pass],
' and on the MCP795XX the 8 kHz and 32 kHz outputs of a crystal part disturb timekeeping [issue 6]: do not use
' RtccspiSquareWave 2 and 3 with a crystal. On the MCP795WXX supplies above 3.6 V affect the time and outputs
' [issues 1 to 5]; stay at or below 3.6 V.
Dim frame(8) As Byte
Dim buf(8) As Byte
Dim csPin As Byte
Dim ready As Boolean

Function ToBcd(ByVal v As Byte) As Byte
    Result = ((v / 10) << 4) Or (v Mod 10)
End Function

Function FromBcd(ByVal b As Byte) As Byte
    Result = (b >> 4) * 10 + (b And 15)
End Function

' Hours 0..23 from an RTCHOUR-style byte (bit 7 TRIMSIGN ignored, bit 6 = 12-hour mode, bit 5 = PM or tens).
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

' The hour byte (without TRIMSIGN) for hours 0..23 in the clock's mode.
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

' Makes `cs` the chip select (an output, high). Returns 1 (like SpiInit, not a status code), or 0 for a pin the part does not have.
Public Function RtccspiInit(ByVal cs As Byte) As Byte
    Result = 0
    If Not Pinio.PinOk(cs) Then
        Exit
    End If
    csPin = cs
    Pinio.PinSet(cs, True)
    Pinio.PinOutput(cs)
    ready = True
    Result = 1
End Function

' One SPI instruction of 1 byte, with nothing after it (chip select low, byte, high).
Function Cmd1(ByVal c As Byte) As Byte
    Result = 4
    If Not ready Then
        Exit
    End If
    Pinio.PinSet(csPin, False)
    Spi.SpiWrite(c)
    Result = Spi.SpiStatus()
    Pinio.PinSet(csPin, True)
End Function

' Instruction `c`, then one data byte.
Function Cmd2(ByVal c As Byte, ByVal d As Byte) As Byte
    Result = 4
    If Not ready Then
        Exit
    End If
    Pinio.PinSet(csPin, False)
    Spi.SpiWrite(c)
    Spi.SpiWrite(d)
    Result = Spi.SpiStatus()
    Pinio.PinSet(csPin, True)
End Function

' Reads n (1..8) bytes with instruction `c` (READ 0x13, EEREAD 0x03, IDREAD 0x33) from address `a` into buf.
Function ReadBlock(ByVal c As Byte, ByVal a As Byte, ByVal n As Byte) As Byte
    Dim i As Byte
    Result = 4
    If Not ready Then
        Exit
    End If
    Pinio.PinSet(csPin, False)
    Spi.SpiWrite(c)
    Spi.SpiWrite(a)
    i = 0
    While i < n
        buf(i) = Spi.SpiRead()
        Inc(i)
    Wend
    Result = Spi.SpiStatus()
    Pinio.PinSet(csPin, True)
End Function

' Writes buf(0..n-1) (n 1..8) with instruction `c` (WRITE 0x12, EEWRITE 0x02, IDWRITE 0x32) to address `a`.
' The page-write rules of the EEPROM are the caller's (n = 1 for EEPROM).
Function WriteBlock(ByVal c As Byte, ByVal a As Byte, ByVal n As Byte) As Byte
    Dim i As Byte
    Result = 4
    If Not ready Then
        Exit
    End If
    Pinio.PinSet(csPin, False)
    Spi.SpiWrite(c)
    Spi.SpiWrite(a)
    i = 0
    While i < n
        Spi.SpiWrite(buf(i))
        Inc(i)
    Wend
    Result = Spi.SpiStatus()
    Pinio.PinSet(csPin, True)
End Function

Function RdReg(ByVal reg As Byte) As Byte
    Result = ReadBlock(19, reg, 1)
End Function

Function WrReg(ByVal reg As Byte, ByVal v As Byte) As Byte
    buf(0) = v
    Result = WriteBlock(18, reg, 1)
End Function

' Reads any register of the RTCC/SRAM space (0x00..0x5F) into `value`; for registers this module has no routine
' for (WDTCON 0x0A and EVDTCON 0x0B on the W parts, for instance). Returns the status.
Public Function RtccspiReadReg(ByVal reg As Byte, ByRef value As Byte) As Byte
    Result = 5
    If reg > 95 Then
        Exit
    End If
    Result = RdReg(reg)
    If Result = 0 Then
        value = buf(0)
    End If
End Function

' Writes any register of the RTCC/SRAM space (0x00..0x5F). The caller is responsible for the contents.
Public Function RtccspiWriteReg(ByVal reg As Byte, ByVal value As Byte) As Byte
    Result = 5
    If reg > 95 Then
        Exit
    End If
    Result = WrReg(reg, value)
End Function

' Copies the registers 0x00..0x07 for the accessors below. Returns the status.
Public Function RtccspiRead() As Byte
    Dim i As Byte
    Result = ReadBlock(19, 0, 8)
    If Result = 0 Then
        i = 0
        While i < 8
            frame(i) = buf(i)
            Inc(i)
        Wend
    End If
End Function

' Hundredths of a second, 0..99 (see the header for errata 4 and 5).
Public Function RtccspiHundredths() As Byte
    Result = FromBcd(frame(0))
End Function

Public Function RtccspiSecond() As Byte
    Result = FromBcd(frame(1) And 127)
End Function

Public Function RtccspiMinute() As Byte
    Result = FromBcd(frame(2) And 127)
End Function

Public Function RtccspiHour() As Byte
    Result = DecHour(frame(3))
End Function

Public Function RtccspiWeekday() As Byte
    Result = frame(4) And 7
End Function

Public Function RtccspiDay() As Byte
    Result = FromBcd(frame(5) And 63)
End Function

Public Function RtccspiMonth() As Byte
    Result = FromBcd(frame(6) And 31)
End Function

Public Function RtccspiYear() As Byte
    Result = FromBcd(frame(7))
End Function

' True when the oscillator runs (OSCRUN).
Public Function RtccspiOscRun() As Boolean
    Result = (frame(4) And 32) <> 0
End Function

' True after the primary supply was lost and the time stamps were loaded (PWRFAIL).
Public Function RtccspiPowerFail() As Boolean
    Result = (frame(4) And 16) <> 0
End Function

' True when the VBAT input is enabled (VBATEN).
Public Function RtccspiBatteryOn() As Boolean
    Result = (frame(4) And 8) <> 0
End Function

' True when the chip says the year is a leap year (LPYR).
Public Function RtccspiLeap() As Boolean
    Result = (frame(6) And 32) <> 0
End Function

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

' Sets the clock (hundredths 0) and starts it; the sequence is that of `Rtcc.RtccSet` with the SPI register
' map, and blocks until the oscillator runs (at most 2 s; 6 if it does not). VBATEN and the trim sign survive.
' Returns 5 for an argument out of range or a day the month does not have.
Public Function RtccspiSet(ByVal year As Byte, ByVal month As Byte, ByVal day As Byte, ByVal weekday As Byte, ByVal hour As Byte, ByVal minute As Byte, ByVal second As Byte) As Byte
    Dim ctl As Byte
    Dim vb As Byte
    Dim ts As Byte
    Dim n As Byte
    Result = 5
    If year > 99 Or month < 1 Or month > 12 Or day < 1 Or weekday < 1 Or weekday > 7 Or hour > 23 Or minute > 59 Or second > 59 Then
        Exit
    End If
    If day > DaysIn(year, month) Then
        Exit
    End If
    ' buf(0) = RTCHOUR (TRIMSIGN), buf(1) = RTCWKDAY (VBATEN), buf(5) = CONTROL.
    Result = ReadBlock(19, 3, 6)
    If Result <> 0 Then
        Exit
    End If
    ts = buf(0) And 128
    vb = buf(1) And 8
    ctl = buf(5)
    Result = WrReg(8, ctl And 247)
    If Result = 0 Then
        Result = WrReg(1, 0)
    End If
    n = 0
    While Result = 0 And n < 100
        Result = RdReg(4)
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
    buf(0) = 0
    buf(1) = ToBcd(second)
    buf(2) = ToBcd(minute)
    buf(3) = ToBcd(hour) Or ts
    buf(4) = weekday Or vb
    buf(5) = ToBcd(day)
    buf(6) = ToBcd(month)
    buf(7) = ToBcd(year)
    Result = WriteBlock(18, 0, 8)
    If Result = 0 Then
        Result = WrReg(5, ToBcd(day))
    End If
    If Result = 0 Then
        If (ctl And 8) <> 0 Then
            Result = WrReg(8, ctl)
        Else
            Result = WrReg(1, ToBcd(second) Or 128)
        End If
    End If
    n = 0
    While Result = 0 And n < 200
        Result = RdReg(4)
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
            Result = WrReg(4, weekday Or vb)
        End If
    End If
End Function

' Starts the oscillator (ST = 1) without touching the time.
Public Function RtccspiStart() As Byte
    Result = RdReg(1)
    If Result = 0 Then
        Result = WrReg(1, buf(0) Or 128)
    End If
End Function

' Stops the oscillator (ST = 0).
Public Function RtccspiStop() As Byte
    Result = RdReg(1)
    If Result = 0 Then
        Result = WrReg(1, buf(0) And 127)
    End If
End Function

' Writes RTCWKDAY with the weekday kept and VBATEN = vb (8, 0, or 255 = as it is); also clears PWRFAIL.
Function WkWrite(ByVal vb As Byte) As Byte
    Result = RdReg(4)
    If Result = 0 Then
        If vb = 255 Then
            vb = buf(0) And 8
        End If
        Result = WrReg(4, (buf(0) And 7) Or vb)
    End If
End Function

' Enables or disables the VBAT input. Also clears PWRFAIL.
Public Function RtccspiBattery(ByVal en As Boolean) As Byte
    If en Then
        Result = WkWrite(8)
    Else
        Result = WkWrite(0)
    End If
End Function

' Clears PWRFAIL (and so the time stamps) so that the next power loss is logged.
Public Function RtccspiClearPowerFail() As Byte
    Result = WkWrite(255)
End Function

' Reads the power-down (up = False) or power-up (up = True) time stamp [5.7.1] as month, day, hour (0..23)
' and minute.
Public Function RtccspiStamp(ByVal up As Boolean, ByRef month As Byte, ByRef day As Byte, ByRef hour As Byte, ByRef minute As Byte) As Byte
    If up Then
        Result = ReadBlock(19, 28, 4)
    Else
        Result = ReadBlock(19, 24, 4)
    End If
    If Result = 0 Then
        minute = FromBcd(buf(0) And 127)
        hour = DecHour(buf(1))
        day = FromBcd(buf(2) And 63)
        month = FromBcd(buf(3) And 31)
    End If
End Function

' Programs alarm n (0 or 1) [5.4]. Alarm 0 is at 0x0C..0x11 (seconds .. month), alarm 1 at 0x12..0x17
' (hundredths .. date). `mask`: 0 seconds, 1 minutes, 2 hours, 3 weekday, 4 date, 5 hundredths of a second
' (alarm 1 only), 7 seconds + minutes + hours + weekday + date + month (the month is compared on alarm 0
' only); 6 is reserved. `hundredths` is used by alarm 1 only and `month` by alarm 0 only. The flag is cleared by
' the write. The pin assignment bit (W parts) is kept. All fields must be valid (month 1..12, day 1..31) even when unused. Arm the alarm with RtccspiAlarmEnable.
Public Function RtccspiAlarm(ByVal n As Byte, ByVal mask As Byte, ByVal month As Byte, ByVal day As Byte, ByVal weekday As Byte, ByVal hour As Byte, ByVal minute As Byte, ByVal second As Byte, ByVal hundredths As Byte) As Byte
    Dim pin As Byte
    Dim twelve As Boolean
    Result = 5
    If n > 1 Or mask = 6 Or mask > 7 Or month < 1 Or month > 12 Or day < 1 Or day > 31 Or weekday < 1 Or weekday > 7 Or hour > 23 Or minute > 59 Or second > 59 Or hundredths > 99 Then
        Exit
    End If
    If n = 0 And mask = 5 Then
        Exit
    End If
    Result = RdReg(3)
    If Result <> 0 Then
        Exit
    End If
    twelve = (buf(0) And 64) <> 0
    If n = 0 Then
        Result = RdReg(15)
    Else
        Result = RdReg(22)
    End If
    If Result <> 0 Then
        Exit
    End If
    pin = buf(0) And 128
    If n = 0 Then
        buf(0) = ToBcd(second)
        buf(1) = ToBcd(minute)
        buf(2) = EncHour(hour, twelve)
        buf(3) = pin Or (mask << 4) Or weekday
        buf(4) = ToBcd(day)
        buf(5) = ToBcd(month)
        Result = WriteBlock(18, 12, 6)
    Else
        buf(0) = ToBcd(hundredths)
        buf(1) = ToBcd(second)
        buf(2) = ToBcd(minute)
        buf(3) = EncHour(hour, twelve)
        buf(4) = pin Or (mask << 4) Or weekday
        buf(5) = ToBcd(day)
        Result = WriteBlock(18, 18, 6)
    End If
End Function

' Arms (arm = True) or disarms alarm n (ALMxEN in CONTROL).
Public Function RtccspiAlarmEnable(ByVal n As Byte, ByVal arm As Boolean) As Byte
    Dim m As Byte
    Result = 5
    If n > 1 Then
        Exit
    End If
    m = 16 << n
    Result = RdReg(8)
    If Result = 0 Then
        If arm Then
            Result = WrReg(8, buf(0) Or m)
        Else
            Result = WrReg(8, buf(0) And (m Xor 255))
        End If
    End If
End Function

' flag = True when alarm n has matched (ALMxIF).
Public Function RtccspiAlarmFlag(ByVal n As Byte, ByRef flag As Boolean) As Byte
    Result = 5
    If n > 1 Then
        Exit
    End If
    Result = RdReg(15 + 7 * n)
    If Result = 0 Then
        flag = (buf(0) And 8) <> 0
    End If
End Function

' Clears the alarm flag of alarm n (a 0 written to ALMxIF; it cannot be written to 1) [Register 5-13 note 3].
Public Function RtccspiAlarmClear(ByVal n As Byte) As Byte
    Dim r As Byte
    Result = 5
    If n > 1 Then
        Exit
    End If
    r = 15 + 7 * n
    Result = RdReg(r)
    If Result = 0 Then
        Result = WrReg(r, buf(0) And 247)
    End If
End Function

' W parts: assigns the output of alarm n to the WDO pin (wdo = True) or the IRQ pin (False) [DS20002280F Register
' 5-13, ALMxPIN]. The MCP7951X/2X ignore the bit.
Public Function RtccspiAlarmPin(ByVal n As Byte, ByVal wdo As Boolean) As Byte
    Dim r As Byte
    Result = 5
    If n > 1 Then
        Exit
    End If
    r = 15 + 7 * n
    Result = RdReg(r)
    If Result = 0 Then
        If wdo Then
            Result = WrReg(r, (buf(0) Or 128) And 247)
        Else
            Result = WrReg(r, buf(0) And 119)
        End If
    End If
End Function

' Square wave on MFP: sel 0 = 1 Hz, 1 = 4.096 kHz, 2 = 8.192 kHz, 3 = 32.768 kHz (SQWEN = 1) [Table 5-8]; see
' the header about selecting 2 or 3 with a crystal. Take it away again with RtccspiSquareWaveOff.
Public Function RtccspiSquareWave(ByVal sel As Byte) As Byte
    Result = 5
    If sel > 3 Then
        Exit
    End If
    Result = RdReg(8)
    If Result = 0 Then
        Result = WrReg(8, (buf(0) And 252) Or 64 Or sel)
    End If
End Function

Public Function RtccspiSquareWaveOff() As Byte
    Result = RdReg(8)
    If Result = 0 Then
        Result = WrReg(8, buf(0) And 191)
    End If
End Function

' Digital trim [5.6, Register 5-17]: steps -255..255. Positive steps add 2 clock cycles per step (a slow clock is
' sped up: TRIMSIGN = 1), negative steps remove them; 0 turns trimming off. About 1.017 ppm per step once a minute
' (coarse = False) or every second (coarse = True, CRSTRIM = 1, and MFP gives a trimmed 1 Hz).
Public Function RtccspiTrim(ByVal steps As Integer, ByVal coarse As Boolean) As Byte
    Dim v As Byte
    Dim sgn As Byte
    Result = 5
    If steps < -255 Or steps > 255 Then
        Exit
    End If
    sgn = 0
    If steps < 0 Then
        v = Byte(-steps)
    Else
        v = Byte(steps)
        If steps > 0 Then
            sgn = 128
        End If
    End If
    Result = WrReg(9, v)
    If Result = 0 Then
        Result = RdReg(3)
    End If
    ' The sign shares RTCHOUR with the running hour: write it only when the sign changes, so the read-modify-write
    ' window (a rollover inside it would put the old hour back) is not open on every call.
    If Result = 0 And (buf(0) And 128) <> sgn Then
        Result = WrReg(3, (buf(0) And 127) Or sgn)
    End If
    If Result = 0 Then
        Result = RdReg(8)
    End If
    If Result = 0 Then
        If coarse Then
            Result = WrReg(8, buf(0) Or 4)
        Else
            Result = WrReg(8, buf(0) And 251)
        End If
    End If
End Function

' SRAM, 64 bytes at RTCC addresses 0x20..0x5F (kept on VBAT, not cleared by a reset); addr 0..63.
Public Function RtccspiRamRead(ByVal addr As Byte, ByRef value As Byte) As Byte
    Result = 5
    If addr > 63 Then
        Exit
    End If
    Result = RdReg(32 + addr)
    If Result = 0 Then
        value = buf(0)
    End If
End Function

Public Function RtccspiRamWrite(ByVal addr As Byte, ByVal value As Byte) As Byte
    Result = 5
    If addr > 63 Then
        Exit
    End If
    Result = WrReg(32 + addr, value)
End Function

' Clears all 64 bytes of SRAM (CLRRAM, instruction 0x54 and a dummy byte) [6.1.3].
Public Function RtccspiRamClear() As Byte
    Result = Cmd2(84, 0)
End Function

' STATUS register into buf(0): SRREAD (0x05) has no address byte.
Function StatusRead() As Byte
    Result = 4
    If Not ready Then
        Exit
    End If
    Pinio.PinSet(csPin, False)
    Spi.SpiWrite(5)
    buf(0) = Spi.SpiRead()
    Result = Spi.SpiStatus()
    Pinio.PinSet(csPin, True)
End Function

' Waits for the end of a running EEPROM write cycle (TWC is 5 ms): STATUS (SRREAD 0x05) bit 0 is WIP [6.2].
' 6 if still busy after 20 ms.
Function EeReady() As Byte
    Dim n As Byte
    Result = 6
    n = 0
    While n < 20
        Result = StatusRead()
        If Result <> 0 Then
            Exit
        End If
        If (buf(0) And 1) = 0 Then
            Exit
        End If
        Result = 6
        DelayMs(1)
        Inc(n)
    Wend
End Function

' Sets the write enable latch (EEWREN 0x06), after the end of a write cycle.
Function WrEnable() As Byte
    Result = EeReady()
    If Result = 0 Then
        Result = Cmd1(6)
    End If
End Function

' EEPROM: addr 0..255 on the MCP7952X, MCP795W2X (256 bytes) and 0..127 on the MCP7951X, MCP795W1X
' (128 bytes; the upper half is mapped back onto the lower [Figure 5-1]). A write starts a 5 ms cycle and the
' next EEPROM call waits for it; the RTCC and SRAM can be used meanwhile. A write to a protected area is
' silently ignored (see RtccspiEeProtect).
Public Function RtccspiEeRead(ByVal addr As Byte, ByRef value As Byte) As Byte
    Result = EeReady()
    If Result = 0 Then
        Result = ReadBlock(3, addr, 1)
    End If
    If Result = 0 Then
        value = buf(0)
    End If
End Function

Public Function RtccspiEeWrite(ByVal addr As Byte, ByVal value As Byte) As Byte
    Result = WrEnable()
    If Result = 0 Then
        buf(0) = value
        Result = WriteBlock(2, addr, 1)
    End If
End Function

' Write protection of the EEPROM array (STATUS register BP<1:0>, nonvolatile) [Register 6-1]: 0 none, 1 upper
' quarter, 2 upper half, 3 all.
Public Function RtccspiEeProtect(ByVal level As Byte) As Byte
    Result = 5
    If level > 3 Then
        Exit
    End If
    Result = WrEnable()
    If Result = 0 Then
        Result = Cmd2(1, level << 2)
    End If
End Function

' Protected EEPROM, 16 bytes (i = 0..15): the node address (EUI-48 or EUI-64) of the X1 and X2 parts is in
' the first 8, the other 8 are a user ID [Figure 5-1, 6.4]. Reading needs no unlock.
Public Function RtccspiIdRead(ByVal i As Byte, ByRef value As Byte) As Byte
    Result = 5
    If i > 15 Then
        Exit
    End If
    Result = EeReady()
    If Result = 0 Then
        Result = ReadBlock(51, i, 1)
    End If
    If Result = 0 Then
        value = buf(0)
    End If
End Function

' Writes one byte of the protected EEPROM: EEWREN, then UNLOCK with 0x55, UNLOCK with 0xAA (each its own chip
' select cycle), then IDWRITE [6.4.2, 6.4.3]. The block locks again after each write.
Public Function RtccspiIdWrite(ByVal i As Byte, ByVal value As Byte) As Byte
    Result = 5
    If i > 15 Then
        Exit
    End If
    Result = WrEnable()
    If Result = 0 Then
        Result = Cmd2(20, 85)
    End If
    If Result = 0 Then
        Result = Cmd2(20, 170)
    End If
    If Result = 0 Then
        buf(0) = value
        Result = WriteBlock(50, i, 1)
    End If
End Function

' W parts: configures the watchdog (WDTCON 0x0A) [DS20002280F Register 5-16]. period 0..7: 32, 512, 2048, 4096,
' 32768, 524288, 1048576 or 2097152 oscillator cycles (977 us .. 64 s); delay = True adds the 64 s start-up
' delay after each clear; longPulse = True makes the WDO pulse 125 ms instead of 122 us; enable starts it.
' The watchdog is cleared by RtccspiWdtClear. WDTEN clears itself on battery. The MCP7951X/2X have none.
Public Function RtccspiWdt(ByVal en As Boolean, ByVal period As Byte, ByVal delay As Boolean, ByVal longPulse As Boolean) As Byte
    Dim v As Byte
    Result = 5
    If period > 7 Then
        Exit
    End If
    v = period
    If longPulse Then
        v = v Or 16
    End If
    If delay Then
        v = v Or 32
    End If
    If en Then
        v = v Or 128
    End If
    Result = WrReg(10, v)
End Function

' Clears (kicks) the watchdog: the CLRWDT instruction 0x44 [DS20002280F Table 4-1].
Public Function RtccspiWdtClear() As Byte
    Result = Cmd1(68)
End Function

' flag = True when the watchdog timed out (WDTIF); clear it with RtccspiWdtFlagClear.
Public Function RtccspiWdtFlag(ByRef flag As Boolean) As Byte
    Result = RdReg(10)
    If Result = 0 Then
        flag = (buf(0) And 64) <> 0
    End If
End Function

Public Function RtccspiWdtFlagClear() As Byte
    Result = RdReg(10)
    If Result = 0 Then
        Result = WrReg(10, buf(0) And 191)
    End If
End Function

' W parts: event detection (EVDTCON 0x0B) [DS20002280F Register 5-17]. lowEnable arms the low-speed input with a
' debounce of 31.25 ms (slow = False) or 500 ms (True); highCount arms the high-speed input for 1, 4, 16 or 32
' transitions (0..3 select them; 255 leaves it off). Flags are read and cleared with RtccspiEventFlags.
Public Function RtccspiEvents(ByVal lowEnable As Boolean, ByVal slow As Boolean, ByVal highCount As Byte) As Byte
    Dim v As Byte
    Result = 5
    If highCount > 3 And highCount <> 255 Then
        Exit
    End If
    v = 0
    If lowEnable Then
        v = v Or 16
    End If
    If slow Then
        v = v Or 4
    End If
    If highCount <> 255 Then
        v = v Or 32 Or highCount
    End If
    Result = WrReg(11, v)
End Function

' lowFlag / highFlag = True when the low-speed (EVLIF) or high-speed (EVHIF) event was detected. clr = True
' clears both flags afterwards.
Public Function RtccspiEventFlags(ByRef lowFlag As Boolean, ByRef highFlag As Boolean, ByVal clr As Boolean) As Byte
    Result = RdReg(11)
    If Result = 0 Then
        lowFlag = (buf(0) And 64) <> 0
        highFlag = (buf(0) And 128) <> 0
        If clr Then
            Result = WrReg(11, buf(0) And 63)
        End If
    End If
End Function
