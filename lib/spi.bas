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
Dim BitWcol As SSP1CON1.7
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
    If sck < 8 Or sck > 23 Or sdi < 8 Or sdi > 23 Or sck = sdi Then
        Exit
    End If
    If sdo <> 255 Then
        If sdo < 8 Or sdo > 23 Or sdo = sck Or sdo = sdi Then
            Exit
        End If
    End If
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
    SetPps(sck, 15)
    If sdo <> 255 Then
        PinSetup(sdo, False)
        SetPps(sdo, 16)
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
    If sck >= 8 And sck <= 23 Then
        SetPps(sck, 0)
    End If
    If sdo >= 8 And sdo <= 23 Then
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
