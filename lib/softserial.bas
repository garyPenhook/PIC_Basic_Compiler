Module Softserial
Include "pinio"
' Asynchronous serial, 8 data bits, no parity, 1 stop bit, on any two pins (numbered as in `Pinio`: RA0 = 0, RB0 = 8,
' RC0 = 16, up to 47 on the parts with ports D to F): for the parts with one EUSART or none to spare, for an inverted line (RS-232 without a driver) and for a
' pin the EUSART cannot reach. Bit times are counted in instruction cycles from `Clock`, so the baud rate follows it.
' Nothing here uses a timer or an interrupt; an interrupt during a byte stretches a bit, so hold interrupts off
' (`Disable` ... `Enable`) around a byte at a high baud rate. A byte received while the program is elsewhere is lost:
' this is for a poll, not a buffer.
'
' The loops are code, not assembly, and cost a fixed number of cycles per bit that the per-bit wait makes up for
' (OverheadCyc, PassCyc, measured with the simulator's cycle count: `tests/softserial_timing.py`). The start edge of
' a received byte is found to within one poll (PollCyc cycles), which sets the highest usable baud: about 1/6 of
' the instruction rate at the very best.

' Cycles of one bit that are not the wait (the pin write, the loop, the call) and cycles of one pass of the wait,
' measured with `scripts/softserial_timing.py` at 4800 to 38400 baud (PIC18: 39 and 7, PIC16: 69 and 9; the
' unoptimised `-O0` build: PIC18 37 and 11, PIC16 79 and 10).
#if _core = "pic18"
#if _opt = 1
Private Const OverheadCyc = 39
Private Const PassCyc = 7
#else
Private Const OverheadCyc = 37
Private Const PassCyc = 11
#endif
#else
#if _opt = 1
Private Const OverheadCyc = 69
Private Const PassCyc = 9
#else
Private Const OverheadCyc = 79
Private Const PassCyc = 10
#endif
#endif

' Cycles of one poll of the start-bit loop, from the start edge to the first wait, and of the receive code per bit. Measured by the sweep `scripts/softserial_rx_sweep.py`. A millisecond is PollsMs polls;
' the first wait runs 1.5 bits less RxStartCyc, which is 1.5 * bitN plus FirstAdj passes.
#if _core = "pic18"
#if _opt = 1
Private Const PollCyc = 30
Private Const RxStartCyc = 48
Private Const RxBitCyc = 39
#else
Private Const PollCyc = 60
Private Const RxStartCyc = 50
Private Const RxBitCyc = 70
#endif
#else
#if _opt = 1
Private Const PollCyc = 60
Private Const RxStartCyc = 70
Private Const RxBitCyc = 79
#else
Private Const PollCyc = 67
Private Const RxStartCyc = 100
Private Const RxBitCyc = 75
#endif
#endif

' The receive wait of the unoptimised PIC16 build costs 12 cycles a pass, not the 10 of the transmit wait (the same
' `Hold`, called from a different routine), so that build computes the receive count from the cycles directly.
#if _core <> "pic18" and _opt = 0
Private Const RxPassCyc = 12
#else
Private Const RxPassCyc = PassCyc
#endif

Private Const PollsMs = Word(_Clock * 250 / PollCyc)
Private Const RxLess = (RxBitCyc - OverheadCyc + PassCyc / 2) / PassCyc
#if _core <> "pic18" and _opt = 0
Private Const FirstAdj = (RxBitCyc * 3 / 2 - RxStartCyc) / RxPassCyc
#else
Private Const FirstAdj = (OverheadCyc * 3 / 2 - RxStartCyc) / PassCyc
#endif

' The global interrupt enable: bit 7 of INTCON (GIE, or GIE/GIEH with priorities), of INTCON0 on the PIC18-Q41
' [DS40002043F 15.13.1, DS40002343F 12.10.1, DS40002214G 11.13.1]. Clearing it holds every interrupt off, with
' priorities too.
#if _has(INTCON0)
Private Dim Gie As INTCON0.7
#else
Private Dim Gie As INTCON.7
#endif
Private Dim holdIrq As Boolean = True

Private Dim txPin As Byte = 255
Private Dim rxPin As Byte = 255
Private Dim idle As Boolean
Private Dim bitN As Word
#if _core <> "pic18"
Private Dim rxN As Word
#endif

' Passes of the wait for one bit.
Private Sub Hold(ByVal n As Word)
    While n > 0
        Dec(n)
    Wend
End Sub

' Sets the pins and the speed; call it first. `tx` or `rx` a pin the part lacks (255, say) means "not used".
' `inverted` = True for a line that idles low (true RS-232 levels through a driver chip, or a transistor inverter).
' Returns False, with both pins unused, when the baud rate is too high for this Clock or so low that a bit is
' more than 65535 instruction cycles (below about 980 baud at 64 MHz).
Public Function SoftInit(ByVal tx As Byte, ByVal rx As Byte, ByVal baud As LongWord, ByVal inverted As Boolean) As Boolean
    Dim cyc As LongWord
    Dim n As Word
    txPin = 255
    rxPin = 255
    Result = False
    cyc = LongWord(_Clock) * 250000 / baud     ' instruction cycles in one bit (a baud of 0 gives all ones)
    n = Word(cyc)
    If Word(cyc >> 16) <> 0 Or n < OverheadCyc + PassCyc Then
        Exit
    End If
    bitN = (n - OverheadCyc + PassCyc / 2) / PassCyc
#if _core <> "pic18" and _opt = 0
    rxN = (n - RxBitCyc + RxPassCyc / 2) / RxPassCyc
#elseif _core <> "pic18"
    rxN = bitN - RxLess
#endif
    idle = Not inverted
    If Pinio.PinOk(tx) Then
        txPin = tx
        Pinio.BindData(tx)
        Pinio.DataPut(idle)
        Pinio.PinOutput(tx)
    End If
    If Pinio.PinOk(rx) Then
        rxPin = rx
        Pinio.PinInput(rx)
    End If
    Result = True
End Function

' True when the receive pin has left its idle level: a byte is starting (a SoftReadByte now returns it).
Public Function SoftAvailable() As Boolean
    Result = False
    If Pinio.PinOk(rxPin) Then
        Pinio.BindData(rxPin)
        Result = Pinio.DataRead() <> idle
    End If
End Function

' With True (the default) a byte is sent or received with interrupts held off, so an interrupt cannot stretch a bit;
' the interrupt enable is put back as it was. A received byte holds them off from its start edge on, 10 bit times
' (about 1 ms at 9600 baud): other interrupts wait that long. With False nothing is touched, and an interrupt
' that runs during a byte distorts it, which a low baud rate and a short handler can live with.
Public Sub SoftHoldIrq(ByVal on As Boolean)
    holdIrq = on
End Sub

' Sends one byte.
Public Sub SoftWriteByte(ByVal b As Byte)
    Dim i As Byte
    Dim g As Boolean
    If Not Pinio.PinOk(txPin) Then
        Exit
    End If
    Pinio.BindData(txPin)
    g = False
    If holdIrq Then
        g = Gie = 1
        Gie = 0
    End If
    Pinio.DataPut(Not idle)
    Hold(bitN)
    For i = 0 To 7
        Pinio.DataPut(((b And 1) <> 0) = idle)
        b = b >> 1
        Hold(bitN)
    Next
    Pinio.DataPut(idle)
    Hold(bitN)
    If g Then
        Gie = 1
    End If
End Sub

' Sends the characters of `text` (up to 80).
Public Sub SoftWrite(ByRefConst s As String(80))
    Dim i As Byte
    Dim c As Byte
    i = 0
    While True
        c = Byte(s(i))
        If c = 0 Then
            Exit
        End If
        SoftWriteByte(c)
        Inc(i)
    Wend
End Sub

Public Sub SoftNewLine()
    SoftWriteByte(13)
    SoftWriteByte(10)
End Sub

' Waits up to `ms` milliseconds for a byte: the byte (0 to 255), -1 when none came, or -2 when the stop bit was not
' at the idle level (a framing error: a wrong baud rate, or a break). Looks at the start edge every PollCyc cycles,
' then samples each bit in the middle; the call ends in the middle of the stop bit, so the next call can catch an
' edge that follows at once. After -2 it waits one more bit so that a stop bit that was merely late is over; a line
' that stays low (a break) answers -2 again at every call.
Public Function SoftReadByte(ByVal ms As Word) As Integer
    Dim k As Word
    Dim i As Byte
    Dim v As Byte
    Dim found As Boolean
    Dim g As Boolean
    If Not Pinio.PinOk(rxPin) Then
        Result = -1
        Exit
    End If
    Pinio.BindData(rxPin)
    found = False
    While Not found
        k = PollsMs
        While k > 0 And Not found
            found = Pinio.DataRead() <> idle
            Dec(k)
        Wend
        If ms = 0 Then
            Break
        End If
        Dec(ms)
    Wend
    If Not found Then
        Result = -1
        Exit
    End If
    g = False
    If holdIrq Then
        g = Gie = 1
        Gie = 0
    End If
#if _core = "pic18"
    Hold(bitN + bitN / 2 + FirstAdj)
#else
    Hold(rxN + rxN / 2 + FirstAdj)
#endif
    v = 0
    For i = 0 To 7
        v = v >> 1
        If Pinio.DataRead() = idle Then
            v = v Or $80
        End If
#if _core = "pic18"
        Hold(bitN)
#else
        Hold(rxN)
#endif
    Next
    If Pinio.DataRead() <> idle Then
        Result = -2
        Hold(bitN)
    Else
        Result = v
    End If
    If g Then
        Gie = 1
    End If
End Function
