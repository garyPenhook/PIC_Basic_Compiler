Module Serial
' EUSART1 in asynchronous 8N1 mode, TX on RC6 and RX on RC7 (DS40002043F, chapter 29, and the
' PPS chapter 18). The pins are routed through PPS: RC6PPS = 0x09 selects EUSART1 TX [Table 18-2];
' RX1PPS = 0x17 selects RC7 as the input (port C = 10b, pin 7) [p.285, p.292].
'
' Baud rate: BRG16 = 1 and BRGH = 1 give baud = FOSC / (4 * (n + 1)) [Table 29-1, TXxSTA BRGH];
' n is SP1BRGH:SP1BRGL. The result is rounded to the nearest n. `Clock` must be FOSC in MHz.
' An internal oscillator drifts with voltage and temperature [29.1.3], which shifts the baud rate.
Dim TxIf As PIR3.4
Dim RxIf As PIR3.5
Dim OverrunErr As RC1STA.1
Dim RxEnable As RC1STA.4
Dim TxPin As TRISC.6
Dim RxPin As TRISC.7
Dim RxAnalog As ANSELC.7
Public Const FoscHz = LongWord(_Clock * 1000000)

Public Sub SerialInit(ByVal baud As LongWord)
    Dim n As LongWord
    n = (FoscHz + baud * 2) / (baud * 4) - 1
    RxAnalog = 0
    RxPin = 1
    TxPin = 0
    RC6PPS = 9
    RX1PPS = 23
    SP1BRGL = Byte(n)
    SP1BRGH = Byte(n >> 8)
    BAUD1CON = 8
    TX1STA = 36
    RC1STA = 144
End Sub

' Sends one byte, waiting for the transmit register to be free.
Public Sub SerialWriteByte(ByVal b As Byte)
    While TxIf = 0
    Wend
    TX1REG = b
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
    Result = RxIf = 1
End Function

' Waits for a byte. An overrun stops the receiver until CREN is cycled, so it is cleared here.
Public Function SerialRead() As Byte
    While RxIf = 0
        If OverrunErr = 1 Then
            RxEnable = 0
            RxEnable = 1
        End If
    Wend
    Result = RC1REG
End Function

' Waits until the last byte has left the shift register (TRMT, TX1STA bit 1).
Public Sub SerialFlush()
    While TX1STA.1 = 0
    Wend
End Sub
