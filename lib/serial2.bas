Module Serial2
' EUSART2 in asynchronous 8N1 mode, TX on RB6 and RX on RB7 (DS40002043F, chapter 29, and the
' PPS chapter 18). The pins are routed through PPS: RB6PPS = 0x0B selects EUSART2 TX/CK [Table 18-2];
' RX2PPS = 0x0F selects RB7 as the input (port B = 01b, pin 7) [Table 18-1, p.292]. RB6 and RB7 are
' also the ICSP clock and data pins, so disconnect a programmer or debugger while using them.
' EUSART1 (module `Serial`) can be used at the same time.
'
' PIC18F0x/1xQ41 (DS40002214G, chapters 21 and 34): UART2 (U2CON0/1/2, U2BRG, U2TXB, U2RXB, U2FIFO), TX on RC2
' and RX on RC1, both on the 14-pin parts too. RC2PPS = 0x13 selects UART2 TX [Table 21-2]; U2RXPPS = PORT[5:3] |
' PIN[2:0], RC1 = 010 001 = 17 [21.8.1] (the reset selection of U2RXPPS, Table 21-1). RC1 and RC2 are also the default
' SPI1 data in and I2C1 data pins of the 14-pin parts: route them elsewhere if both modules are used. Set-up and
' flags as in module `Serial` (the buffer status bits of U2FIFO and TXMTIF of U2ERRIR).
'
' PIC16F17126/46 (DS40002343F, chapters 18 and 32): EUSART2 with TX on RC2 and RX on RC1, both on the 14-pin part too.
' RC2PPS = 0x16 selects TX2/CK2 [Table 18-2]; RX2PPS = PORT[5:3] | PIN[2:0], RC1 = 010 001 = 17 [18.8.1, the reset
' selection of RX2PPS, Table 18-1]. TX2IF and RC2IF are PIR5 bits 0 and 1. The registers and the baud-rate formula are
' those of EUSART1.
'
' PIC16F13214/15/24/25/44/45 (DS40002686B, chapters 18 and 31): the same EUSART2 as the PIC16F17126/46, with the same codes (TX2/CK2 = 0x16 [Table 18-2 p.207];
' TX2IF and RC2IF are PIR5 bits 0 and 1). RC2 and RC1 on the 14- and 20-pin parts; the 8-pin parts have port A only, so TX2 is RA2 and RX2 is RA1.
' PIC16F18056/76 (DS40002325C, chapters 18 and 30; chosen with `Not _has(OSCCON1)`): EUSART2 with TX on RB6 and RX on RB7, the Reset selections of CK2PPS and RX2PPS [Table 18-1 p.169]; both
' PPS tables allow port B on the 28- and the 40-pin part (the second port is C on the 28-pin and D on the 40-pin part). RB6PPS = 11h selects TX2/CK2 [Table 18-2 p.170]; RX2PPS = PORT[5:3] | PIN[2:0],
' RB7 = 001 111 = 15 [18.8.1 p.173]. TX2IF and RC2IF are PIR3 bits 4 and 5 [PIR3, p.111]. RB6 and RB7 are also the ICSP clock and data pins. The registers and the baud-rate formula are those of EUSART1.
'
' PIC16F153xx (DS40001889E, DS40001865F, DS40001853E and DS40001866E, chapter 31; chosen with `_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)`; the PIC16F15313/23 have one EUSART only): EUSART2 with TX on RC2 and RX on RC1. RC2PPS = 11h selects TX2/CK2
' [Table 15-4 p.199]; RX2DTPPS = PORT[5:3] | PIN[2:0], RC1 = 010 001 = 17 [Table 15-1 p.195 gives it as the reset selection]. TX2IF and RC2IF are PIR3 bits 6 and 7. Erratum 5.1 of DS80000725F (the
' PIC16(L)F15356/75/76/85/86): SerialWriteByte's twin waits for TRMT there. The registers and the baud-rate formula are those of EUSART1.
'
' Baud rate: BRG16 = 1 and BRGH = 1 give baud = FOSC / (4 * (n + 1)) [Table 29-1, TXxSTA BRGH];
' n is SP2BRGH:SP2BRGL. The result is rounded to the nearest n. `Clock` must be FOSC in MHz.
' An internal oscillator drifts with voltage and temperature [29.1.3], which shifts the baud rate.
#if Not _has(U2CON0) And Not _has(TX2STA)
#error "serial2 needs a second EUSART: the PIC16F13145 family, the PIC16F183xx parts, the PIC16F152xx parts and the PIC16F153xx parts except the PIC16(L)F15313/23 have one (DS40002519D Table 1 p.1; DS40001799F Family Types table p.3; DS40002195E Table 1 p.1; DS40001897C Table 1 p.3); use module Serial"
#endif
#if _has(U2CON0)
Dim TxFull As U2FIFO.4
Dim TxBufEmpty As U2FIFO.5
Dim RxEmpty As U2FIFO.1
Dim TxShiftEmpty As U2ERRIR.7
Dim OverrunErr As U2ERRIR.1
Dim TxPin As TRISC.2
Dim RxPin As TRISC.1
Dim TxAnalog As ANSELC.2
Dim RxAnalog As ANSELC.1
#elseif Not _has(OSCCON1)
Dim TxIf As PIR3.4
Dim RxIf As PIR3.5
Dim OverrunErr As RC2STA.1
Dim RxEnable As RC2STA.4
Dim TxPin As TRISB.6
Dim RxPin As TRISB.7
Dim RxAnalog As ANSELB.7
#elseif _has(PRODL)
Dim TxIf As PIR3.6
Dim RxIf As PIR3.7
Dim OverrunErr As RC2STA.1
Dim RxEnable As RC2STA.4
Dim TxPin As TRISB.6
Dim RxPin As TRISB.7
Dim RxAnalog As ANSELB.7
#elseif _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)
Dim TxIf As PIR3.6
Dim RxIf As PIR3.7
Dim OverrunErr As RC2STA.1
Dim RxEnable As RC2STA.4
Dim TxPin As TRISC.2
Dim RxPin As TRISC.1
Dim RxAnalog As ANSELC.1
#else
Dim TxIf As PIR5.0
Dim RxIf As PIR5.1
Dim OverrunErr As RC2STA.1
Dim RxEnable As RC2STA.4
#if _has(TRISC)
Dim TxPin As TRISC.2
Dim RxPin As TRISC.1
Dim RxAnalog As ANSELC.1
#else
' The 8-pin parts (PIC16F13214/13215) have port A only: TX2 on RA2, RX2 on RA1 (the reset selection of RX2PPS on an 8-pin part,
' DS40002686B Table 18-1 p.206), clear of the RA4 / RA5 pair of module Serial.
Dim TxPin As TRISA.2
Dim RxPin As TRISA.1
Dim RxAnalog As ANSELA.1
#endif
#endif
Public Const FoscHz = LongWord(_Clock * 1000000)

Public Sub Serial2Init(ByVal baud As LongWord)
    Dim n As LongWord
    n = (FoscHz + baud * 2) / (baud * 4) - 1
    RxAnalog = 0
    RxPin = 1
    TxPin = 0
#if _has(U2CON0)
    TxAnalog = 0
    RC2PPS = 19
    U2RXPPS = 17
    U2BRGL = Byte(n)
    U2BRGH = Byte(n >> 8)
    U2CON0 = 176
    U2CON2 = 128
    U2CON1 = 128
#elseif Not _has(OSCCON1)
    RB6PPS = 17
    RX2PPS = 15
    SP2BRGL = Byte(n)
    SP2BRGH = Byte(n >> 8)
    BAUD2CON = 8
    TX2STA = 36
    RC2STA = 144
#elseif _has(PRODL)
    RB6PPS = 11
    RX2PPS = 15
    SP2BRGL = Byte(n)
    SP2BRGH = Byte(n >> 8)
    BAUD2CON = 8
    TX2STA = 36
    RC2STA = 144
#elseif _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)
    ' RxyPPS 11h is TX2/CK2 [DS40001889E Table 15-4 p.199]; RX2DTPPS = PORT[5:3] | PIN[2:0], RC1 = 010 001 = 17 (its reset selection, Table 15-1 p.195).
    RC2PPS = 17
    RX2DTPPS = 17
    SP2BRGL = Byte(n)
    SP2BRGH = Byte(n >> 8)
    BAUD2CON = 8
    TX2STA = 36
    RC2STA = 144
#else
#if _has(TRISC)
    RC2PPS = 22
    RX2PPS = 17
#else
    RA2PPS = 22
    RX2PPS = 1
#endif
    SP2BRGL = Byte(n)
    SP2BRGH = Byte(n >> 8)
    BAUD2CON = 8
    TX2STA = 36
    RC2STA = 144
#endif
End Sub

' Sends one byte, waiting for the transmit register to be free.
Public Sub Serial2WriteByte(ByVal b As Byte)
#if _has(U2CON0)
    While TxFull = 1
    Wend
    U2TXB = b
#elseif _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF) And (_device = 16F15356 Or _device = 16F15375 Or _device = 16F15376 Or _device = 16F15385 Or _device = 16F15386 Or _device = 16LF15356 Or _device = 16LF15375 Or _device = 16LF15376 Or _device = 16LF15385 Or _device = 16LF15386)
    ' Erratum 5.1 (DS80000725F, silicon A1 and A2; the same EUSART as EUSART1): write only when the shift register is empty (TRMT, TX2STA bit 1).
    While TX2STA.1 = 0
    Wend
    TX2REG = b
#else
    While TxIf = 0
    Wend
    TX2REG = b
#endif
End Sub

Public Sub Serial2Write(ByRefConst s As String(80))
    Dim i As Byte
    i = 0
    While s(i) <> #0
        Serial2WriteByte(Byte(s(i)))
        Inc(i)
    Wend
End Sub

Public Sub Serial2NewLine()
    Serial2WriteByte(13)
    Serial2WriteByte(10)
End Sub

' Unsigned decimal, no leading zeros. Each digit is found by subtracting the power of ten, so no divide routine is linked.
Const Pow10(4) As Word = (10000, 1000, 100, 10)
Public Sub Serial2WriteWord(ByVal v As Word)
    Dim started As Boolean
    Dim k As Byte
    Dim digit As Byte
    Dim d As Word
    started = False
    For k = 0 To 3
        d = Pow10(k)
        digit = 48
        While v >= d
            v = v - d
            Inc(digit)
        Wend
        If digit > 48 Or started Then
            Serial2WriteByte(digit)
            started = True
        End If
    Next
    Serial2WriteByte(48 + Byte(v))
End Sub

Public Sub Serial2WriteHex(ByVal v As Byte)
    Dim h As Byte
    Dim i As Byte
    For i = 0 To 1
        h = v >> 4
        v = v << 4
        If h > 9 Then
            h = h + 7
        End If
        Serial2WriteByte(48 + h)
    Next
End Sub

' True when a received byte is waiting.
Public Function Serial2Available() As Boolean
#if _has(U2CON0)
    Result = RxEmpty = 0
#else
    Result = RxIf = 1
#endif
End Function

' Waits for a byte. An overrun stops the receiver until CREN is cycled, so it is cleared here.
Public Function Serial2Read() As Byte
#if _has(U2CON0)
    While RxEmpty = 1
        If OverrunErr = 1 Then
            OverrunErr = 0
        End If
    Wend
    Result = U2RXB
#else
    While RxIf = 0
        If OverrunErr = 1 Then
            RxEnable = 0
            RxEnable = 1
        End If
    Wend
    Result = RC2REG
#endif
End Function

' ---- Receiving with a time limit ----------------------------------------------------------------------
' None of these waits for ever: `ms` is the longest wait for ONE byte, in milliseconds (a little over, as the
' wait is a poll every 50 us). A byte that is already waiting is returned at once, so a timeout of 0 only looks once.

' The byte Wait2 found.
Private Dim RxByte As Byte

' Waits up to `ms` for a byte and leaves it in RxByte: True when one came. The other routines use this one
' (fixed variables, so no pointers as a ByRef parameter would need). An overrun is cleared as Serial2Read does.
Private Function Wait2(ByVal ms As Word) As Boolean
    Dim t As Byte
    t = 0
    While True
#if _has(U2CON0)
        If RxEmpty = 0 Then
            RxByte = U2RXB
            Result = True
            Exit
        End If
        If OverrunErr = 1 Then
            OverrunErr = 0
        End If
#else
        If RxIf = 1 Then
            RxByte = RC2REG
            Result = True
            Exit
        End If
        If OverrunErr = 1 Then
            RxEnable = 0
            RxEnable = 1
        End If
#endif
        If ms = 0 Then
            Exit
        End If
        DelayUs(50)
        Inc(t)
        If t = 20 Then
            t = 0
            Dec(ms)
        End If
    Wend
End Function

' Waits up to `ms` for a byte: the byte (0 to 255), or -1 when none came.
Public Function Serial2ReadTimeout(ByVal ms As Word) As Integer
    If Wait2(ms) Then
        Result = RxByte
    Else
        Result = -1
    End If
End Function

' The text of the last Serial2ReadLine: up to 63 characters, no CR or LF, ended with a Null.
Public Dim Serial2Line As String(63)

' Reads one line into Serial2Line: True when it ended with CR or LF, False when `ms` passed without a byte (what had
' arrived stays in Serial2Line). Empty lines are skipped, so CR LF is one end of line; characters past 63 are dropped.
Public Function Serial2ReadLine(ByVal ms As Word) As Boolean
    Dim n As Byte
    n = 0
    Serial2Line(0) = Char(0)
    While Wait2(ms)
        If RxByte = 13 Or RxByte = 10 Then
            If n > 0 Then
                Result = True
                Exit
            End If
        ElseIf n < 63 Then
            Serial2Line(n) = Char(RxByte)
            Inc(n)
            Serial2Line(n) = Char(0)
        End If
    Wend
End Function

' Reads until the text `t` (not empty) has arrived, up to `ms` between bytes: True when it has, False on a timeout.
' A mismatch starts the match again at the first character, so a text whose start repeats inside itself
' ("aab" in "aaab") can be missed.
Public Function Serial2WaitFor(ByRefConst t As String(80), ByVal ms As Word) As Boolean
    Dim k As Byte
    k = 0
    While Wait2(ms)
        If RxByte <> Byte(t(k)) Then
            k = 0
        End If
        If RxByte = Byte(t(k)) Then
            Inc(k)
            If t(k) = Char(0) Then
                Result = True
                Exit
            End If
        End If
    Wend
End Function

' The number of the last Serial2ReadDec.
Public Dim Serial2Number As LongInt

' Reads a whole number written in decimal into Serial2Number: characters before the first digit are skipped (a "-"
' right before it makes it negative); the number ends at the first other character, which is read and dropped, or
' at a timeout after at least one digit. False (and 0) when no digit came; a value past 32 bits wraps.
Public Function Serial2ReadDec(ByVal ms As Word) As Boolean
    Dim d As Byte
    Dim neg As Boolean
    neg = False
    Serial2Number = 0
    While Wait2(ms)
        d = RxByte - 48
        If d < 10 Then
            Serial2Number = Serial2Number * 10 + d
            Result = True
        ElseIf Result Then
            Break
        Else
            neg = RxByte = 45
        End If
    Wend
    If neg Then
        Serial2Number = 0 - Serial2Number
    End If
End Function

' Waits until the last byte has left the shift register (TRMT, TX2STA bit 1).
Public Sub Serial2Flush()
#if _has(U2CON0)
    While TxBufEmpty = 0 Or TxShiftEmpty = 0
    Wend
#else
    While TX2STA.1 = 0
    Wend
#endif
End Sub
