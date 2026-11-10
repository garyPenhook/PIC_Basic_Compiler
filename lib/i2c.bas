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

' PIC18F0x/1xQ41 with `#option I2c = Hardware` in the main program (`_i2chw`): the I2C1 peripheral, through the block routines
' I2cReadRegs / I2cWriteRegs / I2cProbe (data in I2cBuf) only: the peripheral counts the bytes of a transfer, so the step routines
' below do not exist in that mode (see the hardware section after the software host). The block routines also exist for the step
' routines of the other backends, and status 5 is a byte count outside 1..8.
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
#if Not _i2chw
Dim sclPort As Byte
Dim sclMask As Byte
Dim sdaPort As Byte
Dim sdaMask As Byte
Dim halfUs As Byte
#endif
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

#if Not _i2chw
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
' ---- PIC18F0x/1xQ41 with `#option I2c = Hardware`: the I2C1 peripheral (DS40002214G chapter 36) ----
' Registers and bits used (host mode, 7-bit addressing, address buffers off so that a write to I2C1TXB starts a transfer):
'   I2C1CON0 EN 7, RSEN 6, MDR 3, MODE 2:0 = 100 (host, 7-bit)    I2C1CON1 ACKCNT 7, ACKDT 6, P 3
'   I2C1CON2 ABD 4 (= 1)                                          I2C1STAT0 MMA 5 (host active)
'   I2C1STAT1 TXBE 5, CLRBF 2, RXBF 0
'   I2C1ERR NACKIF 4, BCLIF 5                                      I2C1CNT = bytes still to move, counted by the module
Dim BitMdr As I2C1CON0.3
Dim BitP As I2C1CON1.3
Dim BitMma As I2C1STAT0.5
Dim BitTxbe As I2C1STAT1.5
Dim BitRxbf As I2C1STAT1.0
Dim FlagNack As I2C1ERR.4
Dim FlagBcl As I2C1ERR.5
Dim sclPin As Byte
Dim sdaPin As Byte
Public Dim I2cBuf(8) As Byte

' True for a pin the part has (0..23: RA3 is input only and refused). The same pins as PinOk of the software host, written
' shorter; keep the two in step (tests/exec_q41/lib_i2c_pins.bas and scripts/test_i2chw.py check the same set).
Function PinGood(ByVal pin As Byte) As Boolean
    Result = False
    If pin = 3 Or pin > 5 And pin < 12 Then
        Exit
    End If
#if Not _has(TRISB)
    If pin > 11 And pin < 16 Then
        Exit
    End If
#endif
#if _has(RC6PPS)
    If pin > 23 Then
#else
    If pin > 21 Then
#endif
        Exit
    End If
    Result = True
End Function

' Open drain (the module needs it on both pins, [DS40002214G Register 36-1 note 1]).
Sub OpenDrain(ByVal port As Byte, ByVal m As Byte)
    If port = 0 Then
        ODCONA = ODCONA Or m
#if _has(TRISB)
    ElseIf port = 1 Then
        ODCONB = ODCONB Or m
#endif
    Else
        ODCONC = ODCONC Or m
    End If
End Sub

' Back to push-pull (the reset state), for I2cOff.
Sub PushPull(ByVal port As Byte, ByVal m As Byte)
    Dim v As Byte
    v = m Xor 255
    If port = 0 Then
        ODCONA = ODCONA And v
#if _has(TRISB)
    ElseIf port = 1 Then
        ODCONB = ODCONB And v
#endif
    Else
        ODCONC = ODCONC And v
    End If
End Sub

' RxyPPS = code for pin 0..23 (a pin the part has; PinGood is checked by the caller). The registers are contiguous from
' RA0PPS (0x201) in the order of the pin numbers [DS40002214G Table 21-2, register summary], so one indirect write
' through FSR2 replaces a chain of one comparison per pin. FSR2 is free for the program unless it uses the reentrant
' software stack (ABI.md 2), where it is the stack pointer: it is saved and put back. The Asm block names the parameters
' and the two save bytes, so the compiler keeps them.
Sub SetPps(ByVal pin As Byte, ByVal code As Byte)
    Dim sl As Byte
    Dim sh As Byte
    sl = 0
    sh = 0
    Asm
        movff FSR2L, I2C_SETPPS__SL
        movff FSR2H, I2C_SETPPS__SH
        lfsr 2, 0x201
        movf I2C_SETPPS__PIN, w, c
        addwf FSR2L, f, c
        movf I2C_SETPPS__CODE, w, c
        movwf INDF2, c
        movff I2C_SETPPS__SL, FSR2L
        movff I2C_SETPPS__SH, FSR2H
    End Asm
End Sub

' Empties everything a transfer leaves behind: the interrupt and error flags, both buffers, the acknowledge bits.
Sub Clean()
    I2C1PIR = 0
    I2C1ERR = 0
    I2C1STAT1 = 4
    I2C1CON1 = 0
End Sub

' Module off and on: the state machine starts from idle. Errata 1.3.2: Start and Stop flags may be set when the
' module is enabled; wait 250 ns + six instruction cycles (25 us covers a 1 MHz clock), then clear them.
Sub ModOn()
    I2C1CON0 = 0
    I2C1CON0 = 132
    DelayUS(25)
    Clean()
End Sub

' Waits (bounded) for one thing the module does: what = 1 the transmit buffer is empty, 2 the module waits for
' the Restart (MDR), 3 a byte was received, 4 the transfer is over (MMA = 0), anything else the transfer is over or the
' module waits for a Restart (MMA = 0 or MDR = 1). Returns 0 when it happened, 1 on a timeout, 2 on a bus collision,
' 3 when a byte was not acknowledged (only looked for when `nack` is True: the module's own not acknowledge of the last
' received byte sets NACKIF too, so received data wins over NACKIF).
' The errors are read after the condition on purpose: a collision clears MMA and sets BCLIF at the same instant, and a
' not acknowledge sets NACKIF and MDR together, so an error that came with the condition would be missed if it were
' looked at first. A byte written to TXB after a missed collision would start a new transfer (ABD = 1).
Function Wait(ByVal what As Byte, ByVal nack As Boolean) As Byte
    Dim n As Word
    n = 0
    Result = 1
    While Result = 1 And n < 20000
        Result = 0
        If what = 1 Then
            If BitTxbe = 0 Then
                Result = 1
            End If
        ElseIf what = 2 Then
            If BitMdr = 0 Then
                Result = 1
            End If
        ElseIf what = 3 Then
            If BitRxbf = 0 Then
                Result = 1
            End If
        ElseIf what = 4 Then
            If BitMma = 1 Then
                Result = 1
            End If
        ElseIf BitMma = 1 And BitMdr = 0 Then
            Result = 1
        End If
        If FlagBcl = 1 Then
            Result = 2
        ElseIf nack And FlagNack = 1 And (what <> 3 Or BitRxbf = 0) Then
            ' Waiting for a byte, RXBF is read again here: the byte (RXBF, 8th clock) and the module's own not
            ' acknowledge of it (NACKIF, 9th) can both land between the read above and this one.
            Result = 3
        End If
        If Result = 1 Then
            Inc(n)
        End If
    Wend
End Function

' A transfer went wrong or did not finish: Stop (P), then the module is reset. The bus may stay held by a client.
Sub Recover()
    Dim n As Word
    If BitMma = 1 Then
        BitP = 1
        n = 0
        While BitMma = 1 And n < 20000
            Inc(n)
        Wend
    End If
    ModOn()
End Sub

' Ends a transfer. `res` is what the last Wait returned. On success or a not acknowledge the module sends the Stop
' itself (RSEN = 0 and the count is 0), except for a not acknowledge while RSEN = 1 (the register phase of a read): the
' module then pauses (MDR) and the Stop is forced with P. A not acknowledge needs no more (the module is idle and the next
' transfer empties the buffers); anything else is recovered. `acks` is True when a NACKIF at the end means a byte was not
' acknowledged (writes), False for a read, where the last byte is not acknowledged on purpose.
' Sets I2cStatus and returns the status.
Function Finish(ByVal res As Byte, ByVal acks As Boolean) As Byte
    Dim w As Byte
    Result = res
    If res = 0 Or res = 3 Then
        w = Wait(6, False)
        If w = 0 And BitMdr = 1 Then
            BitP = 1
            w = Wait(4, False)
        End If
        If w <> 0 Then
            Result = w
        ElseIf Result = 0 And acks And FlagNack = 1 Then
            Result = 3
        End If
    End If
    If Result <> 0 And Result <> 3 Then
        Recover()
    End If
    lastStatus = Result
End Function

' Takes the pins of the last I2cInit away from the module: RxyPPS back to LATxy and ODCONx cleared (push-pull). They stay digital and
' TRISx is as I2cInit left it (input), so they float until the program drives them.
Sub Unroute()
    SetPps(sclPin, 0)
    SetPps(sdaPin, 0)
    PushPull(sclPin >> 3, 1 << (sclPin And 7))
    PushPull(sdaPin >> 3, 1 << (sdaPin And 7))
End Sub

' PPS must be unlocked (PPSLOCK, the reset state): with it locked the pin selections are ignored and every transfer times out.
' A second I2cInit on other pins needs I2cOff first. A byte written to TXB while the module is idle starts a transfer (ABD = 1), so MMA
' is checked just before each write; an interrupt that delays the write after that check can still let it through.
' Sets up I2C1 as a host at the highest clock that is at most `hz` (1..400000) with SCL on `scl` and SDA on `sda`
' (pins 0..23 as the part has them, RA3 refused, different). I2CxCLK is FOSC/4 and SCL = FOSC / (4 * 5 * (BAUD + 1)),
' so `Clock` must be FOSC in MHz and the slowest clock is FOSC / 5120 (12.5 kHz at 64 MHz). Returns 1, or 0 for a
' pin that is not allowed or an `hz` that no BAUD of 0..255 reaches.
Public Function I2cInit(ByVal hz As LongWord, ByVal scl As Byte, ByVal sda As Byte) As Byte
    Dim fclk As LongWord
    Dim stp As LongWord
    Dim acc As LongWord
    Dim d As Word
    Result = 0
    If Not PinGood(scl) Or Not PinGood(sda) Or scl = sda Or hz = 0 Or hz > 400000 Then
        Exit
    End If
    fclk = LongWord(_Clock * 250000)
    stp = LongWord(5) * hz
    acc = stp
    d = 1
    While acc < fclk And d < 257
        acc = acc + stp
        Inc(d)
    Wend
    If d > 256 Then
        Exit
    End If
    I2C1CON0 = 0
    sclPin = scl
    sdaPin = sda
    PinSetup(scl >> 3, 1 << (scl And 7))
    PinSetup(sda >> 3, 1 << (sda And 7))
    OpenDrain(scl >> 3, 1 << (scl And 7))
    OpenDrain(sda >> 3, 1 << (sda And 7))
    I2C1SCLPPS = scl
    I2C1SDAPPS = sda
    SetPps(scl, 33)
    SetPps(sda, 34)
    I2C1CLK = 0
    I2C1BAUD = Byte(d - 1)
    I2C1CON2 = 16
    ModOn()
    ready = True
    lastStatus = 0
    Result = 1
End Function

' Turns the module off and gives the pins of the last I2cInit back (`scl` and `sda` are not looked at: the module remembers
' its pins, so a call with other pins cannot disturb another peripheral's mapping).
Public Sub I2cOff(ByVal scl As Byte, ByVal sda As Byte)
    I2C1CON0 = 0
    If ready Then
        Unroute()
    End If
    ready = False
End Sub

' The status of the last transfer (codes in the header).
Public Function I2cStatus() As Byte
    Result = lastStatus
End Function

' True when a client answers (acknowledges) the 7-bit address `addr` (0..127) for writing: Start, address + W, Stop.
' Status: 0 acknowledged, 3 not acknowledged, 1 timeout, 2 bus collision, 4 not initialised.
Public Function I2cProbe(ByVal addr As Byte) As Byte
    Result = 4
    If Not ready Then
        lastStatus = Result
        Exit
    End If
    Clean()
    I2C1CNTL = 0
    I2C1CNTH = 0
    I2C1CON0 = 132
    I2C1TXB = addr << 1
    Result = Finish(Wait(1, True), True)
End Function

' Writes I2cBuf(0 .. n-1) (n 1..8) to the registers of the client at 7-bit address `addr`, from register `reg` on:
' Start, address + W, reg, the n bytes, Stop. Returns the status (5 when n is not 1..8: nothing is sent).
Public Function I2cWriteRegs(ByVal addr As Byte, ByVal reg As Byte, ByVal n As Byte) As Byte
    Dim i As Byte
    Result = 4
    If Not ready Then
        lastStatus = Result
        Exit
    End If
    If n = 0 Or n > 8 Then
        Result = 5
        lastStatus = Result
        Exit
    End If
    Clean()
    I2C1CNTL = n + 1
    I2C1CNTH = 0
    I2C1CON0 = 132
    I2C1TXB = addr << 1
    i = 0
    Result = 0
    While Result = 0 And i <= n
        Result = Wait(1, True)
        If Result = 0 And BitMma = 0 Then
            Result = 3
        End If
        If Result = 0 Then
            If i = 0 Then
                I2C1TXB = reg
            Else
                I2C1TXB = I2cBuf(i - 1)
            End If
            Inc(i)
        End If
    Wend
    Result = Finish(Result, True)
End Function

' Reads n bytes (1..8) into I2cBuf(0 .. n-1) from the registers of the client at 7-bit address `addr`, from
' register `reg` on: Start, address + W, reg, Restart, address + R, the n bytes (all acknowledged but the last), Stop.
' Returns the status (5 when n is not 1..8: nothing is sent).
Public Function I2cReadRegs(ByVal addr As Byte, ByVal reg As Byte, ByVal n As Byte) As Byte
    Dim i As Byte
    Result = 4
    If Not ready Then
        lastStatus = Result
        Exit
    End If
    If n = 0 Or n > 8 Then
        Result = 5
        lastStatus = Result
        Exit
    End If
    Clean()
    ' One byte (reg) after the address; RSEN = 1 makes the module wait for the Restart when the count reaches 0.
    I2C1CNTL = 1
    I2C1CNTH = 0
    I2C1CON0 = 196
    I2C1TXB = addr << 1
    Result = Wait(1, True)
    If Result = 0 And BitMma = 0 Then
        Result = 3
    End If
    If Result = 0 Then
        I2C1TXB = reg
        Result = Wait(1, True)
    End If
    If Result = 0 Then
        Result = Wait(2, True)
    End If
    ' Paused (MDR) with SCL low: load the number of bytes to read and the acknowledge for the last one, then write
    ' the read address, which is sent after a Restart; it has left TXB (TXBE = 1) once the Restart is done. RSEN then
    ' goes back to 0, so the Stop follows the last byte by itself (if it stayed 1 the module would pause after the last
    ' byte, and Finish sends the Stop with P).
    If Result = 0 Then
        I2C1CNTL = n
        I2C1CON1 = 128
        I2C1TXB = (addr << 1) Or 1
        Result = Wait(1, True)
    End If
    If Result = 0 Then
        I2C1CON0 = 132
    End If
    i = 0
    While Result = 0 And i < n
        Result = Wait(3, i = 0)
        If Result = 0 Then
            I2cBuf(i) = I2C1RXB
            Inc(i)
        End If
    Wend
    Result = Finish(Result, False)
End Function

' True when a client answers the 7-bit address `addr`.
Public Function I2cPing(ByVal addr As Byte) As Boolean
    Result = (I2cProbe(addr) = 0)
End Function

' Writes `value` to register `reg` of the client at 7-bit address `addr`. Returns the status.
Public Function I2cWriteReg(ByVal addr As Byte, ByVal reg As Byte, ByVal value As Byte) As Byte
    I2cBuf(0) = value
    Result = I2cWriteRegs(addr, reg, 1)
End Function

' Reads register `reg` of the client at 7-bit address `addr`. On an error it returns 0 and I2cStatus is not 0.
Public Function I2cReadReg(ByVal addr As Byte, ByVal reg As Byte) As Byte
    Dim s As Byte
    Result = 0
    s = I2cReadRegs(addr, reg, 1)
    If s = 0 Then
        Result = I2cBuf(0)
    End If
End Function
#endif

' PIC16F18056/76 (DS40002325C chapters 18 and 29; chosen with `Not _has(OSCCON1)`): the same MSSP1 host, `RxyPPS` 15h (21) = SCL1 and 16h (22) = SDA1 [Table 18-2 p.170], SSP1IF and BCL1IF in PIR3 bits 6 and 7 [12.10.10 p.111].
' The 28- and 40-pin parts route MSSP1 to port B or port C only [Tables 18-1 and 18-2 p.169-170], so the pins are numbered 8..23 as on the Q10 (RB0..RB7 = 8..15, RC0..RC7 = 16..23). The silicon errata (DS80001014D) list nothing for the MSSP.
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
#elseif Not _has(OSCCON1)
Dim FlagSsp As PIR3.6
Dim FlagBcl As PIR3.7
Const SclCode = 21
Const SdaCode = 22
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
#if _has(RB0PPS)
    ElseIf pin = 8 Then
        RB0PPS = code
    ElseIf pin = 9 Then
        RB1PPS = code
    ElseIf pin = 10 Then
        RB2PPS = code
    ElseIf pin = 11 Then
        RB3PPS = code
#endif
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
#if Not _has(OSCCON1) And Not _has(ADCON1.PREF)
    ' PIC16F18056/76: port B and C only (see the top).
    Result = pin >= 8 And pin <= 23
#else
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

#if Not _i2chw
' Block transfers over the routines above (the hardware host of the PIC18F0x/1xQ41 has only these, see the header).
Public Dim I2cBuf(8) As Byte

' Start, control byte `ctl`, register byte `reg`. Leaves the bus started.
Function Open(ByVal ctl As Byte, ByVal reg As Byte) As Byte
    Result = I2cStart()
    If Result = 0 Then
        Result = I2cSend(ctl)
    End If
    If Result = 0 Then
        Result = I2cSend(reg)
    End If
End Function

' Reads n bytes (1..8) into I2cBuf(0 .. n-1) from the registers of the client at 7-bit address `addr`, from
' register `reg` on: Start, address + W, reg, Restart, address + R, the n bytes (all acknowledged but the last),
' Stop. Returns the status of the first step that failed (the Stop is always attempted), 5 when n is not 1..8
' (nothing is sent).
Public Function I2cReadRegs(ByVal addr As Byte, ByVal reg As Byte, ByVal n As Byte) As Byte
    Dim i As Byte
    Dim s As Byte
    Result = 5
    If n = 0 Or n > 8 Then
        lastStatus = Result
        Exit
    End If
    Result = Open(addr << 1, reg)
    If Result = 0 Then
        Result = I2cRestart()
    End If
    If Result = 0 Then
        Result = I2cSend((addr << 1) Or 1)
    End If
    i = 0
    While Result = 0 And i < n
        I2cBuf(i) = I2cReceive(i < n - 1)
        Result = I2cStatus()
        Inc(i)
    Wend
    s = I2cStop()
    If Result = 0 Then
        Result = s
    End If
    lastStatus = Result
End Function

' Writes I2cBuf(0 .. n-1) (n 1..8) to the registers of the client at 7-bit address `addr`, from register `reg` on:
' Start, address + W, reg, the n bytes, Stop. Returns the status of the first step that failed (the Stop is always
' attempted), 5 when n is not 1..8 (nothing is sent).
Public Function I2cWriteRegs(ByVal addr As Byte, ByVal reg As Byte, ByVal n As Byte) As Byte
    Dim i As Byte
    Dim s As Byte
    Result = 5
    If n = 0 Or n > 8 Then
        lastStatus = Result
        Exit
    End If
    Result = Open(addr << 1, reg)
    i = 0
    While Result = 0 And i < n
        Result = I2cSend(I2cBuf(i))
        Inc(i)
    Wend
    s = I2cStop()
    If Result = 0 Then
        Result = s
    End If
    lastStatus = Result
End Function

' Start, address + W, Stop. 0 when the client at 7-bit address `addr` acknowledged, 3 when it did not, 1 timeout,
' 2 bus collision, 4 not initialised (the status of the Stop is not looked at).
Public Function I2cProbe(ByVal addr As Byte) As Byte
    Result = I2cStart()
    If Result = 0 Then
        Result = I2cSend(addr << 1)
    End If
    I2cStop()
    lastStatus = Result
End Function

' True when a client answers (acknowledges) the 7-bit address `addr` (0..127) for writing.
Public Function I2cPing(ByVal addr As Byte) As Boolean
    Result = (I2cProbe(addr) = 0)
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
#endif
