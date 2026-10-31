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

' PIC18F0x/1xQ41 (chosen with `#if _has(I2C1CON0)`): the same routines and status codes, driven in software on
' two ordinary pins instead of the I2C1 peripheral. Reason: I2C1 counts the bytes of a transfer in hardware
' (I2C1CNT; Stop or Restart by itself, DS40002214G 36.4.2.7) and its host acknowledges a received byte before
' the program says whether it wants another, so the one-step-at-a-time Start / Send / Receive(ack) / Restart /
' Stop used by `Oled`, `Aht30` and programs cannot be mapped onto it without knowing the length first. Pins are
' numbered 0..23 (RA0..RA7 = 0..7, RB0..RB7 = 8..15, RC0..RC7 = 16..23); RA3 is input only and refused, port B
' pins only on the 20-pin parts. SCL and SDA are open drain: the latch bit is 0, the pin pulls low by clearing
' its TRIS bit and releases by setting it, so the bus needs external pull-ups. A client that stretches the clock
' is waited for (bounded, status 1). `hz` is 2000..400000; each half period is DelayUS(ceil(500000 / hz)) plus
' the time of the routines, so the real clock is lower, much lower on a slow `Clock`. Arbitration: SDA is read
' back after each bit sent; a difference is status 2.
' PIC16F183xx (DS40001799F, DS40001800E, DS40001795K, DS40001839E, chapters 13 and 30; chosen with `_has(ADCON0.CHS)`): the same MSSP1 host [Register 30-2: SSPM = 1000, SSP1ADD 0..2 not
' supported], with the pins numbered as on the PIC16F17126/46 (RA0..RA5 except RA3, RB4..RB7 on the 20-pin parts, RC0..RC5 on the 14-pin parts and RC0..RC7 on the 20-pin parts),
' `RxyPPS` 18h (24) = SCL1 and 19h (25) = SDA1 [Register 13-2], SSP1IF and BCL1IF in PIR1 bits 3 and 2. The errata for I2C concern only the LF parts (acknowledge failure,
' DS80000667E 1.4.1, DS80000668L 6.2) and the SMBus VIL level (DS80000666H 5.2); nothing for the F parts at the current silicon revision.
' PIC16F17126/46 (DS40002343F chapters 18 and 31; chosen with `Not _has(PRODL)`): the MSSP1 host of the Q10 below, with pins numbered 0..23 as
' on the Q41 (RA0..RA5 except RA3, RB4..RB7 on the 20-pin part, RC0..RC7), `RxyPPS` 27 = SCL1 and 28 = SDA1 [Table 18-2], SSP1IF and BCL1IF in
' PIR5 bits 2 and 3. Erratum 1.2.1 (spurious start and stop flags when I2C is enabled, silicon B0) does not matter here: SSP1IF is cleared
' before each step and the start and stop interrupts are not used.
' PIC16F152xx (DS40002195E chapters 18 and 25; chosen with `_has(ADCON1.PREF)`): the same MSSP1 host [SSPM = 1000, SSP1ADD 0..2 not valid], the pins numbered as on the PIC16F183xx, `RxyPPS` 07h = SCL1 and 08h = SDA1
' [Table 18-2 p.148], SSP1IF and BCL1IF in PIR1 bits 1 and 2 [12.9.6]. Silicon erratum 1.4.1 (DS80000918K, all revisions: Start and Stop flags can be set when I2C is enabled) does not matter here, as on the PIC16F17126/46:
' SCIE and PCIE stay 0 (SSP1CON3 = 0), SSP1IF is cleared before each step, and the S and P bits are never read.
#if _has(I2C1CON0)
Dim sclPort As Byte
Dim sclMask As Byte
Dim sdaPort As Byte
Dim sdaMask As Byte
Dim halfUs As Byte
Dim ready As Boolean
Dim lastStatus As Byte

' TRIS bit set: the pin is released (an input, pulled up outside).
Sub Release(ByVal port As Byte, ByVal m As Byte)
    If port = 0 Then
        TRISA = TRISA Or m
#if _has(TRISB)
    ElseIf port = 1 Then
        TRISB = TRISB Or m
#endif
    Else
        TRISC = TRISC Or m
    End If
End Sub

' TRIS bit clear with the latch bit 0: the pin pulls the line low.
Sub PullLow(ByVal port As Byte, ByVal m As Byte)
    Dim n As Byte
    n = m Xor 255
    If port = 0 Then
        TRISA = TRISA And n
#if _has(TRISB)
    ElseIf port = 1 Then
        TRISB = TRISB And n
#endif
    Else
        TRISC = TRISC And n
    End If
End Sub

Function Level(ByVal port As Byte, ByVal m As Byte) As Boolean
    Dim v As Byte
    If port = 0 Then
        v = PORTA
#if _has(TRISB)
    ElseIf port = 1 Then
        v = PORTB
#endif
    Else
        v = PORTC
    End If
    Result = (v And m) <> 0
End Function

' Latch bit 0 and a digital pin, released.
Sub PinSetup(ByVal port As Byte, ByVal m As Byte)
    Dim n As Byte
    n = m Xor 255
    If port = 0 Then
        LATA = LATA And n
        ANSELA = ANSELA And n
#if _has(TRISB)
    ElseIf port = 1 Then
        LATB = LATB And n
        ANSELB = ANSELB And n
#endif
    Else
        LATC = LATC And n
        ANSELC = ANSELC And n
    End If
    Release(port, m)
End Sub

Function PinOk(ByVal pin As Byte) As Boolean
    Result = (pin <= 5 And pin <> 3) Or (pin >= 16 And pin <= 21)
#if _has(RC6PPS)
    If pin = 22 Or pin = 23 Then
        Result = True
    End If
#endif
#if _has(TRISB)
    If pin >= 12 And pin <= 15 Then
        Result = True
    End If
#endif
End Function

Sub Half()
    DelayUS(halfUs)
End Sub

' Releases SCL and waits for it to be high (a client may hold it low). False on a timeout.
Function SclHigh() As Boolean
    Dim n As Word
    Release(sclPort, sclMask)
    n = 0
    Result = False
    While n < 20000
        If Level(sclPort, sclMask) Then
            Result = True
            Exit
        End If
        Inc(n)
    Wend
End Function

Sub SdaSet(ByVal one As Boolean)
    If one Then
        Release(sdaPort, sdaMask)
    Else
        PullLow(sdaPort, sdaMask)
    End If
End Sub

' Sets up the two pins as a software host at about `hz` (2000..400000) with SCL on `scl` and SDA on `sda`
' (different pins). Returns 1, or 0 for a pin that is not allowed or an `hz` out of range.
Public Function I2cInit(ByVal hz As LongWord, ByVal scl As Byte, ByVal sda As Byte) As Byte
    Dim h As LongWord
    Result = 0
    If Not PinOk(scl) Or Not PinOk(sda) Or scl = sda Or hz < 2000 Or hz > 400000 Then
        Exit
    End If
    h = (500000 + hz - 1) / hz
    halfUs = Byte(h)
    sclPort = scl >> 3
    sclMask = 1 << (scl And 7)
    sdaPort = sda >> 3
    sdaMask = 1 << (sda And 7)
    PinSetup(sclPort, sclMask)
    PinSetup(sdaPort, sdaMask)
    ready = True
    lastStatus = 0
    Result = 1
End Function

' Gives both pins back as plain inputs (the pins given to I2cInit).
Public Sub I2cOff(ByVal scl As Byte, ByVal sda As Byte)
    If PinOk(scl) Then
        Release(scl >> 3, 1 << (scl And 7))
    End If
    If PinOk(sda) Then
        Release(sda >> 3, 1 << (sda And 7))
    End If
    ready = False
End Sub

' The status of the last Start, Restart, Stop, byte or register routine (codes in the header).
Public Function I2cStatus() As Byte
    Result = lastStatus
End Function

' Start condition: SDA falls while SCL is high. A repeated start first releases SDA, then SCL.
Function Condition(ByVal restart As Boolean) As Byte
    Result = 0
    If restart Then
        SdaSet(True)
        Half()
        If Not SclHigh() Then
            Result = 1
            Exit
        End If
        Half()
    End If
    If Not Level(sdaPort, sdaMask) Then
        Result = 2
        Exit
    End If
    SdaSet(False)
    Half()
    PullLow(sclPort, sclMask)
    Half()
End Function

Public Function I2cStart() As Byte
    Result = 4
    If ready Then
        Result = Condition(False)
    End If
    lastStatus = Result
End Function

Public Function I2cRestart() As Byte
    Result = 4
    If ready Then
        Result = Condition(True)
    End If
    lastStatus = Result
End Function

' Stop condition: SDA rises while SCL is high.
Public Function I2cStop() As Byte
    Result = 4
    If ready Then
        Result = 0
        SdaSet(False)
        Half()
        If SclHigh() Then
            Half()
            SdaSet(True)
            Half()
            If Not Level(sdaPort, sdaMask) Then
                Result = 2
            End If
        Else
            Result = 1
        End If
    End If
    lastStatus = Result
End Function

' One clock pulse with SDA at `one`; returns SDA as read while SCL is high. SCL is left low. A stuck clock sets
' lastStatus to 1.
Function Clk(ByVal one As Boolean) As Boolean
    SdaSet(one)
    Half()
    If SclHigh() Then
        Result = Level(sdaPort, sdaMask)
        Half()
    Else
        Result = False
        lastStatus = 1
    End If
    PullLow(sclPort, sclMask)
End Function

' Sends a byte (an address with its R/W bit, or data), MSb first, then reads the acknowledge. Returns 0 when the
' client acknowledged, 3 when it did not, 2 when SDA differs from what was sent, 1 on a stuck clock.
Public Function I2cSend(ByVal b As Byte) As Byte
    Dim i As Byte
    Dim one As Boolean
    Dim got As Boolean
    Result = 4
    If Not ready Then
        lastStatus = Result
        Exit
    End If
    Result = 0
    lastStatus = 0
    i = 0
    While i < 8 And Result = 0
        one = (b And 128) <> 0
        got = Clk(one)
        If lastStatus <> 0 Then
            Result = lastStatus
        ElseIf got <> one Then
            Result = 2
        End If
        b = b << 1
        Inc(i)
    Wend
    If Result = 0 Then
        got = Clk(True)
        If lastStatus <> 0 Then
            Result = lastStatus
        ElseIf got Then
            Result = 3
        End If
    End If
    lastStatus = Result
End Function

' Receives a byte and then sends an acknowledge (`ack` = True, more bytes follow) or a not acknowledge (False,
' for the last byte). On an error it returns 0 and I2cStatus is not 0.
Public Function I2cReceive(ByVal ack As Boolean) As Byte
    Dim i As Byte
    Dim v As Byte
    Dim got As Boolean
    Result = 0
    lastStatus = 4
    If Not ready Then
        Exit
    End If
    lastStatus = 0
    v = 0
    i = 0
    While i < 8 And lastStatus = 0
        got = Clk(True)
        v = v << 1
        If got Then
            v = v Or 1
        End If
        Inc(i)
    Wend
    If lastStatus = 0 Then
        got = Clk(Not ack)
    End If
    If lastStatus = 0 Then
        Result = v
    End If
    SdaSet(True)
End Function

#else
#if _has(PRODL)
Dim FlagSsp As PIR3.0
Dim FlagBcl As PIR3.1
#elseif _has(ADCON1.PREF)
Dim FlagSsp As PIR1.1
Dim FlagBcl As PIR1.2
Const SclCode = 7
Const SdaCode = 8
#elseif _has(ADCON0.CHS)
Dim FlagSsp As PIR1.3
Dim FlagBcl As PIR1.2
Const SclCode = 24
Const SdaCode = 25
#else
Dim FlagSsp As PIR5.2
Dim FlagBcl As PIR5.3
Const SclCode = 27
Const SdaCode = 28
#endif
Dim BitRcen As SSP1CON2.3
Dim BitAckdt As SSP1CON2.5
Dim BitAckstat As SSP1CON2.6
Dim BitWcol As SSP1CON1.7
Dim ready As Boolean
Dim lastStatus As Byte

#if Not _has(PRODL)
' RxyPPS = code for pin 0..23 (a pin the part has).
Sub SetPps(ByVal pin As Byte, ByVal code As Byte)
    If pin = 0 Then
        RA0PPS = code
    ElseIf pin = 1 Then
        RA1PPS = code
    ElseIf pin = 2 Then
        RA2PPS = code
    ElseIf pin = 4 Then
        RA4PPS = code
    ElseIf pin = 5 Then
        RA5PPS = code
#if _has(RB4PPS)
    ElseIf pin = 12 Then
        RB4PPS = code
    ElseIf pin = 13 Then
        RB5PPS = code
    ElseIf pin = 14 Then
        RB6PPS = code
    ElseIf pin = 15 Then
        RB7PPS = code
#endif
#if _has(RC0PPS)
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
#if _has(RC6PPS)
    ElseIf pin = 22 Then
        RC6PPS = code
    ElseIf pin = 23 Then
        RC7PPS = code
#endif
#endif
    End If
End Sub

' True for a pin the part has (RA3 is input only and refused).
Function PinOk(ByVal pin As Byte) As Boolean
#if _has(RC0PPS)
    Result = (pin <= 5 And pin <> 3) Or (pin >= 16 And pin <= 21)
#else
    Result = pin <= 5 And pin <> 3
#endif
#if _has(RC6PPS)
    If pin = 22 Or pin = 23 Then
        Result = True
    End If
#endif
#if _has(RB4PPS)
    If pin >= 12 And pin <= 15 Then
        Result = True
    End If
#endif
End Function

' Both bus pins are inputs (the MSSP pulls them low as needed [31.6]) and digital.
Sub PinSetup(ByVal pin As Byte)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 8 Then
        TRISA = TRISA Or m
        ANSELA = ANSELA And (m Xor 255)
#if _has(TRISB)
    ElseIf pin < 16 Then
        TRISB = TRISB Or m
        ANSELB = ANSELB And (m Xor 255)
#endif
#if _has(TRISC)
    Else
        TRISC = TRISC Or m
        ANSELC = ANSELC And (m Xor 255)
#endif
    End If
End Sub
#else
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
#endif

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
' divider gives) with SCL on `scl` and SDA on `sda` (pins 8..23, different; 0..23 as the part has them on the PIC16F171xx). Returns 1 when set up,
' 0 when a pin is not allowed or no divider of 3..255 reaches `hz`.
Public Function I2cInit(ByVal hz As LongWord, ByVal scl As Byte, ByVal sda As Byte) As Byte
    Dim fosc As LongWord
    Dim d As LongWord
    Result = 0
#if _has(PRODL)
    If scl < 8 Or scl > 23 Or sda < 8 Or sda > 23 Or scl = sda Or hz = 0 Or hz > 1000000 Then
#else
    If Not PinOk(scl) Or Not PinOk(sda) Or scl = sda Or hz = 0 Or hz > 1000000 Then
#endif
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
#if _has(PRODL)
    SetPps(scl, 15)
    SetPps(sda, 16)
#else
    SetPps(scl, SclCode)
    SetPps(sda, SdaCode)
#endif
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
#if _has(PRODL)
    If scl >= 8 And scl <= 23 Then
        SetPps(scl, 0)
    End If
    If sda >= 8 And sda <= 23 Then
        SetPps(sda, 0)
    End If
#else
    If PinOk(scl) Then
        SetPps(scl, 0)
    End If
    If PinOk(sda) Then
        SetPps(sda, 0)
    End If
#endif
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
#endif

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
