Module I2c
' I2C host (master) on MSSP1, DS40002043F chapter 28. SCL and SDA go to any pin of ports B and C
' (pin numbers 8..23: RB0..RB7 = 8..15, RC0..RC7 = 16..23, as the Adc channels); the reset
' selection is SCL = RC3 (19) and SDA = RC4 (20) [Table 18-1]. The module is the only host on the
' bus (no multi-master): a bus collision is reported as an error. The bus needs external pull-ups.
' `Clock` must be FOSC in MHz.
'
' Clock [Equation 28-1, SSPM = 1000]: f = FOSC / (4 * (SSPxADD + 1)). SSPxADD 0..2 are not valid
' for I2C [28.7], so the highest clock is FOSC / 16 and the lowest FOSC / 1024 (62 kHz at 64 MHz).
' I2cInit rounds the divider up, so the clock is at or below the one asked for. The slew rate control
' bit SMP is set (disabled) for 100 kHz or less and for 1 MHz and above, and cleared (enabled) in
' between [28.9.1].
'
' Every step is done by the hardware one at a time (the host mode does not queue events [28.6]);
' each wait is bounded, so a stuck bus returns an error instead of hanging. Status codes:
'   0 ok, 1 timeout (a bus line held low or no pull-up), 2 bus collision, 3 no acknowledge,
'   4 module not initialised.
' A bus collision resets the MSSP to idle [28.6.4]; the module clears BCL1IF and WCOL itself.
' The module is not reentrant: do not call it from a handler and from the main program. It does
' not use the MSSP1 interrupt (SSP1IF is polled and cleared by the module), so keep that interrupt
' disabled.
Dim FlagSsp As PIR3.0
Dim FlagBcl As PIR3.1
Dim BitRcen As SSP1CON2.3
Dim BitAckdt As SSP1CON2.5
Dim BitAckstat As SSP1CON2.6
Dim BitWcol As SSP1CON1.7
Dim ready As Boolean
Dim lastStatus As Byte

' RxyPPS = code for pin 8..23.
Sub SetPps(ByVal pin As Byte, ByVal code As Byte)
    If pin = 8 Then
        RB0PPS = code
    ElseIf pin = 9 Then
        RB1PPS = code
    ElseIf pin = 10 Then
        RB2PPS = code
    ElseIf pin = 11 Then
        RB3PPS = code
    ElseIf pin = 12 Then
        RB4PPS = code
    ElseIf pin = 13 Then
        RB5PPS = code
    ElseIf pin = 14 Then
        RB6PPS = code
    ElseIf pin = 15 Then
        RB7PPS = code
    ElseIf pin = 16 Then
        RC0PPS = code
    ElseIf pin = 17 Then
        RC1PPS = code
    ElseIf pin = 18 Then
        RC2PPS = code
    ElseIf pin = 19 Then
        RC3PPS = code
    ElseIf pin = 20 Then
        RC4PPS = code
    ElseIf pin = 21 Then
        RC5PPS = code
    ElseIf pin = 22 Then
        RC6PPS = code
    ElseIf pin = 23 Then
        RC7PPS = code
    End If
End Sub

' Both bus pins are inputs (the MSSP pulls them low as needed [28.6]) and digital.
Sub PinSetup(ByVal pin As Byte)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 16 Then
        TRISB = TRISB Or m
        ANSELB = ANSELB And (m Xor 255)
    Else
        TRISC = TRISC Or m
        ANSELC = ANSELC And (m Xor 255)
    End If
End Sub

' Waits for SSP1IF; returns 0 when it is set (and clears it), 1 on timeout, 2 on a bus collision.
Function WaitIf() As Byte
    Dim n As Word
    n = 0
    Result = 1
    While n < 60000
        If FlagBcl = 1 Then
            FlagBcl = 0
            Result = 2
            Exit
        End If
        If FlagSsp = 1 Then
            FlagSsp = 0
            Result = 0
            Exit
        End If
        Inc(n)
    Wend
End Function

' Waits until the control bits `msk` of SSP1CON2 are all clear (the operation they started is done).
Function WaitIdle(ByVal msk As Byte) As Byte
    Dim n As Word
    n = 0
    Result = 1
    While n < 60000
        If FlagBcl = 1 Then
            FlagBcl = 0
            Result = 2
            Exit
        End If
        If (SSP1CON2 And msk) = 0 Then
            Result = 0
            Exit
        End If
        Inc(n)
    Wend
End Function

' Starts one SSP1CON2 operation (SEN, RSEN, PEN as the bit mask) and waits for it to finish.
Function Condition(ByVal msk As Byte) As Byte
    Result = WaitIdle(31)
    If Result = 0 Then
        FlagSsp = 0
        SSP1CON2 = SSP1CON2 Or msk
        Result = WaitIdle(msk)
    End If
End Function

' Sets up MSSP1 as an I2C host at about `hz` (1..1000000, rounded down to the nearest clock the
' divider gives) with SCL on `scl` and SDA on `sda` (pins 8..23, different). Returns 1 when set up,
' 0 when a pin is not allowed or no divider of 3..255 reaches `hz`.
Public Function I2cInit(ByVal hz As LongWord, ByVal scl As Byte, ByVal sda As Byte) As Byte
    Dim fosc As LongWord
    Dim d As LongWord
    Result = 0
    If scl < 8 Or scl > 23 Or sda < 8 Or sda > 23 Or scl = sda Or hz = 0 Or hz > 1000000 Then
        Exit
    End If
    fosc = LongWord(_Clock * 1000000)
    ' SSPxADD = ceil(FOSC / (4 * hz)) - 1
    d = (fosc + LongWord(4) * hz - 1) / (LongWord(4) * hz) - 1
    If d < 3 Or d > 255 Then
        Exit
    End If
    SSP1CON1 = 0
    PinSetup(scl)
    PinSetup(sda)
    SSP1CLKPPS = scl
    SSP1DATPPS = sda
    SetPps(scl, 15)
    SetPps(sda, 16)
    SSP1ADD = Byte(d)
    SSP1CON2 = 0
    SSP1CON3 = 0
    If hz > 100000 And hz < 1000000 Then
        SSP1STAT = 0
    Else
        SSP1STAT = 128
    End If
    FlagSsp = 0
    FlagBcl = 0
    SSP1CON1 = 40
    ready = True
    lastStatus = 0
    Result = 1
End Function

' Disables the MSSP and gives both pins back to their LATxy bits (SDA and SCL are given as at
' I2cInit).
Public Sub I2cOff(ByVal scl As Byte, ByVal sda As Byte)
    SSP1CON1 = 0
    If scl >= 8 And scl <= 23 Then
        SetPps(scl, 0)
    End If
    If sda >= 8 And sda <= 23 Then
        SetPps(sda, 0)
    End If
    ready = False
End Sub

' The status of the last Start, Restart, Stop, byte or register routine (codes in the header).
Public Function I2cStatus() As Byte
    Result = lastStatus
End Function

' Start condition. Returns the status code.
Public Function I2cStart() As Byte
    Result = 4
    If ready Then
        Result = Condition(1)
    End If
    lastStatus = Result
End Function

' Repeated start condition. Returns the status code.
Public Function I2cRestart() As Byte
    Result = 4
    If ready Then
        Result = Condition(2)
    End If
    lastStatus = Result
End Function

' Stop condition. Returns the status code.
Public Function I2cStop() As Byte
    Result = 4
    If ready Then
        Result = Condition(4)
    End If
    lastStatus = Result
End Function

' Sends a byte (an address with its R/W bit, or data) and returns the status code: 0 when the client
' acknowledged, 3 when it did not [ACKSTAT, 28.6.6].
Public Function I2cSend(ByVal b As Byte) As Byte
    Result = 4
    If Not ready Then
        lastStatus = Result
        Exit
    End If
    Result = WaitIdle(31)
    If Result = 0 Then
        FlagSsp = 0
        BitWcol = 0
        SSP1BUF = b
        If BitWcol = 1 Then
            BitWcol = 0
            Result = 1
        Else
            Result = WaitIf()
            If Result = 0 And BitAckstat = 1 Then
                Result = 3
            End If
        End If
    End If
    lastStatus = Result
End Function

' Receives a byte and then sends an acknowledge (`ack` = True, more bytes follow) or a not
' acknowledge (False, for the last byte) [28.6.7, 28.6.8]. The value is returned in the low byte;
' on an error it returns 0 and I2cStatus is not 0.
Public Function I2cReceive(ByVal ack As Boolean) As Byte
    Result = 0
    lastStatus = 4
    If Not ready Then
        Exit
    End If
    lastStatus = WaitIdle(31)
    If lastStatus = 0 Then
        FlagSsp = 0
        BitRcen = 1
        lastStatus = WaitIf()
    End If
    If lastStatus = 0 Then
        Result = SSP1BUF
        If ack Then
            BitAckdt = 0
        Else
            BitAckdt = 1
        End If
        lastStatus = Condition(16)
    End If
End Function

' True when a client answers (acknowledges) the 7-bit address `addr` (0..127) for writing.
Public Function I2cPing(ByVal addr As Byte) As Boolean
    Dim s As Byte
    Result = False
    s = I2cStart()
    If s = 0 Then
        s = I2cSend(addr << 1)
        If s = 0 Then
            Result = True
        End If
    End If
    I2cStop()
End Function

' Writes `value` to register `reg` of the client at 7-bit address `addr`: Start, address + W, reg,
' value, Stop. Returns the first status code that was not 0 (the Stop is always attempted).
Public Function I2cWriteReg(ByVal addr As Byte, ByVal reg As Byte, ByVal value As Byte) As Byte
    Dim s As Byte
    Result = I2cStart()
    If Result = 0 Then
        Result = I2cSend(addr << 1)
    End If
    If Result = 0 Then
        Result = I2cSend(reg)
    End If
    If Result = 0 Then
        Result = I2cSend(value)
    End If
    s = I2cStop()
    If Result = 0 Then
        Result = s
    End If
    lastStatus = Result
End Function

' Reads register `reg` of the client at 7-bit address `addr`: Start, address + W, reg, Restart,
' address + R, one byte with not acknowledge, Stop. On an error it returns 0 and I2cStatus is not 0.
Public Function I2cReadReg(ByVal addr As Byte, ByVal reg As Byte) As Byte
    Dim s As Byte
    Dim e As Byte
    Result = 0
    e = I2cStart()
    If e = 0 Then
        e = I2cSend(addr << 1)
    End If
    If e = 0 Then
        e = I2cSend(reg)
    End If
    If e = 0 Then
        e = I2cRestart()
    End If
    If e = 0 Then
        e = I2cSend((addr << 1) Or 1)
    End If
    If e = 0 Then
        Result = I2cReceive(False)
        e = lastStatus
    End If
    s = I2cStop()
    If e = 0 Then
        e = s
    End If
    If e <> 0 Then
        Result = 0
    End If
    lastStatus = e
End Function
