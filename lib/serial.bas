Module Serial
' EUSART1 in asynchronous 8N1 mode, TX on RC6 and RX on RC7 (DS40002043F, chapter 29, and the
' PPS chapter 18). The pins are routed through PPS: RC6PPS = 0x09 selects EUSART1 TX [Table 18-2];
' RX1PPS = 0x17 selects RC7 as the input (port C = 10b, pin 7) [p.285, p.292].
' PIC16F17126/46 (DS40002343F, chapters 18 and 32): TX on RC4 and RX on RC5, which exist on the 14-pin part too.
' RC4PPS = 0x13 selects TX1/CK1 [Table 18-2]; RX1PPS = PORT[5:3] | PIN[2:0], RC5 = 010 101 = 21 [18.8.1].
' The EUSART1 registers and the baud-rate formula are the same on both families.
' PIC16F13145 family (DS40002519D, chapters 18 and 31): the same EUSART1 and codes (TX1/CK1 = 0x13 [Table 18-2 p.188]); TX RC4 and
' RX RC5 on the 14- and 20-pin parts, RA4 and RA5 on the 8-pin PIC16F13113 (port A only).
' PIC16F183xx (DS40001799F, DS40001800E, DS40001795K, DS40001839E; chosen with `#if _has(ADCON0.CHS)`): the same EUSART1 registers; TXIF and RCIF
' are PIR1 bits 4 and 5. TX goes out through RC4PPS = 14h (TX/CK) [Register 13-2] and RXPPS = PORT[4:3] | PIN[2:0] selects RX [Register 13-1];
' RC4 and RC5 on the 14- and 20-pin parts, RA4 and RA5 on the 8-pin PIC16F18313 (port A only). An enabled receiver (SPEN) with TXEN = 0 drives
' the TX pin low on the PIC16F18313/18323 silicon A3 only (DS80000666H item 2.1, not the current revision A6).
' PIC16F152xx (DS40002195E, chapters 18 and 24; chosen with `#if _has(ADCON1.PREF)`): the same EUSART1 registers; TX1IF and RC1IF are PIR1 bits 3 and 4 [12.9.6]. TX goes out through
' RxyPPS = 05h (TX1/CK1) [Table 18-2 p.148] and RX1PPS = PORT[5:3] | PIN[2:0] selects RX [18.8.1]; RC4 and RC5 on the 14- and 20-pin parts, RA4 and RA5 on the 8-pin PIC16F15213/14 (port A only).
' Silicon erratum 1.3.1 (DS80000918K, all revisions): a byte written to TX1REG just as the shift register empties can be sent twice. SerialWriteByte therefore waits for TRMT (the shift
' register empty, workaround method 2) instead of TXIF; characters still go out back to back, as the byte is written within a few cycles of the stop bit.
' PIC18F0x/1xQ41 (DS40002214G, chapters 21 and 34): UART1 (U1CON0/1/2, U1BRG, U1TXB, U1RXB, U1FIFO), TX on RC4
' and RX on RC5, which exist on the 14-pin parts too. RC4PPS = 0x10 selects UART1 TX [Table 21-2]; U1RXPPS =
' PORT[5:3] | PIN[2:0], RC5 = 010 101 = 21 [21.8.1]. The UART has a transmit and a receive buffer, so the
' flags used are the buffer status bits of U1FIFO (TXBF, RXBE) and the shift register flag TXMTIF of U1ERRIR,
' not the interrupt flags. Chosen with `#if _has(U1CON0)`.
'
' Baud rate: BRG16 = 1 and BRGH = 1 give baud = FOSC / (4 * (n + 1)) [Table 29-1, TXxSTA BRGH];
' n is SP1BRGH:SP1BRGL. The result is rounded to the nearest n. `Clock` must be FOSC in MHz.
' An internal oscillator drifts with voltage and temperature [29.1.3], which shifts the baud rate.
#if _has(U1CON0)
Dim TxFull As U1FIFO.4
Dim TxBufEmpty As U1FIFO.5
Dim RxEmpty As U1FIFO.1
Dim TxShiftEmpty As U1ERRIR.7
Dim OverrunErr As U1ERRIR.1
Dim TxPin As TRISC.4
Dim RxPin As TRISC.5
Dim TxAnalog As ANSELC.4
Dim RxAnalog As ANSELC.5
Const SerTxCode = 16
Const SerRxCode = 21
#elseif _has(ADCON1.PREF)
Dim RxIf As PIR1.4
#if _has(TRISC)
Dim TxPin As TRISC.4
Dim RxPin As TRISC.5
Dim RxAnalog As ANSELC.5
Const SerRxCode = 21
#else
Dim TxPin As TRISA.4
Dim RxPin As TRISA.5
Dim RxAnalog As ANSELA.5
Const SerRxCode = 5
#endif
Const SerTxCode = 5
Dim OverrunErr As RC1STA.1
Dim RxEnable As RC1STA.4
#elseif _has(ADCON0.CHS)
Dim TxIf As PIR1.4
Dim RxIf As PIR1.5
#if _has(TRISC)
Dim TxPin As TRISC.4
Dim RxPin As TRISC.5
Dim RxAnalog As ANSELC.5
Const SerRxCode = 21
#else
Dim TxPin As TRISA.4
Dim RxPin As TRISA.5
Dim RxAnalog As ANSELA.5
Const SerRxCode = 5
#endif
Const SerTxCode = 20
Dim OverrunErr As RC1STA.1
Dim RxEnable As RC1STA.4
#elseif _has(PIR4.TX1IF)
Dim TxIf As PIR4.6
Dim RxIf As PIR4.7
#if _has(TRISC)
Dim TxPin As TRISC.4
Dim RxPin As TRISC.5
Dim RxAnalog As ANSELC.5
Const SerRxCode = 21
#else
' PIC16F13113 (8-pin, DS40002519D Table 1 p.1): port A only, so TX is RA4 and RX is RA5 (RX1PPS = 000 101).
Dim TxPin As TRISA.4
Dim RxPin As TRISA.5
Dim RxAnalog As ANSELA.5
Const SerRxCode = 5
#endif
Const SerTxCode = 19
Dim OverrunErr As RC1STA.1
Dim RxEnable As RC1STA.4
#else
Dim TxIf As PIR3.4
Dim RxIf As PIR3.5
Dim TxPin As TRISC.6
Dim RxPin As TRISC.7
Dim RxAnalog As ANSELC.7
Const SerTxCode = 9
Const SerRxCode = 23
Dim OverrunErr As RC1STA.1
Dim RxEnable As RC1STA.4
#endif
Public Const FoscHz = LongWord(_Clock * 1000000)

Public Sub SerialInit(ByVal baud As LongWord)
    Dim n As LongWord
    n = (FoscHz + baud * 2) / (baud * 4) - 1
    RxAnalog = 0
    RxPin = 1
    TxPin = 0
#if _has(U1CON0)
    TxAnalog = 0
    RC4PPS = SerTxCode
    U1RXPPS = SerRxCode
    ' UxBRG is written only while ON = 0 [34.20.8]. BRGS = 1 (4 baud clocks per bit), TXEN, RXEN, MODE = 8-bit
    ' asynchronous [34.20.1]; RUNOVF keeps the receiver running after a FIFO overflow [34.20.3]; then ON [34.20.2].
    U1BRGL = Byte(n)
    U1BRGH = Byte(n >> 8)
    U1CON0 = 176
    U1CON2 = 128
    U1CON1 = 128
#elseif _has(ADCON1.PREF)
#if _has(TRISC)
    RC4PPS = SerTxCode
#else
    RA4PPS = SerTxCode
#endif
    RX1PPS = SerRxCode
    SP1BRGL = Byte(n)
    SP1BRGH = Byte(n >> 8)
    BAUD1CON = 8
    TX1STA = 36
    RC1STA = 144
#elseif _has(ADCON0.CHS)
#if _has(TRISC)
    RC4PPS = SerTxCode
#else
    RA4PPS = SerTxCode
#endif
    RXPPS = SerRxCode
    SP1BRGL = Byte(n)
    SP1BRGH = Byte(n >> 8)
    BAUD1CON = 8
    TX1STA = 36
    RC1STA = 144
#elseif _has(PIR4.TX1IF)
#if _has(TRISC)
    RC4PPS = SerTxCode
#else
    RA4PPS = SerTxCode
#endif
    RX1PPS = SerRxCode
    SP1BRGL = Byte(n)
    SP1BRGH = Byte(n >> 8)
    BAUD1CON = 8
    TX1STA = 36
    RC1STA = 144
#else
    RC6PPS = SerTxCode
    RX1PPS = SerRxCode
    SP1BRGL = Byte(n)
    SP1BRGH = Byte(n >> 8)
    BAUD1CON = 8
    TX1STA = 36
    RC1STA = 144
#endif
End Sub

' Sends one byte, waiting for the transmit register to be free.
Public Sub SerialWriteByte(ByVal b As Byte)
#if _has(U1CON0)
    While TxFull = 1
    Wend
    U1TXB = b
#elseif _has(ADCON1.PREF)
    ' Erratum 1.3.1: write only when the shift register is empty (TRMT, TX1STA bit 1).
    While TX1STA.1 = 0
    Wend
    TX1REG = b
#else
    While TxIf = 0
    Wend
    TX1REG = b
#endif
End Sub

Public Sub SerialWrite(ByRefConst s As String(80))
    Dim i As Byte
    Dim c As Byte
    i = 0
    While True
        c = Byte(s(i))
        If c = 0 Then
            Exit
        End If
        SerialWriteByte(c)
        Inc(i)
    Wend
End Sub

Public Sub SerialNewLine()
    SerialWriteByte(13)
    SerialWriteByte(10)
End Sub

' Unsigned decimal, no leading zeros.
Public Sub SerialWriteWord(ByVal v As Word)
    Dim started As Boolean
    Dim d As Word
    Dim digit As Byte
    started = False
    d = 10000
    While d > 0
        digit = Byte(v / d)
        v = v Mod d
        If digit > 0 Or started Or d = 1 Then
            SerialWriteByte(48 + digit)
            started = True
        End If
        d = d / 10
    Wend
End Sub

Public Sub SerialWriteHex(ByVal v As Byte)
    Dim h As Byte
    h = v >> 4
    If h > 9 Then
        h = h + 7
    End If
    SerialWriteByte(48 + h)
    h = v And 15
    If h > 9 Then
        h = h + 7
    End If
    SerialWriteByte(48 + h)
End Sub

' True when a received byte is waiting.
Public Function SerialAvailable() As Boolean
#if _has(U1CON0)
    Result = RxEmpty = 0
#else
    Result = RxIf = 1
#endif
End Function

' Waits for a byte. An overrun stops the receiver until CREN is cycled, so it is cleared here.
Public Function SerialRead() As Byte
#if _has(U1CON0)
    ' A full receive FIFO sets RXFOIF; the shifter keeps running (RUNOVF), so the flag is just cleared [34.2.2.7].
    While RxEmpty = 1
        If OverrunErr = 1 Then
            OverrunErr = 0
        End If
    Wend
    Result = U1RXB
#else
    While RxIf = 0
        If OverrunErr = 1 Then
            RxEnable = 0
            RxEnable = 1
        End If
    Wend
    Result = RC1REG
#endif
End Function

' Event hook: assign a handler to SerialOnRx, then call SerialRxService regularly (from the main loop, or from
' your own Interrupt inside Save(0, SerialRxService)). When a byte has arrived it is read, which clears RCIF,
' and passed to the handler. An overrun is cleared as SerialRead does. An unassigned SerialOnRx still reads
' (and drops) the byte.
Public Type TRxEvent = Event(ByVal c As Byte)
Public Dim SerialOnRx As TRxEvent
Public Sub SerialRxService()
#if _has(U1CON0)
    If OverrunErr = 1 Then
        OverrunErr = 0
    End If
    If RxEmpty = 0 Then
        SerialOnRx(U1RXB)
    End If
#else
    If OverrunErr = 1 Then
        RxEnable = 0
        RxEnable = 1
    End If
    If RxIf = 1 Then
        SerialOnRx(RC1REG)
    End If
#endif
End Sub

' Waits until the last byte has left the shift register (TRMT, TX1STA bit 1; Q41: transmit buffer empty, TXBE, and
' shift register empty, TXMTIF, which is set at the end of the Stop bits [34.20.4, 34.20.7]).
Public Sub SerialFlush()
#if _has(U1CON0)
    While TxBufEmpty = 0 Or TxShiftEmpty = 0
    Wend
#else
    While TX1STA.1 = 0
    Wend
#endif
End Sub
