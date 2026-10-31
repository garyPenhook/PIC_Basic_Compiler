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

' Level read from pin (True = high).
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
