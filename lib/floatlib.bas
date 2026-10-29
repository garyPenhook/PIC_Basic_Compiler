Module FloatLib
' Single-precision (IEEE-754 binary32) arithmetic for the Float type.
'
' The compiler includes this module by itself when a program mentions Float, and turns every Float
' operation into a call to one of the routines below; nothing here needs to be called by hand.
' A Float is held as its 32-bit pattern in a LongWord: sign (bit 31), biased exponent (bits 30..23),
' 23 fraction bits. Only the routines a program uses are linked.
'
' Behaviour: round to nearest, ties to even. Infinities and NaN are produced and propagated
' (every NaN is $7FC00000). Denormals are not supported: an exponent field of 0 is read as zero and
' a result too small for a normal number becomes a signed zero.
'
' The routines are written in assembly on the compiler's scratch registers __A..__D (a call never
' leaves anything live there). The mantissa work uses a byte-aligned 32-bit form: the leading one at
' bit 31, 23 fraction bits below it, then eight more bits (guard first, sticky merged into bit 0).
' Pack rounds that form and assembles the result.

#if Not _has(PRODL)
#error "floatlib is written in PIC18 assembly (PRODL, movff); Float is not available on the enhanced mid-range core yet"
#endif

Const NaNBits As LongWord = $7FC00000
Const SignBit As LongWord = $80000000

' Builds the result: sign in __D0 (bit 7 only), biased exponent of the leading one in __C1:__C0
' (signed), mantissa in __A3..__A0 with the leading one at bit 31 (a 24-bit mantissa in __A3..__A1
' and the bits below it in __A0). Rounds to nearest even on __A0 and leaves the float in __A3..__A0.
Private Sub Pack()
    Asm
        btfsc __C1, 7, c
        bra FLP_UNDER
        movlw 0x80
        cpfseq __A0, c
        bra FLP_NE
        btfss __A1, 0, c
        bra FLP_RD
        bra FLP_UP
    FLP_NE:
        cpfsgt __A0, c
        bra FLP_RD
    FLP_UP:
        movlw 1
        addwf __A1, f, c
        movlw 0
        addwfc __A2, f, c
        addwfc __A3, f, c
        bnc FLP_RD
        movlw 0x80
        movwf __A3, c
        incf __C0, f, c
        btfsc STATUS, 2, c
        incf __C1, f, c
    FLP_RD:
        movf __C1, f, c
        bnz FLP_OVER
        incf __C0, w, c
        bz FLP_OVER
        movf __C0, f, c
        bz FLP_UNDER
        bcf STATUS, 0, c
        rrcf __C0, f, c
        bcf __A3, 7, c
        btfsc STATUS, 0, c
        bsf __A3, 7, c
        movff __A1, __A0
        movff __A2, __A1
        movff __A3, __A2
        movf __C0, w, c
        iorwf __D0, w, c
        movwf __A3, c
        return
    FLP_OVER:
        movlw 0x80
        movwf __A2, c
        movlw 0x7F
        bra FLP_END
    FLP_UNDER:
        clrf __A2, c
        movlw 0
    FLP_END:
        clrf __A0, c
        clrf __A1, c
        iorwf __D0, w, c
        movwf __A3, c
    End Asm
End Sub

Public Function FAdd(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Asm
        movff FLOATLIB_FADD__A, __A0
        movff FLOATLIB_FADD__A+1, __A1
        movff FLOATLIB_FADD__A+2, __A2
        movff FLOATLIB_FADD__A+3, __A3
        movff FLOATLIB_FADD__B, __B0
        movff FLOATLIB_FADD__B+1, __B1
        movff FLOATLIB_FADD__B+2, __B2
        movff FLOATLIB_FADD__B+3, __B3
        movf __A3, w, c
        andlw 0x7F
        movwf __C0, c
        movf __B3, w, c
        andlw 0x7F
        movwf __C1, c
        movf __A0, w, c
        subwf __B0, w, c
        movf __A1, w, c
        subwfb __B1, w, c
        movf __A2, w, c
        subwfb __B2, w, c
        movf __C0, w, c
        subwfb __C1, w, c
        bnc FLA_OK
        movf __A0, w, c
        movff __B0, __A0
        movwf __B0, c
        movf __A1, w, c
        movff __B1, __A1
        movwf __B1, c
        movf __A2, w, c
        movff __B2, __A2
        movwf __B2, c
        movf __A3, w, c
        movff __B3, __A3
        movwf __B3, c
    FLA_OK:
        movf __A3, w, c
        andlw 0x80
        movwf __D0, c
        movf __B3, w, c
        andlw 0x80
        movwf __D1, c
        rlcf __A2, w, c
        rlcf __A3, w, c
        movwf __C0, c
        rlcf __B2, w, c
        rlcf __B3, w, c
        movwf __D2, c
        clrf __C1, c
        incf __C0, w, c
        bnz FLA_FIN
        movf __A2, w, c
        andlw 0x7F
        iorwf __A1, w, c
        iorwf __A0, w, c
        bnz FLA_NAN
        incf __D2, w, c
        bnz FLA_RET
        movf __D0, w, c
        xorwf __D1, w, c
        bz FLA_RET
    FLA_NAN:
        clrf __A0, c
        clrf __A1, c
        movlw 0xC0
        movwf __A2, c
        movlw 0x7F
        movwf __A3, c
        bra FLA_RET
    FLA_FIN:
        movf __D2, f, c
        bnz FLA_NORM
        movf __C0, f, c
        bnz FLA_RET
        movf __D1, w, c
        andwf __D0, w, c
        clrf __A0, c
        clrf __A1, c
        clrf __A2, c
        movwf __A3, c
        bra FLA_RET
    FLA_NORM:
        bsf __A2, 7, c
        movff __A2, __A3
        movff __A1, __A2
        movff __A0, __A1
        clrf __A0, c
        bsf __B2, 7, c
        movff __B2, __B3
        movff __B1, __B2
        movff __B0, __B1
        clrf __B0, c
        movf __D2, w, c
        subwf __C0, w, c
        bz FLA_AL
        movwf __D3, c
        movlw 32
        cpfslt __D3, c
        bra FLA_FAR
    FLA_SH:
        btfsc __B0, 0, c
        bsf __D1, 0, c
        bcf STATUS, 0, c
        rrcf __B3, f, c
        rrcf __B2, f, c
        rrcf __B1, f, c
        rrcf __B0, f, c
        decfsz __D3, f, c
        bra FLA_SH
        btfsc __D1, 0, c
        bsf __B0, 0, c
        bra FLA_AL
    FLA_FAR:
        clrf __B3, c
        clrf __B2, c
        clrf __B1, c
        movlw 1
        movwf __B0, c
    FLA_AL:
        movf __D0, w, c
        xorwf __D1, w, c
        andlw 0x80
        bnz FLA_SUB
        movf __B0, w, c
        addwf __A0, f, c
        movf __B1, w, c
        addwfc __A1, f, c
        movf __B2, w, c
        addwfc __A2, f, c
        movf __B3, w, c
        addwfc __A3, f, c
        bnc FLA_PK
        rrcf __A3, f, c
        rrcf __A2, f, c
        rrcf __A1, f, c
        rrcf __A0, f, c
        btfsc STATUS, 0, c
        bsf __A0, 0, c
        incf __C0, f, c
        bra FLA_PK
    FLA_SUB:
        movf __B0, w, c
        subwf __A0, f, c
        movf __B1, w, c
        subwfb __A1, f, c
        movf __B2, w, c
        subwfb __A2, f, c
        movf __B3, w, c
        subwfb __A3, f, c
        movf __A0, w, c
        iorwf __A1, w, c
        iorwf __A2, w, c
        iorwf __A3, w, c
        bz FLA_RET
    FLA_NL:
        btfsc __A3, 7, c
        bra FLA_PK
        movf __A3, f, c
        bnz FLA_BIT
        movff __A2, __A3
        movff __A1, __A2
        movff __A0, __A1
        clrf __A0, c
        movlw 8
        subwf __C0, f, c
        movlw 0
        subwfb __C1, f, c
        bra FLA_NL
    FLA_BIT:
        bcf STATUS, 0, c
        rlcf __A0, f, c
        rlcf __A1, f, c
        rlcf __A2, f, c
        rlcf __A3, f, c
        movlw 1
        subwf __C0, f, c
        movlw 0
        subwfb __C1, f, c
        bra FLA_NL
    FLA_PK:
    End Asm
    Pack()
    Asm
    FLA_RET:
        movff __A0, FLOATLIB_FADD__RESULT
        movff __A1, FLOATLIB_FADD__RESULT+1
        movff __A2, FLOATLIB_FADD__RESULT+2
        movff __A3, FLOATLIB_FADD__RESULT+3
    End Asm
End Function

Public Function FSub(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Result = FAdd(a, b Xor SignBit)
End Function

Public Function FMul(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Asm
        movff FLOATLIB_FMUL__A, __B0
        movff FLOATLIB_FMUL__A+1, __B1
        movff FLOATLIB_FMUL__A+2, __B2
        movff FLOATLIB_FMUL__A+3, __A3
        movff FLOATLIB_FMUL__B, __B3
        movff FLOATLIB_FMUL__B+1, __C2
        movff FLOATLIB_FMUL__B+2, __C3
        movff FLOATLIB_FMUL__B+3, __D2
        movf __A3, w, c
        xorwf __D2, w, c
        andlw 0x80
        movwf __D0, c
        rlcf __B2, w, c
        rlcf __A3, w, c
        movwf __C0, c
        rlcf __C3, w, c
        rlcf __D2, w, c
        movwf __D2, c
        incf __C0, w, c
        bnz FLM_1
        movf __B2, w, c
        andlw 0x7F
        iorwf __B1, w, c
        iorwf __B0, w, c
        bnz FLM_NAN
    FLM_1:
        incf __D2, w, c
        bnz FLM_2
        movf __C3, w, c
        andlw 0x7F
        iorwf __C2, w, c
        iorwf __B3, w, c
        bnz FLM_NAN
    FLM_2:
        incf __C0, w, c
        bz FLM_AI
        incf __D2, w, c
        bnz FLM_FIN
        movf __C0, f, c
        bz FLM_NAN
        bra FLM_INF
    FLM_AI:
        movf __D2, f, c
        bz FLM_NAN
    FLM_INF:
        clrf __A0, c
        clrf __A1, c
        movlw 0x80
        movwf __A2, c
        movlw 0x7F
        bra FLM_SG
    FLM_NAN:
        clrf __A0, c
        clrf __A1, c
        movlw 0xC0
        movwf __A2, c
        movlw 0x7F
        bra FLM_OUT
    FLM_ZERO:
        clrf __A0, c
        clrf __A1, c
        clrf __A2, c
        movlw 0
    FLM_SG:
        iorwf __D0, w, c
    FLM_OUT:
        movwf __A3, c
        bra FLM_RET
    FLM_FIN:
        movf __C0, f, c
        bz FLM_ZERO
        movf __D2, f, c
        bz FLM_ZERO
        movf __D2, w, c
        addwf __C0, f, c
        clrf __C1, c
        movlw 0
        addwfc __C1, f, c
        movlw 127
        subwf __C0, f, c
        movlw 0
        subwfb __C1, f, c
        bsf __B2, 7, c
        bsf __C3, 7, c
        clrf __D1, c
        clrf __D3, c
        clrf __A0, c
        clrf __A1, c
        clrf __A2, c
        clrf __A3, c
        movf __B3, w, c
        mulwf __B0, c
        movf PRODL, w, c
        addwf __D1, f, c
        movf PRODH, w, c
        addwfc __D3, f, c
        movlw 0
        addwfc __A0, f, c
        addwfc __A1, f, c
        addwfc __A2, f, c
        addwfc __A3, f, c
        movf __C2, w, c
        mulwf __B0, c
        movf PRODL, w, c
        addwf __D3, f, c
        movf PRODH, w, c
        addwfc __A0, f, c
        movlw 0
        addwfc __A1, f, c
        addwfc __A2, f, c
        addwfc __A3, f, c
        movf __C3, w, c
        mulwf __B0, c
        movf PRODL, w, c
        addwf __A0, f, c
        movf PRODH, w, c
        addwfc __A1, f, c
        movlw 0
        addwfc __A2, f, c
        addwfc __A3, f, c
        movf __B3, w, c
        mulwf __B1, c
        movf PRODL, w, c
        addwf __D3, f, c
        movf PRODH, w, c
        addwfc __A0, f, c
        movlw 0
        addwfc __A1, f, c
        addwfc __A2, f, c
        addwfc __A3, f, c
        movf __C2, w, c
        mulwf __B1, c
        movf PRODL, w, c
        addwf __A0, f, c
        movf PRODH, w, c
        addwfc __A1, f, c
        movlw 0
        addwfc __A2, f, c
        addwfc __A3, f, c
        movf __C3, w, c
        mulwf __B1, c
        movf PRODL, w, c
        addwf __A1, f, c
        movf PRODH, w, c
        addwfc __A2, f, c
        movlw 0
        addwfc __A3, f, c
        movf __B3, w, c
        mulwf __B2, c
        movf PRODL, w, c
        addwf __A0, f, c
        movf PRODH, w, c
        addwfc __A1, f, c
        movlw 0
        addwfc __A2, f, c
        addwfc __A3, f, c
        movf __C2, w, c
        mulwf __B2, c
        movf PRODL, w, c
        addwf __A1, f, c
        movf PRODH, w, c
        addwfc __A2, f, c
        movlw 0
        addwfc __A3, f, c
        movf __C3, w, c
        mulwf __B2, c
        movf PRODL, w, c
        addwf __A2, f, c
        movf PRODH, w, c
        addwfc __A3, f, c
        movf __D3, w, c
        iorwf __D1, w, c
        bz FLM_NS
        bsf __A0, 0, c
    FLM_NS:
        btfsc __A3, 7, c
        bra FLM_TOP
        bcf STATUS, 0, c
        rlcf __D3, f, c
        rlcf __A0, f, c
        rlcf __A1, f, c
        rlcf __A2, f, c
        rlcf __A3, f, c
        bra FLM_PK
    FLM_TOP:
        incf __C0, f, c
        btfsc STATUS, 2, c
        incf __C1, f, c
    FLM_PK:
    End Asm
    Pack()
    Asm
    FLM_RET:
        movff __A0, FLOATLIB_FMUL__RESULT
        movff __A1, FLOATLIB_FMUL__RESULT+1
        movff __A2, FLOATLIB_FMUL__RESULT+2
        movff __A3, FLOATLIB_FMUL__RESULT+3
    End Asm
End Function

Public Function FDiv(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Asm
        movff FLOATLIB_FDIV__A, __B0
        movff FLOATLIB_FDIV__A+1, __B1
        movff FLOATLIB_FDIV__A+2, __B2
        movff FLOATLIB_FDIV__A+3, __A3
        movff FLOATLIB_FDIV__B, __C2
        movff FLOATLIB_FDIV__B+1, __C3
        movff FLOATLIB_FDIV__B+2, __D1
        movff FLOATLIB_FDIV__B+3, __D2
        movf __A3, w, c
        xorwf __D2, w, c
        andlw 0x80
        movwf __D0, c
        rlcf __B2, w, c
        rlcf __A3, w, c
        movwf __C0, c
        rlcf __D1, w, c
        rlcf __D2, w, c
        movwf __D2, c
        incf __C0, w, c
        bnz FLD_1
        movf __B2, w, c
        andlw 0x7F
        iorwf __B1, w, c
        iorwf __B0, w, c
        bnz FLD_NAN
    FLD_1:
        incf __D2, w, c
        bnz FLD_2
        movf __D1, w, c
        andlw 0x7F
        iorwf __C3, w, c
        iorwf __C2, w, c
        bnz FLD_NAN
    FLD_2:
        incf __C0, w, c
        bnz FLD_3
        incf __D2, w, c
        bz FLD_NAN
        bra FLD_INF
    FLD_3:
        incf __D2, w, c
        bz FLD_ZERO
        movf __D2, f, c
        bnz FLD_5
        movf __C0, f, c
        bz FLD_NAN
    FLD_INF:
        clrf __A0, c
        clrf __A1, c
        movlw 0x80
        movwf __A2, c
        movlw 0x7F
        bra FLD_SG
    FLD_NAN:
        clrf __A0, c
        clrf __A1, c
        movlw 0xC0
        movwf __A2, c
        movlw 0x7F
        bra FLD_OUT
    FLD_5:
        movf __C0, f, c
        bnz FLD_GO
    FLD_ZERO:
        clrf __A0, c
        clrf __A1, c
        clrf __A2, c
        movlw 0
    FLD_SG:
        iorwf __D0, w, c
    FLD_OUT:
        movwf __A3, c
        bra FLD_RET
    FLD_GO:
        clrf __C1, c
        movf __D2, w, c
        subwf __C0, f, c
        movlw 0
        subwfb __C1, f, c
        movlw 127
        addwf __C0, f, c
        movlw 0
        addwfc __C1, f, c
        bsf __B2, 7, c
        bsf __D1, 7, c
        movf __C2, w, c
        subwf __B0, w, c
        movf __C3, w, c
        subwfb __B1, w, c
        movf __D1, w, c
        subwfb __B2, w, c
        bc FLD_LP0
        bcf STATUS, 0, c
        rlcf __B0, f, c
        rlcf __B1, f, c
        rlcf __B2, f, c
        bsf __D0, 0, c
        movlw 1
        subwf __C0, f, c
        movlw 0
        subwfb __C1, f, c
    FLD_LP0:
        movlw 32
        movwf __D3, c
    FLD_LP:
        movf __C2, w, c
        subwf __B0, f, c
        movf __C3, w, c
        subwfb __B1, f, c
        movf __D1, w, c
        subwfb __B2, f, c
        bc FLD_TAKE
        btfsc __D0, 0, c
        bra FLD_TAKE
        movf __C2, w, c
        addwf __B0, f, c
        movf __C3, w, c
        addwfc __B1, f, c
        movf __D1, w, c
        addwfc __B2, f, c
        bcf STATUS, 0, c
        bra FLD_Q
    FLD_TAKE:
        bsf STATUS, 0, c
    FLD_Q:
        rlcf __A0, f, c
        rlcf __A1, f, c
        rlcf __A2, f, c
        rlcf __A3, f, c
        bcf __D0, 0, c
        bcf STATUS, 0, c
        rlcf __B0, f, c
        rlcf __B1, f, c
        rlcf __B2, f, c
        btfsc STATUS, 0, c
        bsf __D0, 0, c
        decfsz __D3, f, c
        bra FLD_LP
        movf __B0, w, c
        iorwf __B1, w, c
        iorwf __B2, w, c
        btfsc __D0, 0, c
        iorlw 1
        bz FLD_ST
        bsf __A0, 0, c
    FLD_ST:
        bcf __D0, 0, c
    End Asm
    Pack()
    Asm
    FLD_RET:
        movff __A0, FLOATLIB_FDIV__RESULT
        movff __A1, FLOATLIB_FDIV__RESULT+1
        movff __A2, FLOATLIB_FDIV__RESULT+2
        movff __A3, FLOATLIB_FDIV__RESULT+3
    End Asm
End Function

' -1, 0 or 1 for a < b, a = b, a > b (+0 equals -0); 2 when either is NaN.
Private Function Cmp(ByVal a As LongWord, ByVal b As LongWord) As ShortInt
    Asm
        movff FLOATLIB_CMP__A, __A0
        movff FLOATLIB_CMP__A+1, __A1
        movff FLOATLIB_CMP__A+2, __A2
        movff FLOATLIB_CMP__A+3, __A3
        movff FLOATLIB_CMP__B, __B0
        movff FLOATLIB_CMP__B+1, __B1
        movff FLOATLIB_CMP__B+2, __B2
        movff FLOATLIB_CMP__B+3, __B3
        movf __A3, w, c
        andlw 0x7F
        xorlw 0x7F
        bnz FLC_B
        btfss __A2, 7, c
        bra FLC_B
        movf __A2, w, c
        andlw 0x7F
        iorwf __A1, w, c
        iorwf __A0, w, c
        bnz FLC_NAN
    FLC_B:
        movf __B3, w, c
        andlw 0x7F
        xorlw 0x7F
        bnz FLC_Z
        btfss __B2, 7, c
        bra FLC_Z
        movf __B2, w, c
        andlw 0x7F
        iorwf __B1, w, c
        iorwf __B0, w, c
        bnz FLC_NAN
    FLC_Z:
        movf __A3, w, c
        andlw 0x7F
        iorwf __A2, w, c
        iorwf __A1, w, c
        iorwf __A0, w, c
        movwf __C0, c
        movf __B3, w, c
        andlw 0x7F
        iorwf __B2, w, c
        iorwf __B1, w, c
        iorwf __B0, w, c
        iorwf __C0, w, c
        bz FLC_EQ
        movf __A3, w, c
        xorwf __B3, w, c
        bn FLC_DIFF
        movff __A3, __D0
        movf __B0, w, c
        subwf __A0, f, c
        movf __B1, w, c
        subwfb __A1, f, c
        movf __B2, w, c
        subwfb __A2, f, c
        movf __B3, w, c
        subwfb __A3, f, c
        movf __A0, w, c
        iorwf __A1, w, c
        iorwf __A2, w, c
        iorwf __A3, w, c
        bz FLC_EQ
        movlw 1
        btfss STATUS, 0, c
        movlw 0xFF
        btfsc __D0, 7, c
        sublw 0
        bra FLC_ST
    FLC_DIFF:
        movlw 0xFF
        btfss __A3, 7, c
        movlw 1
        bra FLC_ST
    FLC_EQ:
        movlw 0
        bra FLC_ST
    FLC_NAN:
        movlw 2
    FLC_ST:
        movwf __A0, c
        movff __A0, FLOATLIB_CMP__RESULT
    End Asm
End Function


Public Function FEq(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Result = Cmp(a, b) = 0
End Function

Public Function FNe(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Result = Cmp(a, b) <> 0
End Function

Public Function FLt(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Result = Cmp(a, b) = -1
End Function

Public Function FLe(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Dim c As ShortInt
    c = Cmp(a, b)
    Result = c = -1 Or c = 0
End Function

Public Function FGt(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Result = Cmp(a, b) = 1
End Function

Public Function FGe(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Dim c As ShortInt
    c = Cmp(a, b)
    Result = c = 1 Or c = 0
End Function

' The Float for the unsigned magnitude in __A3..__A0 and the sign bit in __D0 (bit 7); leaves it in __A3..__A0.
Private Sub FromMag()
    Asm
        movf __A3, w, c
        iorwf __A2, w, c
        iorwf __A1, w, c
        iorwf __A0, w, c
        bnz FLF_GO
        return
    FLF_GO:
        clrf __C1, c
        movlw 158
        movwf __C0, c
    FLF_N:
        btfsc __A3, 7, c
        bra FLF_P
        movf __A3, f, c
        bnz FLF_B
        movff __A2, __A3
        movff __A1, __A2
        movff __A0, __A1
        clrf __A0, c
        movlw 8
        subwf __C0, f, c
        bra FLF_N
    FLF_B:
        bcf STATUS, 0, c
        rlcf __A0, f, c
        rlcf __A1, f, c
        rlcf __A2, f, c
        rlcf __A3, f, c
        decf __C0, f, c
        bra FLF_N
    FLF_P:
    End Asm
    Pack()
End Sub

Public Function FFromLong(ByVal v As LongInt) As LongWord
    Asm
        movff FLOATLIB_FFROMLONG__V, __A0
        movff FLOATLIB_FFROMLONG__V+1, __A1
        movff FLOATLIB_FFROMLONG__V+2, __A2
        movff FLOATLIB_FFROMLONG__V+3, __A3
        movf __A3, w, c
        andlw 0x80
        movwf __D0, c
        bz FLL_P
        comf __A0, f, c
        comf __A1, f, c
        comf __A2, f, c
        comf __A3, f, c
        movlw 1
        addwf __A0, f, c
        movlw 0
        addwfc __A1, f, c
        addwfc __A2, f, c
        addwfc __A3, f, c
    FLL_P:
    End Asm
    FromMag()
    Asm
        movff __A0, FLOATLIB_FFROMLONG__RESULT
        movff __A1, FLOATLIB_FFROMLONG__RESULT+1
        movff __A2, FLOATLIB_FFROMLONG__RESULT+2
        movff __A3, FLOATLIB_FFROMLONG__RESULT+3
    End Asm
End Function

Public Function FFromULong(ByVal v As LongWord) As LongWord
    Asm
        movff FLOATLIB_FFROMULONG__V, __A0
        movff FLOATLIB_FFROMULONG__V+1, __A1
        movff FLOATLIB_FFROMULONG__V+2, __A2
        movff FLOATLIB_FFROMULONG__V+3, __A3
        clrf __D0, c
    End Asm
    FromMag()
    Asm
        movff __A0, FLOATLIB_FFROMULONG__RESULT
        movff __A1, FLOATLIB_FFROMULONG__RESULT+1
        movff __A2, FLOATLIB_FFROMULONG__RESULT+2
        movff __A3, FLOATLIB_FFROMULONG__RESULT+3
    End Asm
End Function

' Truncates toward zero; out of range saturates to the LongInt limits, NaN gives 0.
Public Function FToLong(ByVal a As LongWord) As LongInt
    Asm
        movff FLOATLIB_FTOLONG__A, __A0
        movff FLOATLIB_FTOLONG__A+1, __A1
        movff FLOATLIB_FTOLONG__A+2, __A2
        movff FLOATLIB_FTOLONG__A+3, __A3
        movf __A3, w, c
        andlw 0x80
        movwf __D0, c
        rlcf __A2, w, c
        rlcf __A3, w, c
        movwf __C0, c
        movlw 127
        cpfslt __C0, c
        bra FLT_GE
    FLT_Z:
        clrf __A0, c
        clrf __A1, c
        clrf __A2, c
        clrf __A3, c
        bra FLT_OUT
    FLT_GE:
        movlw 158
        cpfslt __C0, c
        bra FLT_BIG
        bsf __A2, 7, c
        clrf __A3, c
        movlw 150
        cpfslt __C0, c
        bra FLT_L
        movf __C0, w, c
        sublw 150
        movwf __D3, c
    FLT_R:
        bcf STATUS, 0, c
        rrcf __A2, f, c
        rrcf __A1, f, c
        rrcf __A0, f, c
        decfsz __D3, f, c
        bra FLT_R
        bra FLT_NEG
    FLT_L:
        movlw 150
        subwf __C0, w, c
        bz FLT_NEG
        movwf __D3, c
    FLT_LL:
        bcf STATUS, 0, c
        rlcf __A0, f, c
        rlcf __A1, f, c
        rlcf __A2, f, c
        rlcf __A3, f, c
        decfsz __D3, f, c
        bra FLT_LL
    FLT_NEG:
        btfss __D0, 7, c
        bra FLT_OUT
        comf __A0, f, c
        comf __A1, f, c
        comf __A2, f, c
        comf __A3, f, c
        movlw 1
        addwf __A0, f, c
        movlw 0
        addwfc __A1, f, c
        addwfc __A2, f, c
        addwfc __A3, f, c
        bra FLT_OUT
    FLT_BIG:
        incf __C0, w, c
        bnz FLT_SAT
        movf __A2, w, c
        andlw 0x7F
        iorwf __A1, w, c
        iorwf __A0, w, c
        bnz FLT_Z
    FLT_SAT:
        setf __A0, c
        setf __A1, c
        setf __A2, c
        movlw 0x7F
        movwf __A3, c
        btfss __D0, 7, c
        bra FLT_OUT
        clrf __A0, c
        clrf __A1, c
        clrf __A2, c
        movlw 0x80
        movwf __A3, c
    FLT_OUT:
        movff __A0, FLOATLIB_FTOLONG__RESULT
        movff __A1, FLOATLIB_FTOLONG__RESULT+1
        movff __A2, FLOATLIB_FTOLONG__RESULT+2
        movff __A3, FLOATLIB_FTOLONG__RESULT+3
    End Asm
End Function
