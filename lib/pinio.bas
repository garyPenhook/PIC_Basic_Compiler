Module Pinio
' Run-time pin access by number, for the bit-banged modules (`shift`, and the ones built on it). Pins are
' numbered as in the `Lcd` module: RA0..RA7 = 0..7, RB0..RB7 = 8..15, RC0..RC7 = 16..23. A part without
' port B (14-pin PIC18-Q41, PIC16F13123/13124/13125, 8-pin PIC16F13113) or without port C refuses those pins:
' PinOk is False for them, and every routine ignores a pin that is not OK.
'
' PinOutput / PinInput also clear the pin's ANSELx bit, so the pin is digital. PinSet writes LATx
' (read-modify-write), PinGet reads PORTx. PinFloat / PinDrive give an open-drain line without ODCONx: the
' LATx bit is cleared once by PinDriveLow, then TRISx alternates (input = released, output = low).
' The routines are not reentrant and change LATx/TRISx by read-modify-write: do not use them from an
' interrupt handler and the main program on the same port.

' True for a pin 0..23 that the part has.
Public Function PinOk(ByVal pin As Byte) As Boolean
    Result = pin < 8
#if _has(LATB)
    If pin >= 8 And pin < 16 Then
        Result = True
    End If
#endif
#if _has(LATC)
    If pin >= 16 And pin < 24 Then
        Result = True
    End If
#endif
End Function

' Output level of pin (True = high).
#if _has(PRODL)
' PIC18: the LATx registers are consecutive (LATA, LATB, LATC) on every supported part [18F27Q10 LATA..LATC 0xF82..0xF84,
' PIC18-Q41 0x4BE..0x4C0, from the device files; the 18F0xQ41 parts have no LATB but keep LATC at LATA + 2], so the port is
' LATA + (pin >> 3), reached through FSR0 (compiler-owned, nothing is live in it across a call), and the mask is built by a
' shift loop. A pin 24 and above, or on a port the part lacks, is ignored.
Public Sub PinSet(ByVal pin As Byte, ByVal level As Boolean)
#if Not _has(LATB)
    If pin >= 8 And pin < 16 Then
        Exit
    End If
#endif
    Asm
        movf PINIO_PINSET__PIN, w, c
        sublw 23
        bnc PINIO_PINSET_END
        lfsr 0, LATA
        rrncf PINIO_PINSET__PIN, w, c
        rrncf WREG, w, c
        rrncf WREG, w, c
        andlw 3
        addwf FSR0L, f, c
        movlw 7
        andwf PINIO_PINSET__PIN, f, c
        movlw 1
PINIO_PINSET_SHL:
        decf PINIO_PINSET__PIN, f, c
        bnc PINIO_PINSET_GOT
        rlncf WREG, w, c
        bra PINIO_PINSET_SHL
PINIO_PINSET_GOT:
        tstfsz PINIO_PINSET__LEVEL, c
        bra PINIO_PINSET_HI
        comf WREG, w, c
        andwf INDF0, f, c
        bra PINIO_PINSET_END
PINIO_PINSET_HI:
        iorwf INDF0, f, c
PINIO_PINSET_END:
    End Asm
End Sub
#else
Public Sub PinSet(ByVal pin As Byte, ByVal level As Boolean)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 8 Then
        If level Then
            LATA = LATA Or m
        Else
            LATA = LATA And (m Xor 255)
        End If
#if _has(LATB)
    ElseIf pin < 16 Then
        If level Then
            LATB = LATB Or m
        Else
            LATB = LATB And (m Xor 255)
        End If
#endif
#if _has(LATC)
    ElseIf pin < 24 Then
        If level Then
            LATC = LATC Or m
        Else
            LATC = LATC And (m Xor 255)
        End If
#endif
    End If
End Sub
#endif

' Level read from pin (True = high).
#if _has(PRODL)
' PIC18: PORTA, PORTB, PORTC are consecutive too (see PinSet); the same FSR0 scheme. False for a pin that is not OK.
Public Function PinGet(ByVal pin As Byte) As Boolean
#if Not _has(LATB)
    If pin >= 8 And pin < 16 Then
        Result = False
        Exit
    End If
#endif
    Asm
        clrf PINIO_PINGET__RESULT, c
        movf PINIO_PINGET__PIN, w, c
        sublw 23
        bnc PINIO_PINGET_END
        lfsr 0, PORTA
        rrncf PINIO_PINGET__PIN, w, c
        rrncf WREG, w, c
        rrncf WREG, w, c
        andlw 3
        addwf FSR0L, f, c
        movlw 7
        andwf PINIO_PINGET__PIN, f, c
        movlw 1
PINIO_PINGET_SHL:
        decf PINIO_PINGET__PIN, f, c
        bnc PINIO_PINGET_GOT
        rlncf WREG, w, c
        bra PINIO_PINGET_SHL
PINIO_PINGET_GOT:
        andwf INDF0, w, c
        bz PINIO_PINGET_END
        incf PINIO_PINGET__RESULT, f, c
PINIO_PINGET_END:
    End Asm
End Function
#else
Public Function PinGet(ByVal pin As Byte) As Boolean
    Dim m As Byte
    m = 1 << (pin And 7)
    Result = False
    If pin < 8 Then
        Result = (PORTA And m) <> 0
#if _has(LATB)
    ElseIf pin < 16 Then
        Result = (PORTB And m) <> 0
#endif
#if _has(LATC)
    ElseIf pin < 24 Then
        Result = (PORTC And m) <> 0
#endif
    End If
End Function
#endif

' Pin as a digital output.
Public Sub PinOutput(ByVal pin As Byte)
    Dim m As Byte
    Dim n As Byte
    m = 1 << (pin And 7)
    n = m Xor 255
    If pin < 8 Then
        ANSELA = ANSELA And n
        TRISA = TRISA And n
#if _has(LATB)
    ElseIf pin < 16 Then
        ANSELB = ANSELB And n
        TRISB = TRISB And n
#endif
#if _has(LATC)
    ElseIf pin < 24 Then
        ANSELC = ANSELC And n
        TRISC = TRISC And n
#endif
    End If
End Sub

' Pin as a digital input.
Public Sub PinInput(ByVal pin As Byte)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 8 Then
        ANSELA = ANSELA And (m Xor 255)
        TRISA = TRISA Or m
#if _has(LATB)
    ElseIf pin < 16 Then
        ANSELB = ANSELB And (m Xor 255)
        TRISB = TRISB Or m
#endif
#if _has(LATC)
    ElseIf pin < 24 Then
        ANSELC = ANSELC And (m Xor 255)
        TRISC = TRISC Or m
#endif
    End If
End Sub

' Open-drain line: PinDriveLow pulls the pin low (LATx bit cleared, pin made an output); PinRelease lets it
' float (input), so an external pull-up takes it high. The pin is digital.
Public Sub PinDriveLow(ByVal pin As Byte)
    PinSet(pin, False)
    PinOutput(pin)
End Sub

Public Sub PinRelease(ByVal pin As Byte)
    PinInput(pin)
End Sub

' Bound pins, for a loop that drives or reads two pins many times (`shift`): BindData / BindClk resolve a pin once (use only a pin
' PinOk accepted), then DataPut / DataRead act on the data pin and ClkPut on the clock pin without the per-call port search and
' mask loop. On PIC18 each is a few instructions through FSR0; on the other cores they call PinSet / PinGet on the bound pin.
' Not reentrant: one data pin and one clock pin at a time.
#if _has(PRODL)
Dim dAddr As Word
Dim dMask As Byte
Dim cAddr As Word
Dim cMask As Byte

' LATx address of pin 0..23 (0 otherwise).
Function PinAddr(ByVal pin As Byte) As Word
    Asm
        clrf PINIO_PINADDR__RESULT, c
        clrf PINIO_PINADDR__RESULT+1, c
        movf PINIO_PINADDR__PIN, w, c
        sublw 23
        bnc PINIO_PINADDR_END
        rrncf PINIO_PINADDR__PIN, w, c
        rrncf WREG, w, c
        rrncf WREG, w, c
        andlw 3
        addlw low LATA
        movwf PINIO_PINADDR__RESULT, c
        movlw high LATA
        movwf PINIO_PINADDR__RESULT+1, c
PINIO_PINADDR_END:
    End Asm
End Function

Public Sub BindData(ByVal pin As Byte)
    dAddr = PinAddr(pin)
    dMask = 1 << (pin And 7)
End Sub

Public Sub BindClk(ByVal pin As Byte)
    cAddr = PinAddr(pin)
    cMask = 1 << (pin And 7)
End Sub

Public Sub DataPut(ByVal level As Boolean)
    Asm
        movff PINIO_DADDR, FSR0L
        movff PINIO_DADDR+1, FSR0H
        movf PINIO_DMASK, w, c
        tstfsz PINIO_DATAPUT__LEVEL, c
        bra PINIO_DATAPUT_HI
        comf WREG, w, c
        andwf INDF0, f, c
        bra PINIO_DATAPUT_END
PINIO_DATAPUT_HI:
        iorwf INDF0, f, c
PINIO_DATAPUT_END:
    End Asm
End Sub

Public Sub ClkPut(ByVal level As Boolean)
    Asm
        movff PINIO_CADDR, FSR0L
        movff PINIO_CADDR+1, FSR0H
        movf PINIO_CMASK, w, c
        tstfsz PINIO_CLKPUT__LEVEL, c
        bra PINIO_CLKPUT_HI
        comf WREG, w, c
        andwf INDF0, f, c
        bra PINIO_CLKPUT_END
PINIO_CLKPUT_HI:
        iorwf INDF0, f, c
PINIO_CLKPUT_END:
    End Asm
End Sub

Public Function DataRead() As Boolean
    Asm
        clrf PINIO_DATAREAD__RESULT, c
        movlw PORTA - LATA
        addwf PINIO_DADDR, w, c
        movwf FSR0L, c
        movff PINIO_DADDR+1, FSR0H
        movf PINIO_DMASK, w, c
        andwf INDF0, w, c
        bz PINIO_DATAREAD_END
        incf PINIO_DATAREAD__RESULT, f, c
PINIO_DATAREAD_END:
    End Asm
End Function
#else
Dim dPin As Byte
Dim cPin As Byte

Public Sub BindData(ByVal pin As Byte)
    dPin = pin
End Sub

Public Sub BindClk(ByVal pin As Byte)
    cPin = pin
End Sub

Public Sub DataPut(ByVal level As Boolean)
    PinSet(dPin, level)
End Sub

Public Sub ClkPut(ByVal level As Boolean)
    PinSet(cPin, level)
End Sub

Public Function DataRead() As Boolean
    Result = PinGet(dPin)
End Function
#endif

' ---- Whole-port byte access, for 8-bit parallel buses (`glcd`) ----
' `base` is the first pin of the port: 0 = port A, 8 = port B, 16 = port C (any other value, or a port the part lacks, is ignored
' and reads as 0). All eight bits of the port are used, so the part must have all eight pins.

' Writes `v` to the port's latch.
Public Sub PortWrite(ByVal base As Byte, ByVal v As Byte)
    If base = 0 Then
        LATA = v
#if _has(LATB)
    ElseIf base = 8 Then
        LATB = v
#endif
#if _has(LATC)
    ElseIf base = 16 Then
        LATC = v
#endif
    End If
End Sub

' Reads the port's pins.
Public Function PortRead(ByVal base As Byte) As Byte
    Result = 0
    If base = 0 Then
        Result = PORTA
#if _has(LATB)
    ElseIf base = 8 Then
        Result = PORTB
#endif
#if _has(LATC)
    ElseIf base = 16 Then
        Result = PORTC
#endif
    End If
End Function

' Makes the eight pins of the port digital inputs (`isInput` True) or outputs.
Public Sub PortDirection(ByVal base As Byte, ByVal isInput As Boolean)
    Dim t As Byte
    t = 0
    If isInput Then
        t = 255
    End If
    If base = 0 Then
        ANSELA = 0
        TRISA = t
#if _has(LATB)
    ElseIf base = 8 Then
        ANSELB = 0
        TRISB = t
#endif
#if _has(LATC)
    ElseIf base = 16 Then
        ANSELC = 0
        TRISC = t
#endif
    End If
End Sub
