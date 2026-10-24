Module Serial2
' EUSART2 in asynchronous 8N1 mode, TX on RB6 and RX on RB7 (DS40002043F, chapter 29, and the
' PPS chapter 18). The pins are routed through PPS: RB6PPS = 0x0B selects EUSART2 TX/CK [Table 18-2];
' RX2PPS = 0x0F selects RB7 as the input (port B = 01b, pin 7) [Table 18-1, p.292]. RB6 and RB7 are
' also the ICSP clock and data pins, so disconnect a programmer or debugger while using them.
' EUSART1 (module `Serial`) can be used at the same time.
'
' Baud rate: BRG16 = 1 and BRGH = 1 give baud = FOSC / (4 * (n + 1)) [Table 29-1, TXxSTA BRGH];
' n is SP2BRGH:SP2BRGL. The result is rounded to the nearest n. `Clock` must be FOSC in MHz.
' An internal oscillator drifts with voltage and temperature [29.1.3], which shifts the baud rate.
Dim TxIf As PIR3.6
Dim RxIf As PIR3.7
Dim OverrunErr As RC2STA.1
Dim RxEnable As RC2STA.4
Dim TxPin As TRISB.6
Dim RxPin As TRISB.7
Dim RxAnalog As ANSELB.7
Public Const FoscHz = LongWord(_Clock * 1000000)

Public Sub Serial2Init(ByVal baud As LongWord)
    Dim n As LongWord
    n = (FoscHz + baud * 2) / (baud * 4) - 1
    RxAnalog = 0
    RxPin = 1
    TxPin = 0
    RB6PPS = 11
    RX2PPS = 15
    SP2BRGL = Byte(n)
    SP2BRGH = Byte(n >> 8)
    BAUD2CON = 8
    TX2STA = 36
    RC2STA = 144
End Sub

' Sends one byte, waiting for the transmit register to be free.
Public Sub Serial2WriteByte(ByVal b As Byte)
    While TxIf = 0
    Wend
    TX2REG = b
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

' Unsigned decimal, no leading zeros.
Public Sub Serial2WriteWord(ByVal v As Word)
    Dim started As Boolean
    Dim d As Word
    Dim digit As Byte
    started = False
    d = 10000
    While d > 0
        digit = Byte(v / d)
        v = v Mod d
        If digit > 0 Or started Or d = 1 Then
            Serial2WriteByte(48 + digit)
            started = True
        End If
        d = d / 10
    Wend
End Sub

Public Sub Serial2WriteHex(ByVal v As Byte)
    Dim h As Byte
    h = v >> 4
    If h > 9 Then
        h = h + 7
    End If
    Serial2WriteByte(48 + h)
    h = v And 15
    If h > 9 Then
        h = h + 7
    End If
    Serial2WriteByte(48 + h)
End Sub

' True when a received byte is waiting.
Public Function Serial2Available() As Boolean
    Result = RxIf = 1
End Function

' Waits for a byte. An overrun stops the receiver until CREN is cycled, so it is cleared here.
Public Function Serial2Read() As Byte
    While RxIf = 0
        If OverrunErr = 1 Then
            RxEnable = 0
            RxEnable = 1
        End If
    Wend
    Result = RC2REG
End Function

' Waits until the last byte has left the shift register (TRMT, TX2STA bit 1).
Public Sub Serial2Flush()
    While TX2STA.1 = 0
    Wend
End Sub
