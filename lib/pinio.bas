Module Pinio
' Run-time pin access by number, for the bit-banged modules (`shift`, and the ones built on it). Pins are
' numbered as in the `Lcd` module: RA0..RA7 = 0..7, RB0..RB7 = 8..15, RC0..RC7 = 16..23, RD0..RD7 = 24..31, RE0..RE7 = 32..39 and RF0..RF7 = 40..47 (the numbers of the ADC channels and of the PPS input registers). A part without
' port B (14-pin PIC18-Q41, PIC16F13123/13124/13125, 8-pin PIC16F13113) or without port C refuses those pins:
' PinOk is False for them, and every routine ignores a pin that is not OK.
'
' PinOutput / PinInput also clear the pin's ANSELx bit, so the pin is digital. PinSet writes LATx
' (read-modify-write), PinGet reads PORTx. PinFloat / PinDrive give an open-drain line without ODCONx: the
' LATx bit is cleared once by PinDriveLow, then TRISx alternates (input = released, output = low).
' The routines are not reentrant and change LATx/TRISx by read-modify-write: do not use them from an
' interrupt handler and the main program on the same port.

' One more than the highest pin number a part can have: 24 (ports A to C), 32 (with port D), 40 (with port E) or 48 (with port F).
#if _has(PRODL)
Public Const PinCount = 24
#elseif _has(LATF)
Public Const PinCount = 48
#elseif _has(ANSELE)
Public Const PinCount = 40
#elseif _has(LATD)
Public Const PinCount = 32
#else
Public Const PinCount = 24
#endif

' True for a pin that the part has (one comparison: the part's ports are A, A + B, A + C, A + B + C, and on the larger parts D, E and F; pins 0..47).
Public Function PinOk(ByVal pin As Byte) As Boolean
#if _has(LATB)
#if _has(LATF)
    Result = pin < 48
#elseif _has(ANSELE)
    Result = pin < 40
#elseif _has(LATD)
    Result = pin < 32
#elseif _has(LATC)
    Result = pin < 24
#else
    Result = pin < 16
#endif
#else
#if _has(LATC)
    Result = (pin And 8) = 0 And pin < 24
#else
    Result = pin < 8
#endif
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
#if _has(LATF)
Const PinTop As Byte = 48
#elseif _has(ANSELE)
Const PinTop As Byte = 40
#elseif _has(LATD)
Const PinTop As Byte = 32
#endif
' Enhanced mid-range: LATA, LATB, LATC are consecutive on every supported part [PIC16F131xx..F180xx: 0x18..0x1A, F183xx: 0x10C..0x10E,
' from the device files] and a part without port B keeps LATC at LATA + 2, so the port is LATA + (pin >> 3), reached through FSR0. The
' mask is 1 << (pin And 7) built from the three low bits of the pin by conditional shifts (no loop, the pin is not changed): bit 0
' and bit 1 shift by 1 and 2 (a bit-1 shift is two steps), bit 2 is the nibble swap of a mask that is still in the low nibble.
#if _has(LATD)
Public Sub PinSet(ByVal pin As Byte, ByVal level As Boolean)
#if Not _has(LATB)
    If pin >= 8 And pin < 16 Then
        Exit
    End If
#endif
#if Not _has(LATC)
    If pin >= 16 Then
        Exit
    End If
#endif
    If pin >= PinTop Then
        Exit
    End If
    Asm
        banksel PINIO_PINSET__PIN
        lsrf PINIO_PINSET__PIN, w
        lsrf WREG, w
        lsrf WREG, w
        addlw low(LATA)
        movwf FSR0L
        movlw high(LATA)
        movwf FSR0H
        movlw 1
        btfsc PINIO_PINSET__PIN, 0
        lslf WREG, w
        btfsc PINIO_PINSET__PIN, 1
        lslf WREG, w
        btfsc PINIO_PINSET__PIN, 1
        lslf WREG, w
        btfsc PINIO_PINSET__PIN, 2
        swapf WREG, w
        banksel PINIO_PINSET__LEVEL
        movf PINIO_PINSET__LEVEL, f
        btfsc STATUS, 2
        goto PINIO_PINSET_LO
        iorwf INDF0, f
        goto PINIO_PINSET_END
PINIO_PINSET_LO:
        xorlw 255
        andwf INDF0, f
PINIO_PINSET_END:
    End Asm
End Sub
#else
Public Sub PinSet(ByVal pin As Byte, ByVal level As Boolean)
#if Not _has(LATB)
    If pin >= 8 And pin < 16 Then
        Exit
    End If
#endif
#if Not _has(LATC)
    If pin >= 16 Then
        Exit
    End If
#endif
    Asm
        banksel PINIO_PINSET__PIN
        movlw 24
        subwf PINIO_PINSET__PIN, w
        btfsc STATUS, 0
        goto PINIO_PINSET_END
        lsrf PINIO_PINSET__PIN, w
        lsrf WREG, w
        lsrf WREG, w
        addlw low(LATA)
        movwf FSR0L
        movlw high(LATA)
        movwf FSR0H
        movlw 1
        btfsc PINIO_PINSET__PIN, 0
        lslf WREG, w
        btfsc PINIO_PINSET__PIN, 1
        lslf WREG, w
        btfsc PINIO_PINSET__PIN, 1
        lslf WREG, w
        btfsc PINIO_PINSET__PIN, 2
        swapf WREG, w
        banksel PINIO_PINSET__LEVEL
        movf PINIO_PINSET__LEVEL, f
        btfsc STATUS, 2
        goto PINIO_PINSET_LO
        iorwf INDF0, f
        goto PINIO_PINSET_END
PINIO_PINSET_LO:
        xorlw 255
        andwf INDF0, f
PINIO_PINSET_END:
    End Asm
End Sub
#endif
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
' Enhanced mid-range: PORTA, PORTB, PORTC are consecutive too; the scheme of PinSet. False for a pin that is not OK.
#if _has(LATD)
Public Function PinGet(ByVal pin As Byte) As Boolean
#if Not _has(LATB)
    If pin >= 8 And pin < 16 Then
        Result = False
        Exit
    End If
#endif
#if Not _has(LATC)
    If pin >= 16 Then
        Result = False
        Exit
    End If
#endif
    If pin >= PinTop Then
        Result = False
        Exit
    End If
    Asm
        banksel PINIO_PINGET__RESULT
        clrf PINIO_PINGET__RESULT
        banksel PINIO_PINGET__PIN
        lsrf PINIO_PINGET__PIN, w
        lsrf WREG, w
        lsrf WREG, w
        addlw low(PORTA)
        movwf FSR0L
        movlw high(PORTA)
        movwf FSR0H
        movlw 1
        btfsc PINIO_PINGET__PIN, 0
        lslf WREG, w
        btfsc PINIO_PINGET__PIN, 1
        lslf WREG, w
        btfsc PINIO_PINGET__PIN, 1
        lslf WREG, w
        btfsc PINIO_PINGET__PIN, 2
        swapf WREG, w
        andwf INDF0, w
        btfsc STATUS, 2
        goto PINIO_PINGET_END
        banksel PINIO_PINGET__RESULT
        incf PINIO_PINGET__RESULT, f
PINIO_PINGET_END:
    End Asm
End Function
#else
Public Function PinGet(ByVal pin As Byte) As Boolean
#if Not _has(LATB)
    If pin >= 8 And pin < 16 Then
        Result = False
        Exit
    End If
#endif
#if Not _has(LATC)
    If pin >= 16 Then
        Result = False
        Exit
    End If
#endif
    Asm
        banksel PINIO_PINGET__RESULT
        clrf PINIO_PINGET__RESULT
        banksel PINIO_PINGET__PIN
        movlw 24
        subwf PINIO_PINGET__PIN, w
        btfsc STATUS, 0
        goto PINIO_PINGET_END
        lsrf PINIO_PINGET__PIN, w
        lsrf WREG, w
        lsrf WREG, w
        addlw low(PORTA)
        movwf FSR0L
        movlw high(PORTA)
        movwf FSR0H
        movlw 1
        btfsc PINIO_PINGET__PIN, 0
        lslf WREG, w
        btfsc PINIO_PINGET__PIN, 1
        lslf WREG, w
        btfsc PINIO_PINGET__PIN, 1
        lslf WREG, w
        btfsc PINIO_PINGET__PIN, 2
        swapf WREG, w
        andwf INDF0, w
        btfsc STATUS, 2
        goto PINIO_PINGET_END
        banksel PINIO_PINGET__RESULT
        incf PINIO_PINGET__RESULT, f
PINIO_PINGET_END:
    End Asm
End Function
#endif
#endif

' Pin as a digital output. (Plain Basic on purpose: a call with a constant pin is folded into a private copy of a few words, which an Asm
' routine cannot be. A pin on a port the part lacks is ignored.)
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
#if _has(LATB)
    ElseIf pin < 24 Then
#else
    ElseIf pin >= 16 And pin < 24 Then
#endif
        ANSELC = ANSELC And n
        TRISC = TRISC And n
#endif
#if _has(LATD)
    ElseIf pin >= 24 And pin < 32 Then
        ANSELD = ANSELD And n
        TRISD = TRISD And n
#endif
#if _has(ANSELE)
    ElseIf pin >= 32 And pin < 40 Then
        ANSELE = ANSELE And n
        TRISE = TRISE And n
#endif
#if _has(LATF)
    ElseIf pin >= 40 And pin < 48 Then
        ANSELF = ANSELF And n
        TRISF = TRISF And n
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
#if _has(LATB)
    ElseIf pin < 24 Then
#else
    ElseIf pin >= 16 And pin < 24 Then
#endif
        ANSELC = ANSELC And (m Xor 255)
        TRISC = TRISC Or m
#endif
#if _has(LATD)
    ElseIf pin >= 24 And pin < 32 Then
        ANSELD = ANSELD And (m Xor 255)
        TRISD = TRISD Or m
#endif
#if _has(ANSELE)
    ElseIf pin >= 32 And pin < 40 Then
        ANSELE = ANSELE And (m Xor 255)
        TRISE = TRISE Or m
#endif
#if _has(LATF)
    ElseIf pin >= 40 And pin < 48 Then
        ANSELF = ANSELF And (m Xor 255)
        TRISF = TRISF Or m
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

' Open-drain pin, for a line that several devices share (`onewire`): the LATx bit must be 0 (PinSet(pin, False) once) and the pin
' digital (PinInput once). BindOd picks the pin (not reentrant), then OdLow makes it an output (the line is pulled low), OdRelease
' an input (a pull-up takes it high) and OdRead reads it. The three change TRISx or read PORTx only, a few instructions each: on
' PIC18 they share the bound data pin of DataPut / DataRead, on the other cores they have a bound pin of their own.
Public Sub OdLow()
    Asm
        movlw TRISA - LATA
        addwf PINIO_DADDR, w, c
        movwf FSR0L, c
        movff PINIO_DADDR+1, FSR0H
        comf PINIO_DMASK, w, c
        andwf INDF0, f, c
    End Asm
End Sub

Public Sub OdRelease()
    Asm
        movlw TRISA - LATA
        addwf PINIO_DADDR, w, c
        movwf FSR0L, c
        movff PINIO_DADDR+1, FSR0H
        movf PINIO_DMASK, w, c
        iorwf INDF0, f, c
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

Public Sub BindOd(ByVal pin As Byte)
    BindData(pin)
End Sub

Public Function OdRead() As Boolean
    Result = DataRead()
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

' Open-drain pin (see the PIC18 copy): PORTx, TRISx and the pin's mask are found once by BindOd (all of them are at addresses
' below 256 on every supported part, TRISA..C and PORTA..C consecutive), OdLow / OdRelease / OdRead use FSR0.
Dim odT As Byte
Dim odP As Byte
Dim odM As Byte

Public Sub BindOd(ByVal pin As Byte)
    Asm
        banksel PINIO_BINDOD__PIN
        lsrf PINIO_BINDOD__PIN, w
        lsrf WREG, w
        lsrf WREG, w
        movwf FSR0L
        addlw low(TRISA)
        banksel PINIO_ODT
        movwf PINIO_ODT
        movf FSR0L, w
        addlw low(PORTA)
        movwf PINIO_ODP
        movlw 1
        banksel PINIO_BINDOD__PIN
        btfsc PINIO_BINDOD__PIN, 0
        lslf WREG, w
        btfsc PINIO_BINDOD__PIN, 1
        lslf WREG, w
        btfsc PINIO_BINDOD__PIN, 1
        lslf WREG, w
        btfsc PINIO_BINDOD__PIN, 2
        swapf WREG, w
        banksel PINIO_ODM
        movwf PINIO_ODM
    End Asm
End Sub

Public Sub OdLow()
    Asm
        banksel PINIO_ODT
        movf PINIO_ODT, w
        movwf FSR0L
        clrf FSR0H
        comf PINIO_ODM, w
        andwf INDF0, f
    End Asm
End Sub

Public Sub OdRelease()
    Asm
        banksel PINIO_ODT
        movf PINIO_ODT, w
        movwf FSR0L
        clrf FSR0H
        movf PINIO_ODM, w
        iorwf INDF0, f
    End Asm
End Sub

Public Function OdRead() As Boolean
    Asm
        banksel PINIO_ODREAD__RESULT
        clrf PINIO_ODREAD__RESULT
        banksel PINIO_ODP
        movf PINIO_ODP, w
        movwf FSR0L
        clrf FSR0H
        movf PINIO_ODM, w
        andwf INDF0, w
        banksel PINIO_ODREAD__RESULT
        btfss STATUS, 2
        incf PINIO_ODREAD__RESULT, f
    End Asm
End Function
#endif

' ---- Whole-port byte access, for parallel buses (`glcd`) ----
' `base` is the first pin of the port: 0 = port A, 8 = port B, 16 = port C (any other value, or a port the part lacks, is ignored
' and reads as 0). The routines with no suffix use all eight bits of the port, so the part must have all eight pins; the `High`
' ones use only the upper nibble (pins base + 4 .. base + 7, bits 7..4) and leave the lower four pins alone. `PortDigital` makes
' the pins digital once (the ANSELx bit), `PortDirection` then only switches TRISx, which is what a bus that turns around for
' every transfer needs.

' Makes the eight pins of the port digital (clears ANSELx).
Public Sub PortDigital(ByVal base As Byte)
    If base = 0 Then
        ANSELA = 0
#if _has(LATB)
    ElseIf base = 8 Then
        ANSELB = 0
#endif
#if _has(LATC)
    ElseIf base = 16 Then
        ANSELC = 0
#endif
#if _has(LATD)
    ElseIf base = 24 Then
        ANSELD = 0
#endif
#if _has(ANSELE)
    ElseIf base = 32 Then
        ANSELE = 0
#endif
#if _has(LATF)
    ElseIf base = 40 Then
        ANSELF = 0
#endif
    End If
End Sub

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
#if _has(LATD)
    ElseIf base = 24 Then
        LATD = v
#endif
#if _has(ANSELE)
    ElseIf base = 32 Then
        LATE = v
#endif
#if _has(LATF)
    ElseIf base = 40 Then
        LATF = v
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
#if _has(LATD)
    ElseIf base = 24 Then
        Result = PORTD
#endif
#if _has(ANSELE)
    ElseIf base = 32 Then
        Result = PORTE
#endif
#if _has(LATF)
    ElseIf base = 40 Then
        Result = PORTF
#endif
    End If
End Function

' Makes the eight pins of the port inputs (`isInput` True) or outputs. The pins must have been made digital (`PortDigital`).
Public Sub PortDirection(ByVal base As Byte, ByVal isInput As Boolean)
    Dim t As Byte
    t = 0
    If isInput Then
        t = 255
    End If
    If base = 0 Then
        TRISA = t
#if _has(LATB)
    ElseIf base = 8 Then
        TRISB = t
#endif
#if _has(LATC)
    ElseIf base = 16 Then
        TRISC = t
#endif
#if _has(LATD)
    ElseIf base = 24 Then
        TRISD = t
#endif
#if _has(ANSELE)
    ElseIf base = 32 Then
        TRISE = t
#endif
#if _has(LATF)
    ElseIf base = 40 Then
        TRISF = t
#endif
    End If
End Sub

' Bits 7..4 of `v` to the upper four pins of the port's latch; the lower four are not changed.
Public Sub PortWriteHigh(ByVal base As Byte, ByVal v As Byte)
    v = v And 240
    If base = 0 Then
        LATA = (LATA And 15) Or v
#if _has(LATB)
    ElseIf base = 8 Then
        LATB = (LATB And 15) Or v
#endif
#if _has(LATC)
    ElseIf base = 16 Then
        LATC = (LATC And 15) Or v
#endif
#if _has(LATD)
    ElseIf base = 24 Then
        LATD = (LATD And 15) Or v
#endif
#if _has(ANSELE)
    ElseIf base = 32 Then
        LATE = (LATE And 15) Or v
#endif
#if _has(LATF)
    ElseIf base = 40 Then
        LATF = (LATF And 15) Or v
#endif
    End If
End Sub

' The upper four pins of the port in bits 7..4 (the lower four read as 0).
Public Function PortReadHigh(ByVal base As Byte) As Byte
    Result = PortRead(base) And 240
End Function

' Makes the upper four pins inputs or outputs and the lower four stay as they are.
Public Sub PortDirectionHigh(ByVal base As Byte, ByVal isInput As Boolean)
    Dim t As Byte
    t = 0
    If isInput Then
        t = 240
    End If
    If base = 0 Then
        TRISA = (TRISA And 15) Or t
#if _has(LATB)
    ElseIf base = 8 Then
        TRISB = (TRISB And 15) Or t
#endif
#if _has(LATC)
    ElseIf base = 16 Then
        TRISC = (TRISC And 15) Or t
#endif
#if _has(LATD)
    ElseIf base = 24 Then
        TRISD = (TRISD And 15) Or t
#endif
#if _has(ANSELE)
    ElseIf base = 32 Then
        TRISE = (TRISE And 15) Or t
#endif
#if _has(LATF)
    ElseIf base = 40 Then
        TRISF = (TRISF And 15) Or t
#endif
    End If
End Sub

' Makes the upper four pins of the port digital.
Public Sub PortDigitalHigh(ByVal base As Byte)
    If base = 0 Then
        ANSELA = ANSELA And 15
#if _has(LATB)
    ElseIf base = 8 Then
        ANSELB = ANSELB And 15
#endif
#if _has(LATC)
    ElseIf base = 16 Then
        ANSELC = ANSELC And 15
#endif
#if _has(LATD)
    ElseIf base = 24 Then
        ANSELD = ANSELD And 15
#endif
#if _has(ANSELE)
    ElseIf base = 32 Then
        ANSELE = ANSELE And 15
#endif
#if _has(LATF)
    ElseIf base = 40 Then
        ANSELF = ANSELF And 15
#endif
    End If
End Sub
