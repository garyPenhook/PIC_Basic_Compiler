Module Spi
' SPI host (master) on MSSP1, DS40002043F chapter 28. SCK, SDO and SDI go to pins of ports B and C
' (pin numbers 8..23: RB0..RB7 = 8..15, RC0..RC7 = 16..23, as the Adc channels) [Table 18-1, 18-2].
' SDO can be 255 for a receive-only host. The chip select is not part of the module: drive it with
' the Gpio routines or a port bit. `Clock` must be FOSC in MHz.
'
' Clock: SpiInit(hz, ...) gives FOSC / 4 for `hz` of FOSC / 4 or more (SSPM = 0000), otherwise
' FOSC / (4 * (SSPxADD + 1)) with SSPxADD 1..255 (SSPM = 1010; SSPxADD = 0 is not supported
' [28.9.2]), rounded so the clock is at or below `hz`. The lowest clock is FOSC / 1024.
' Modes (CPOL, CPHA): 0 = idle low, data changes on the falling edge (CKP = 0, CKE = 1); 1 = CKP 0,
' CKE 0; 2 = CKP 1, CKE 1; 3 = CKP 1, CKE 0. CKP is the idle level of SCK and CKE = 1 transmits on
' the active to idle transition [28.9.1, 28.9.2]. The input is sampled in the middle of the data
' output time (SMP = 0).
'
' A byte is exchanged by writing SSPxBUF [28.2.1]; the wait for the received byte (BF) is bounded, so
' a module that does not run cannot hang the program: SpiStatus is 1 after a timeout.
' The module is not reentrant, and does not use the MSSP1 interrupt. It owns MSSP1: do not use the
' `I2c` module at the same time.
'
' PIC18F0x/1xQ41 (DS40002214G, chapters 21 and 35; chosen with `#if _has(SPI1CON0)`): SPI1 as host. Pins are
' numbered 0..23 (RA0..RA7 = 0..7, RB0..RB7 = 8..15, RC0..RC7 = 16..23; the Q41 has RA0..RA5, RB4..RB7 on the
' 20-pin parts, and RC0..RC7; RA3 is input only), any of them through PPS: SCK = RxyPPS 0x1B and SDO = 0x1C
' [Table 21-2], SDI and SCK inputs through SPI1SDIPPS / SPI1SCKPPS = the pin number [21.8.1]. The clock is
' FOSC / (2 * (SPI1BAUD + 1)) [35.7.5], SPI1BAUD 0..255, so FOSC / 2 .. FOSC / 512, at most 10 MHz (full duplex,
' TSCK 95 ns [Table 48-21]). A byte is exchanged in BMODE = 1 with TWIDTH = 0 (8 bits) and TXR = RXR = 1: writing
' SPI1TXB starts the transfer [35.3.1], and SPI1RXIF (PIR3 bit 0, read only) is set while the receive FIFO holds
' data [35.6.1]. CKP = idle level of SCK, CKE = 1 for modes 0 and 2, SMP = 0 (sampled mid-bit) [35.7.2].
'
' PIC16F17126/46 (DS40002343F chapters 18 and 31; chosen with `Not _has(PRODL)`): the same MSSP1 host as the Q10 below, with the pins of the
' Q41 branch: numbered 0..23, RA0..RA5 except RA3 (input only: allowed for SDI, refused for SCK and SDO), RB4..RB7 (20-pin part), RC0..RC7,
' through PPS with SCK1 = RxyPPS 27 and SDO1 = 28 [Table 18-2]; SSP1CLKPPS and SSP1DATPPS take the pin number [Table 18-1].
#if _has(SPI1CON0) Or Not _has(PRODL)
Dim ready As Boolean
Dim lastStatus As Byte

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
    End If
End Sub

' True for a pin the part has: RA0..RA5, RB4..RB7 (20-pin parts), RC0..RC7 (RC6, RC7 on the 20-pin parts).
Function PinOk(ByVal pin As Byte) As Boolean
    Result = pin <= 5 Or (pin >= 16 And pin <= 21)
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

' Makes pin 0..23 a digital input (asInput) or output.
Sub PinSetup(ByVal pin As Byte, ByVal asInput As Boolean)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 8 Then
        ANSELA = ANSELA And (m Xor 255)
        If asInput Then
            TRISA = TRISA Or m
        Else
            TRISA = TRISA And (m Xor 255)
        End If
#if _has(TRISB)
    ElseIf pin < 16 Then
        ANSELB = ANSELB And (m Xor 255)
        If asInput Then
            TRISB = TRISB Or m
        Else
            TRISB = TRISB And (m Xor 255)
        End If
#endif
    Else
        ANSELC = ANSELC And (m Xor 255)
        If asInput Then
            TRISC = TRISC Or m
        Else
            TRISC = TRISC And (m Xor 255)
        End If
    End If
End Sub
#endif

#if _has(SPI1CON0)
Dim RxIf As PIR3.0

' Sets up SPI1 as a host at about `hz` (1..10000000) in mode 0..3 with SCK on `sck`, data out on `sdo`
' (255 = none) and data in on `sdi`. Returns 1, or 0 for a bad pin, a pin used twice, a mode above 3, or a
' clock below FOSC / 512. Use SpiOff before changing pins.
Public Function SpiInit(ByVal hz As LongWord, ByVal mode As Byte, ByVal sck As Byte, ByVal sdo As Byte, ByVal sdi As Byte) As Byte
    Dim fosc As LongWord
    Dim d As LongWord
    Result = 0
    If mode > 3 Or hz = 0 Or hz > 10000000 Then
        Exit
    End If
    If Not PinOk(sck) Or Not PinOk(sdi) Or sck = sdi Or sck = 3 Then
        Exit
    End If
    If sdo <> 255 Then
        If Not PinOk(sdo) Or sdo = sck Or sdo = sdi Or sdo = 3 Then
            Exit
        End If
    End If
    fosc = LongWord(_Clock * 1000000)
    ' SPI1BAUD = ceil(FOSC / (2 * hz)) - 1
    d = (fosc + LongWord(2) * hz - 1) / (LongWord(2) * hz) - 1
    If d > 255 Then
        Exit
    End If
    SPI1CON0 = 0
    PinSetup(sck, False)
    PinSetup(sdi, True)
    SPI1SCKPPS = sck
    SPI1SDIPPS = sdi
    SetPps(sck, 27)
    If sdo <> 255 Then
        PinSetup(sdo, False)
        SetPps(sdo, 28)
    End If
    SPI1CLK = 0
    SPI1BAUD = Byte(d)
    ' CKP (bit 5) = idle level, CKE (bit 6) = 1 for modes 0 and 2, SMP = 0, SSP (bit 2) left at its reset value.
    If mode >= 2 Then
        SPI1CON1 = 36
    Else
        SPI1CON1 = 4
    End If
    If (mode And 1) = 0 Then
        SPI1CON1 = SPI1CON1 Or 64
    End If
    SPI1TWIDTH = 0
    SPI1CON2 = 3
    SPI1CON0 = 131
    ready = True
    lastStatus = 0
    Result = 1
End Function

' Disables SPI1 and gives the pins back to their LATxy bits (pins as given to SpiInit).
Public Sub SpiOff(ByVal sck As Byte, ByVal sdo As Byte)
    SPI1CON0 = 0
    If PinOk(sck) Then
        SetPps(sck, 0)
    End If
    If PinOk(sdo) Then
        SetPps(sdo, 0)
    End If
    ready = False
End Sub

' 0 after the last transfer completed, 1 after a timeout, 4 when not initialised.
Public Function SpiStatus() As Byte
    Result = lastStatus
End Function

' Sends one byte and returns the byte received at the same time (0 on an error, see SpiStatus).
Public Function SpiTransfer(ByVal b As Byte) As Byte
    Dim n As Word
    Result = 0
    lastStatus = 4
    If Not ready Then
        Exit
    End If
    SPI1TXB = b
    lastStatus = 1
    n = 0
    While n < 60000
        If RxIf = 1 Then
            Result = SPI1RXB
            lastStatus = 0
            Exit
        End If
        Inc(n)
    Wend
End Function

' Sends one byte and ignores the byte received.
Public Sub SpiWrite(ByVal b As Byte)
    Dim r As Byte
    r = SpiTransfer(b)
End Sub

' Receives one byte (sends 255 on SDO).
Public Function SpiRead() As Byte
    Result = SpiTransfer(255)
End Function
#else
Dim BitWcol As SSP1CON1.7
#if _has(PRODL)
Dim ready As Boolean
Dim lastStatus As Byte

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

' Makes pin 8..23 a digital input (asInput) or output.
Sub PinSetup(ByVal pin As Byte, ByVal asInput As Boolean)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 16 Then
        ANSELB = ANSELB And (m Xor 255)
        If asInput Then
            TRISB = TRISB Or m
        Else
            TRISB = TRISB And (m Xor 255)
        End If
    Else
        ANSELC = ANSELC And (m Xor 255)
        If asInput Then
            TRISC = TRISC Or m
        Else
            TRISC = TRISC And (m Xor 255)
        End If
    End If
End Sub
#endif

' Sets up MSSP1 as an SPI host at about `hz` (1..16000000) in mode 0..3 with SCK on `sck`, data out
' on `sdo` (255 = none) and data in on `sdi`. Returns 1, or 0 for a bad pin, a pin used twice, a
' mode above 3, or a clock below FOSC / 1024. Use SpiOff before changing pins.
Public Function SpiInit(ByVal hz As LongWord, ByVal mode As Byte, ByVal sck As Byte, ByVal sdo As Byte, ByVal sdi As Byte) As Byte
    Dim fosc As LongWord
    Dim d As LongWord
    Dim con As Byte
    Result = 0
    If mode > 3 Or hz = 0 Or hz > 16000000 Then
        Exit
    End If
#if _has(PRODL)
    If sck < 8 Or sck > 23 Or sdi < 8 Or sdi > 23 Or sck = sdi Then
        Exit
    End If
    If sdo <> 255 Then
        If sdo < 8 Or sdo > 23 Or sdo = sck Or sdo = sdi Then
            Exit
        End If
    End If
#else
    If Not PinOk(sck) Or Not PinOk(sdi) Or sck = sdi Or sck = 3 Then
        Exit
    End If
    If sdo <> 255 Then
        If Not PinOk(sdo) Or sdo = sck Or sdo = sdi Or sdo = 3 Then
            Exit
        End If
    End If
#endif
    fosc = LongWord(_Clock * 1000000)
    ' SSPxADD = ceil(FOSC / (4 * hz)) - 1; 0 means FOSC / 4.
    d = (fosc + LongWord(4) * hz - 1) / (LongWord(4) * hz) - 1
    If d > 255 Then
        Exit
    End If
    SSP1CON1 = 0
    PinSetup(sck, False)
    PinSetup(sdi, True)
    SSP1CLKPPS = sck
    SSP1DATPPS = sdi
#if _has(PRODL)
    SetPps(sck, 15)
#else
    SetPps(sck, 27)
#endif
    If sdo <> 255 Then
        PinSetup(sdo, False)
#if _has(PRODL)
        SetPps(sdo, 16)
#else
        SetPps(sdo, 28)
#endif
    End If
    If d = 0 Then
        con = 0
    Else
        SSP1ADD = Byte(d)
        con = 10
    End If
    If mode >= 2 Then
        con = con Or 16
    End If
    SSP1STAT = 0
    If (mode And 1) = 0 Then
        SSP1STAT = 64
    End If
    SSP1CON3 = 0
    SSP1CON1 = con
    SSP1CON1 = con Or 32
    ready = True
    lastStatus = 0
    Result = 1
End Function

' Disables the MSSP and gives the pins back to their LATxy bits (pins as given to SpiInit).
Public Sub SpiOff(ByVal sck As Byte, ByVal sdo As Byte)
    SSP1CON1 = 0
#if _has(PRODL)
    If sck >= 8 And sck <= 23 Then
        SetPps(sck, 0)
    End If
    If sdo >= 8 And sdo <= 23 Then
        SetPps(sdo, 0)
    End If
#else
    If PinOk(sck) Then
        SetPps(sck, 0)
    End If
    If PinOk(sdo) Then
        SetPps(sdo, 0)
    End If
#endif
    ready = False
End Sub

' 0 after the last transfer completed, 1 after a timeout, 4 when not initialised.
Public Function SpiStatus() As Byte
    Result = lastStatus
End Function

' Sends one byte and returns the byte received at the same time (0 on an error, see SpiStatus).
Public Function SpiTransfer(ByVal b As Byte) As Byte
    Dim n As Word
    Result = 0
    lastStatus = 4
    If Not ready Then
        Exit
    End If
    BitWcol = 0
    SSP1BUF = b
    lastStatus = 1
    n = 0
    While n < 60000
        If (SSP1STAT And 1) = 1 Then
            Result = SSP1BUF
            lastStatus = 0
            Exit
        End If
        Inc(n)
    Wend
End Function

' Sends one byte and ignores the byte received.
Public Sub SpiWrite(ByVal b As Byte)
    Dim r As Byte
    r = SpiTransfer(b)
End Sub

' Receives one byte (sends 255 on SDO).
Public Function SpiRead() As Byte
    Result = SpiTransfer(255)
End Function
#endif
