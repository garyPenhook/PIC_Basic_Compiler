Module Clc
Include "pinio"
' Configurable Logic Cells (CLC1..CLC8) of the PIC18F27Q10, DS40002043F chapter 26. A cell has four
' input selectors (D1S..D4S, 6 bits each, 64 sources [26.1.1 table p.409]), four gates, one logic
' function (MODE) and an output polarity. Gate y takes any of the four selected inputs true or
' inverted, ANDs them, and may invert the result (GyPOL) [26.1.2]. The registers of cell n start at
' CLC1CON + 10 * (n - 1) [CLCxCON address list p.416: E27h, E31h, E3Bh ... E6Dh], so one routine
' reaches all eight through FSR0 (compiler-owned; nothing is live in it across a call).
'
' Two levels:
'   ClcCombine(n, srcA, srcB, op)  a cell that computes A op B and is enabled: AND, OR, XOR, NAND, NOR, XNOR.
'   ClcMode / ClcSource / ClcGate / ClcPolarity / ClcEdges / ClcEnable: every register of the cell, for the
'   latches and flip-flops and the AND-OR, OR-XOR forms (the set-up order of [26.6]: disable, select the
'   inputs, enable the gates, polarity and mode, pins, then enable).
' A cell needs no clock of its own: it runs from its inputs, also in Sleep [26.5]. CLCxCON is cleared by a
' reset but the selectors, gates and polarities are not [26.4]; ClcMode is therefore always the first call.
' Gate logic with nothing selected is a constant: all gate bits 0 with GyPOL = 0 is 0, with GyPOL = 1 is 1
' [Table 26-1]. ClcCombine uses that for its unused gates.
'
' Input sources (the DyS value) are the codes of [26.1.1 p.409]: ClcInCLCIN0..ClcInCLCIN7 (0..7, the pins
' set by ClcInputPin), ClcInFosc 8, ClcInHfintosc 9, ClcInLfintosc 10, ClcInClkr 16, ClcInTmr0 17, ClcInTmr1 18,
' ClcInTmr2 19, ClcInCcp1 24, ClcInCcp2 25, ClcInPwm3 26, ClcInPwm4 27, ClcInCmp1 28, ClcInCmp2 29, ClcInCwg1A 49,
' ClcInCwg1B 50 and ClcInClc1..ClcInClc8 (33..40, the output of another cell). Others are in the data sheet table.
'
' Pins: ClcInputPin(i, pin) routes CLCINi to a pin through CLCINiPPS (the code is the pin number) and makes it a
' digital input; i = 0, 1, 4, 5 reach ports A and C, i = 2, 3, 6, 7 ports B and C [Table 18-1 p.286, 28-pin part].
' ClcOutputPin(n, pin) sends the cell output to a pin through RxyPPS = 18h + n - 1 [Table 18-2 p.287]: cells
' 1, 2, 5, 6 reach port A and port C, cells 3, 4, 7, 8 port B and port C. Both return False (and change nothing) for a
' pin or cell the part cannot route. The 40/44-pin PIC18F47Q10 routes differently (ports B and D for cells 3, 4, 7, 8) and is
' not a supported part, so the module stops with #error on a part with port D.
'
' Interrupt: ClcEdges(n, rising, falling) sets INTP / INTN. The flag CLCnIF (PIR) and enable CLCnIE (PIE) are the
' program's: clear the flag in the handler [26.2]. Changing the polarity while an edge is enabled raises an interrupt [26.1.4].
' The routines are not reentrant: do not call them from a handler and from the main program.
#if Not (_has(CLC8CON) And _has(PRODL))
#error "clc needs a PIC18 part with eight CLCs (PIC18F27Q10)"
#endif
#if _has(LATD)
#error "clc: the pin routing of the 40/44-pin Q10 differs; only the 28-pin PIC18F27Q10 is supported"
#endif

Public Const ClcModeAndOr = 0
Public Const ClcModeOrXor = 1
Public Const ClcModeAnd4 = 2
Public Const ClcModeSr = 3
Public Const ClcModeDffSr = 4
Public Const ClcModeDffR = 5
Public Const ClcModeJk = 6
Public Const ClcModeLatch = 7

Public Const ClcOpAnd = 0
Public Const ClcOpOr = 1
Public Const ClcOpXor = 2
Public Const ClcOpNand = 3
Public Const ClcOpNor = 4
Public Const ClcOpXnor = 5

' Gate masks (CLCxGLSy): the true and the negated form of input 1..4 [CLCxGLS0 p.422: bit 1 = G1D1T, bit 0 = G1D1N ...].
Public Const ClcD1T = 2
Public Const ClcD1N = 1
Public Const ClcD2T = 8
Public Const ClcD2N = 4
Public Const ClcD3T = 32
Public Const ClcD3N = 16
Public Const ClcD4T = 128
Public Const ClcD4N = 64

' Polarity byte (CLCxPOL): the output invert bit and the four gate output invert bits [p.417].
Public Const ClcInvOut = 128
Public Const ClcInvG1 = 1
Public Const ClcInvG2 = 2
Public Const ClcInvG3 = 4
Public Const ClcInvG4 = 8

Public Const ClcInCLCIN0 = 0
Public Const ClcInCLCIN1 = 1
Public Const ClcInCLCIN2 = 2
Public Const ClcInCLCIN3 = 3
Public Const ClcInCLCIN4 = 4
Public Const ClcInCLCIN5 = 5
Public Const ClcInCLCIN6 = 6
Public Const ClcInCLCIN7 = 7
Public Const ClcInFosc = 8
Public Const ClcInHfintosc = 9
Public Const ClcInLfintosc = 10
Public Const ClcInClkr = 16
Public Const ClcInTmr0 = 17
Public Const ClcInTmr1 = 18
Public Const ClcInTmr2 = 19
Public Const ClcInCcp1 = 24
Public Const ClcInCcp2 = 25
Public Const ClcInPwm3 = 26
Public Const ClcInPwm4 = 27
Public Const ClcInCmp1 = 28
Public Const ClcInCmp2 = 29
Public Const ClcInCwg1A = 49
Public Const ClcInCwg1B = 50
Public Const ClcInClc1 = 33
Public Const ClcInClc2 = 34
Public Const ClcInClc3 = 35
Public Const ClcInClc4 = 36
Public Const ClcInClc5 = 37
Public Const ClcInClc6 = 38
Public Const ClcInClc7 = 39
Public Const ClcInClc8 = 40

' Register offsets inside a cell's block of ten registers [p.414].
Const OffCon = 0
Const OffPol = 1
Const OffSel = 2
Const OffGls = 6

' CLCxCON bits [p.416].
Const BitEn = 128
Const BitIntp = 16
Const BitIntn = 8

' True for a cell number the part has (1..8).
Public Function ClcOk(ByVal n As Byte) As Boolean
    Result = n >= 1 And n <= 8
End Function

' Register `off` of cell n := (register And Not clr) Or setv; the cell number is not checked here.
Sub Modify(ByVal n As Byte, ByVal off As Byte, ByVal clr As Byte, ByVal setv As Byte)
    Asm
        decf CLC_MODIFY__N, w, c
        mullw 10
        lfsr 0, CLC1CON
        movf PRODL, w, c
        addwf CLC_MODIFY__OFF, w, c
        addwf FSR0L, f, c
        comf CLC_MODIFY__CLR, w, c
        andwf INDF0, w, c
        iorwf CLC_MODIFY__SETV, w, c
        movwf INDF0, c
    End Asm
End Sub

' Register `off` of cell n := v (the cell number is not checked here).
Sub Put(ByVal n As Byte, ByVal off As Byte, ByVal v As Byte)
    Asm
        decf CLC_PUT__N, w, c
        mullw 10
        lfsr 0, CLC1CON
        movf PRODL, w, c
        addwf CLC_PUT__OFF, w, c
        addwf FSR0L, f, c
        movf CLC_PUT__V, w, c
        movwf INDF0, c
    End Asm
End Sub

' RxyPPS of the pin (pins 0..23, consecutive from RA0PPS) := code.
Sub PutPps(ByVal pin As Byte, ByVal code As Byte)
    Asm
        lfsr 0, RA0PPS
        movf CLC_PUTPPS__PIN, w, c
        addwf FSR0L, f, c
        movf CLC_PUTPPS__CODE, w, c
        movwf INDF0, c
    End Asm
End Sub

' CLCINiPPS := pin number (i = 0..7, the registers are consecutive from CLCIN0PPS).
Sub PutIn(ByVal i As Byte, ByVal pin As Byte)
    Asm
        lfsr 0, CLCIN0PPS
        movf CLC_PUTIN__I, w, c
        addwf FSR0L, f, c
        movf CLC_PUTIN__PIN, w, c
        movwf INDF0, c
    End Asm
End Sub

' Disables cell n and sets its function (ClcMode*): CLCxCON = mode, so the cell is off and no edge interrupt is enabled.
Public Sub ClcMode(ByVal n As Byte, ByVal mode As Byte)
    If n < 1 Or n > 8 Then
        Exit
    End If
    Put(n, OffCon, mode And 7)
End Sub

' Input d (1..4) of cell n := source (0..63, ClcIn*).
Public Sub ClcSource(ByVal n As Byte, ByVal d As Byte, ByVal source As Byte)
    If n < 1 Or n > 8 Or d < 1 Or d > 4 Then
        Exit
    End If
    Put(n, OffSel + d - 1, source And 63)
End Sub

' Gate g (1..4) of cell n := mask, the ClcDyT / ClcDyN bits of the inputs it takes (0 = the gate is a constant, see ClcPolarity).
Public Sub ClcGate(ByVal n As Byte, ByVal g As Byte, ByVal mask As Byte)
    If n < 1 Or n > 8 Or g < 1 Or g > 4 Then
        Exit
    End If
    Put(n, OffGls + g - 1, mask)
End Sub

' CLCxPOL := pol: ClcInvOut and the ClcInvG1..ClcInvG4 bits.
Public Sub ClcPolarity(ByVal n As Byte, ByVal pol As Byte)
    If n < 1 Or n > 8 Then
        Exit
    End If
    Put(n, OffPol, pol And 143)
End Sub

' Edge interrupt enables of cell n: a rising edge (INTP) and a falling edge (INTN) of its output set CLCnIF.
Public Sub ClcEdges(ByVal n As Byte, ByVal rising As Boolean, ByVal falling As Boolean)
    Dim v As Byte
    If n < 1 Or n > 8 Then
        Exit
    End If
    v = 0
    If rising Then
        v = BitIntp
    End If
    If falling Then
        v = v Or BitIntn
    End If
    Modify(n, OffCon, BitIntp Or BitIntn, v)
End Sub

' Enables cell n (EN = 1): last, after the inputs, gates, mode, polarity and pins are set.
Public Sub ClcEnable(ByVal n As Byte)
    If n < 1 Or n > 8 Then
        Exit
    End If
    Modify(n, OffCon, 0, BitEn)
End Sub

' Disables cell n: its output is logic 0 [CLCxCON EN p.416].
Public Sub ClcDisable(ByVal n As Byte)
    If n < 1 Or n > 8 Then
        Exit
    End If
    Modify(n, OffCon, BitEn, 0)
End Sub

' CLCxCON .. CLCxGLS3 of cell n in one pass: CON = m (EN = 0), POL = pol, SEL0 = sa, SEL1 = sb, SEL2 and SEL3 untouched, GLS0 = D1T, GLS1 = g2, GLS2 = g3, GLS3 = 0.
Sub CombineRegs(ByVal n As Byte, ByVal m As Byte, ByVal sa As Byte, ByVal sb As Byte, ByVal g2 As Byte, ByVal g3 As Byte, ByVal pol As Byte)
    Asm
        decf CLC_COMBINEREGS__N, w, c
        mullw 10
        lfsr 0, CLC1CON
        movf PRODL, w, c
        addwf FSR0L, f, c
        movf CLC_COMBINEREGS__M, w, c
        movwf POSTINC0, c
        movf CLC_COMBINEREGS__POL, w, c
        movwf POSTINC0, c
        movf CLC_COMBINEREGS__SA, w, c
        movwf POSTINC0, c
        movf CLC_COMBINEREGS__SB, w, c
        movwf POSTINC0, c
        movf POSTINC0, w, c
        movf POSTINC0, w, c
        movlw 2
        movwf POSTINC0, c
        movf CLC_COMBINEREGS__G2, w, c
        movwf POSTINC0, c
        movf CLC_COMBINEREGS__G3, w, c
        movwf POSTINC0, c
        clrf WREG, c
        movwf POSTINC0, c
    End Asm
End Sub

' A cell computing A op B (ClcOp*) from two sources (ClcIn*), enabled. AND uses AND-OR with gates 1 and 2 (D1 and D2),
' OR and XOR use OR-XOR (OR: D1 and D2 in gates 1 and 2; XOR: D1 in gate 1, D2 in gate 3); the unused gates are constant 0,
' so (g1 AND g2) OR 0, (g1 OR g2) XOR 0 and (g1 OR 0) XOR (g3 OR 0). NAND, NOR and XNOR set the output polarity.
' CLCxPOL is written whole, so a polarity set earlier with ClcPolarity is replaced; inputs 3 and 4 and edge enables are cleared (CLCxCON is written).
Public Sub ClcCombine(ByVal n As Byte, ByVal srcA As Byte, ByVal srcB As Byte, ByVal op As Byte)
    Dim f As Byte
    Dim m As Byte
    Dim g2 As Byte
    Dim g3 As Byte
    Dim pol As Byte
    If n < 1 Or n > 8 Or op > 5 Then
        Exit
    End If
    f = op
    pol = 0
    If op > 2 Then
        f = op - 3
        pol = ClcInvOut
    End If
    m = ClcModeOrXor
    If f = 0 Then
        m = ClcModeAndOr
    End If
    g2 = ClcD2T
    g3 = 0
    If f = 2 Then
        g2 = 0
        g3 = ClcD2T
    End If
    CombineRegs(n, m, srcA And 63, srcB And 63, g2, g3, pol)
    Modify(n, OffCon, 0, BitEn)
End Sub

' Output of cell n (True = high): CLCxCON.OUT, sampled from CLCxOUT [p.416]. False for a cell the part does not have.
Public Function ClcOutput(ByVal n As Byte) As Boolean
    Result = False
    If n < 1 Or n > 8 Then
        Exit
    End If
    Asm
        decf CLC_CLCOUTPUT__N, w, c
        mullw 10
        lfsr 0, CLC1CON
        movf PRODL, w, c
        addwf FSR0L, f, c
        clrf CLC_CLCOUTPUT__RESULT, c
        btfsc INDF0, 5, c
        incf CLC_CLCOUTPUT__RESULT, f, c
    End Asm
End Function

' The outputs of all eight cells at one instant, bit n - 1 = cell n (CLCDATA mirror copies [26.3 p.412]).
Public Function ClcOutputs() As Byte
    Result = CLCDATA
End Function

' Routes input i (0..7, ClcInCLCIN0..7) of the cells to a pin and makes it a digital input. False if the pin is not one that input reaches.
Public Function ClcInputPin(ByVal i As Byte, ByVal pin As Byte) As Boolean
    Dim port As Byte
    Result = False
    If i > 7 Or pin >= 24 Then
        Exit
    End If
    port = pin >> 3
    If port = 1 Then
        If (i And 2) = 0 Then
            Exit
        End If
    ElseIf port = 0 Then
        If (i And 2) <> 0 Then
            Exit
        End If
    End If
    PutIn(i, pin)
    Pinio.PinInput(pin)
    Result = True
End Function

' Sends the output of cell n to a pin (a digital output). False if the cell cannot reach that pin.
Public Function ClcOutputPin(ByVal n As Byte, ByVal pin As Byte) As Boolean
    Dim port As Byte
    Dim grp As Byte
    Result = False
    If n < 1 Or n > 8 Or pin >= 24 Then
        Exit
    End If
    port = pin >> 3
    grp = (n - 1) And 2
    If port = 0 Then
        If grp <> 0 Then
            Exit
        End If
    ElseIf port = 1 Then
        If grp = 0 Then
            Exit
        End If
    End If
    PutPps(pin, 23 + n)
    Pinio.PinOutput(pin)
    Result = True
End Function
