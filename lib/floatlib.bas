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

Const NaNBits As LongWord = $7FC00000
Const SignBit As LongWord = $80000000

#if _has(PRODL)
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
    End Asm
End Function

Public Function FMul(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Asm
        movf __A3, w, c
        xorwf __B3, w, c
        andlw 0x80
        movwf __D0, c
        rlcf __A2, w, c
        rlcf __A3, w, c
        movwf __C0, c
        rlcf __B2, w, c
        rlcf __B3, w, c
        movwf __D2, c
        incf __C0, w, c
        bnz FLM_1
        movf __A2, w, c
        andlw 0x7F
        iorwf __A1, w, c
        iorwf __A0, w, c
        bnz FLM_NAN
    FLM_1:
        incf __D2, w, c
        bnz FLM_2
        movf __B2, w, c
        andlw 0x7F
        iorwf __B1, w, c
        iorwf __B0, w, c
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
        movff __A1, __C3
        movff __A2, __B3
        bsf __B3, 7, c
        bsf __B2, 7, c
        movf __B0, w, c
        mulwf __A0, c
        movff PRODL, __D1
        movff PRODH, __D3
        movf __B1, w, c
        mulwf __A0, c
        movf PRODL, w, c
        addwf __D3, f, c
        movlw 0
        addwfc PRODH, w, c
        movwf __C2, c
        movf __B2, w, c
        mulwf __A0, c
        movf PRODL, w, c
        addwf __C2, w, c
        movwf __A0, c
        movlw 0
        addwfc PRODH, w, c
        movwf __A1, c
        clrf __A2, c
        clrf __A3, c
        movf __B0, w, c
        mulwf __C3, c
        movf PRODL, w, c
        addwf __D3, f, c
        movf PRODH, w, c
        addwfc __A0, f, c
        movlw 0
        addwfc __A1, f, c
        addwfc __A2, f, c
        movf __B1, w, c
        mulwf __C3, c
        movf PRODL, w, c
        addwf __A0, f, c
        movf PRODH, w, c
        addwfc __A1, f, c
        movlw 0
        addwfc __A2, f, c
        movf __B2, w, c
        mulwf __C3, c
        movf PRODL, w, c
        addwf __A1, f, c
        movf PRODH, w, c
        addwfc __A2, f, c
        movf __B0, w, c
        mulwf __B3, c
        movf PRODL, w, c
        addwf __A0, f, c
        movf PRODH, w, c
        addwfc __A1, f, c
        movlw 0
        addwfc __A2, f, c
        addwfc __A3, f, c
        movf __B1, w, c
        mulwf __B3, c
        movf PRODL, w, c
        addwf __A1, f, c
        movf PRODH, w, c
        addwfc __A2, f, c
        movlw 0
        addwfc __A3, f, c
        movf __B2, w, c
        mulwf __B3, c
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
    End Asm
End Function

Public Function FDiv(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Asm
        movf __A3, w, c
        xorwf __B3, w, c
        andlw 0x80
        movwf __D0, c
        rlcf __A2, w, c
        rlcf __A3, w, c
        movwf __C0, c
        rlcf __B2, w, c
        rlcf __B3, w, c
        movwf __D2, c
        incf __C0, w, c
        bnz FLD_1
        movf __A2, w, c
        andlw 0x7F
        iorwf __A1, w, c
        iorwf __A0, w, c
        bnz FLD_NAN
    FLD_1:
        incf __D2, w, c
        bnz FLD_2
        movf __B2, w, c
        andlw 0x7F
        iorwf __B1, w, c
        iorwf __B0, w, c
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
        movff __A0, __C2
        movff __A1, __C3
        movff __A2, __D1
        clrf __C1, c
        movf __D2, w, c
        subwf __C0, f, c
        movlw 0
        subwfb __C1, f, c
        movlw 127
        addwf __C0, f, c
        movlw 0
        addwfc __C1, f, c
        bsf __D1, 7, c
        bsf __B2, 7, c
        movf __B0, w, c
        subwf __C2, w, c
        movf __B1, w, c
        subwfb __C3, w, c
        movf __B2, w, c
        subwfb __D1, w, c
        bc FLD_LP0
        bcf STATUS, 0, c
        rlcf __C2, f, c
        rlcf __C3, f, c
        rlcf __D1, f, c
        bsf __D0, 0, c
        movlw 1
        subwf __C0, f, c
        movlw 0
        subwfb __C1, f, c
    FLD_LP0:
        movlw 32
        movwf __D3, c
    FLD_LP:
        movf __B0, w, c
        subwf __C2, f, c
        movf __B1, w, c
        subwfb __C3, f, c
        movf __B2, w, c
        subwfb __D1, f, c
        bc FLD_TAKE
        btfsc __D0, 0, c
        bra FLD_TAKE
        movf __B0, w, c
        addwf __C2, f, c
        movf __B1, w, c
        addwfc __C3, f, c
        movf __B2, w, c
        addwfc __D1, f, c
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
        rlcf __C2, f, c
        rlcf __C3, f, c
        rlcf __D1, f, c
        btfsc STATUS, 0, c
        bsf __D0, 0, c
        decfsz __D3, f, c
        bra FLD_LP
        movf __C2, w, c
        iorwf __C3, w, c
        iorwf __D1, w, c
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
    End Asm
End Function

' -1, 0 or 1 for a < b, a = b, a > b (+0 equals -0); 2 when either is NaN.
Private Function Cmp(ByVal a As LongWord, ByVal b As LongWord) As ShortInt
    Asm
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
    End Asm
End Function


' The sign of a, as Cmp(a, 0) gives it: -1, 0 (either zero) or 1; 2 for NaN. The operand is in __A only.
Private Function FSign(ByVal a As LongWord) As ShortInt
    Asm
        movf __A3, w, c
        andlw 0x7F
        iorwf __A2, w, c
        iorwf __A1, w, c
        iorwf __A0, w, c
        bz FLS_ST
        movf __A3, w, c
        andlw 0x7F
        xorlw 0x7F
        bnz FLS_V
        btfss __A2, 7, c
        bra FLS_V
        movf __A2, w, c
        andlw 0x7F
        iorwf __A1, w, c
        iorwf __A0, w, c
        bz FLS_V
        movlw 2
        bra FLS_ST
    FLS_V:
        movlw 1
        btfsc __A3, 7, c
        movlw 0xFF
    FLS_ST:
    End Asm
End Function

' a times two to the power k (k in __B0, signed; the operand is in __A), the same bits as FMul / FDiv by that
' power of two: a NaN gives the NaN, infinity stays, a zero (or a denormal) gives a signed zero, an exponent
' that reaches 255 gives infinity and one that reaches 0 or below a signed zero.
Public Function FScale(ByVal a As LongWord, ByVal k As ShortInt) As LongWord
    Asm
        rlcf __A2, w, c
        rlcf __A3, w, c
        bz FLK_Z
        movwf __C0, c
        incf __C0, w, c
        bz FLK_S
        movf __B0, w, c
        addwf __C0, f, c
        btfsc __B0, 7, c
        bra FLK_NEG
        bc FLK_INF
        incf __C0, w, c
        bz FLK_INF
        bra FLK_PUT
    FLK_NEG:
        bnc FLK_Z
        movf __C0, f, c
        bz FLK_Z
    FLK_PUT:
        bcf STATUS, 0, c
        rrcf __C0, f, c
        bcf __A2, 7, c
        btfsc STATUS, 0, c
        bsf __A2, 7, c
        movf __A3, w, c
        andlw 0x80
        iorwf __C0, w, c
        movwf __A3, c
        return
    FLK_S:
        movf __A2, w, c
        andlw 0x7F
        iorwf __A1, w, c
        iorwf __A0, w, c
        bz FLK_R
        clrf __A0, c
        clrf __A1, c
        movlw 0xC0
        movwf __A2, c
        movlw 0x7F
        movwf __A3, c
    FLK_R:
        return
    FLK_INF:
        clrf __A0, c
        clrf __A1, c
        movlw 0x80
        movwf __A2, c
        movlw 0x7F
        bra FLK_SG
    FLK_Z:
        clrf __A0, c
        clrf __A1, c
        clrf __A2, c
        movlw 0
    FLK_SG:
        btfsc __A3, 7, c
        iorlw 0x80
        movwf __A3, c
    End Asm
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
        clrf __C1, c
        movlw 158
        movwf __C0, c
    End Asm
    FromMag()
    Asm
    End Asm
End Function

Public Function FFromULong(ByVal v As LongWord) As LongWord
    Asm
        clrf __D0, c
        clrf __C1, c
        movlw 158
        movwf __C0, c
    End Asm
    FromMag()
    Asm
    End Asm
End Function

' A Byte or a Word (only __A0, or __A1:__A0, is read): the same value as FFromULong, entered with the
' magnitude already moved up so that FromMag does not shift whole bytes.
Public Function FFromByte(ByVal v As Byte) As LongWord
    Asm
        clrf __D0, c
        clrf __C1, c
        movlw 134
        movwf __C0, c
        movff __A0, __A3
        clrf __A0, c
        clrf __A1, c
        clrf __A2, c
    End Asm
    FromMag()
    Asm
    End Asm
End Function

Public Function FFromWord(ByVal v As Word) As LongWord
    Asm
        clrf __D0, c
        clrf __C1, c
        movlw 142
        movwf __C0, c
        movff __A1, __A3
        movff __A0, __A2
        clrf __A0, c
        clrf __A1, c
    End Asm
    FromMag()
    Asm
    End Asm
End Function

' Truncates toward zero; out of range saturates to the LongInt limits, NaN gives 0.
Public Function FToLong(ByVal a As LongWord) As LongInt
    Asm
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
    End Asm
End Function
#else
' The enhanced mid-range core (PIC16F171xx) has no hardware multiplier, no MOVFF and no compare-and-skip
' instructions: these are the routines above rewritten for it. The multiply is a 24-step shift-and-add loop,
' rounding and the range compares use SUBWF and the carry, and a conditional branch is a flag test that skips a BRA.
' The results are bit for bit those of the PIC18 routines. Banked operands are reached with MOVLB.

' Builds the result: sign in __D0 (bit 7 only), biased exponent of the leading one in __C1:__C0
' (signed), mantissa in __A3..__A0 with the leading one at bit 31 (a 24-bit mantissa in __A3..__A1
' and the bits below it in __A0). Rounds to nearest even on __A0 and leaves the float in __A3..__A0.
Private Sub Pack()
    Asm
        btfsc __C1, 7
        bra FLP_UNDER
        rrf __A1, w
        movlw 0x7F
        addwfc __A0, w
        btfss STATUS, 0
        bra FLP_RD
        incfsz __A1, f
        bra FLP_RD
        incfsz __A2, f
        bra FLP_RD
        incfsz __A3, f
        bra FLP_RD
        movlw 0x80
        movwf __A3
        incf __C0, f
        btfsc STATUS, 2
        incf __C1, f
    FLP_RD:
        movf __C1, f
        btfss STATUS, 2
        bra FLP_OVER
        incf __C0, w
        btfsc STATUS, 2
        bra FLP_OVER
        movf __C0, f
        btfsc STATUS, 2
        bra FLP_UNDER
        lslf __A3, f
        lsrf __C0, f
        rrf __A3, f
        movf __A1, w
        movwf __A0
        movf __A2, w
        movwf __A1
        movf __A3, w
        movwf __A2
        movf __C0, w
        iorwf __D0, w
        movwf __A3
        return
    FLP_OVER:
        movlw 0x80
        movwf __A2
        movlw 0x7F
        bra FLP_END
    FLP_UNDER:
        clrf __A2
        movlw 0
    FLP_END:
        clrf __A0
        clrf __A1
        iorwf __D0, w
        movwf __A3
    End Asm
End Sub

Public Function FAdd(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Asm
        movf __A3, w
        andlw 0x7F
        movwf __C0
        movf __B3, w
        andlw 0x7F
        movwf __C1
        movf __A0, w
        subwf __B0, w
        movf __A1, w
        subwfb __B1, w
        movf __A2, w
        subwfb __B2, w
        movf __C0, w
        subwfb __C1, w
        btfss STATUS, 0
        bra FLA_OK
        movf __A0, w
        xorwf __B0, w
        xorwf __A0, f
        xorwf __B0, f
        movf __A1, w
        xorwf __B1, w
        xorwf __A1, f
        xorwf __B1, f
        movf __A2, w
        xorwf __B2, w
        xorwf __A2, f
        xorwf __B2, f
        movf __A3, w
        xorwf __B3, w
        xorwf __A3, f
        xorwf __B3, f
    FLA_OK:
        movf __A3, w
        andlw 0x80
        movwf __D0
        movf __B3, w
        andlw 0x80
        movwf __D1
        rlf __A2, w
        rlf __A3, w
        movwf __C0
        rlf __B2, w
        rlf __B3, w
        movwf __D2
        clrf __C1
        incf __C0, w
        btfss STATUS, 2
        bra FLA_FIN
        movf __A2, w
        andlw 0x7F
        iorwf __A1, w
        iorwf __A0, w
        btfss STATUS, 2
        bra FLA_NAN
        incf __D2, w
        btfss STATUS, 2
        bra FLA_RET
        movf __D0, w
        xorwf __D1, w
        btfsc STATUS, 2
        bra FLA_RET
    FLA_NAN:
        clrf __A0
        clrf __A1
        movlw 0xC0
        movwf __A2
        movlw 0x7F
        movwf __A3
        bra FLA_RET
    FLA_FIN:
        movf __D2, f
        btfss STATUS, 2
        bra FLA_NORM
        movf __C0, f
        btfss STATUS, 2
        bra FLA_RET
        movf __D1, w
        andwf __D0, w
        clrf __A0
        clrf __A1
        clrf __A2
        movwf __A3
        bra FLA_RET
    FLA_NORM:
        bsf __A2, 7
        movf __A2, w
        movwf __A3
        movf __A1, w
        movwf __A2
        movf __A0, w
        movwf __A1
        clrf __A0
        bsf __B2, 7
        movf __B2, w
        movwf __B3
        movf __B1, w
        movwf __B2
        movf __B0, w
        movwf __B1
        clrf __B0
        movf __D2, w
        subwf __C0, w
        btfsc STATUS, 2
        bra FLA_AL
        movwf __D3
movlw 32
subwf __D3, w
btfsc STATUS, 0
bra FLA_FAR
    FLA_SH:
        btfsc __B0, 0
        bsf __D1, 0
        lsrf __B3, f
        rrf __B2, f
        rrf __B1, f
        rrf __B0, f
        decfsz __D3, f
        bra FLA_SH
        btfsc __D1, 0
        bsf __B0, 0
        bra FLA_AL
    FLA_FAR:
        clrf __B3
        clrf __B2
        clrf __B1
        movlw 1
        movwf __B0
    FLA_AL:
        movf __D0, w
        xorwf __D1, w
        andlw 0x80
        btfss STATUS, 2
        bra FLA_SUB
        movf __B0, w
        addwf __A0, f
        movf __B1, w
        addwfc __A1, f
        movf __B2, w
        addwfc __A2, f
        movf __B3, w
        addwfc __A3, f
        btfss STATUS, 0
        bra FLA_PK
        rrf __A3, f
        rrf __A2, f
        rrf __A1, f
        rrf __A0, f
        btfsc STATUS, 0
        bsf __A0, 0
        incf __C0, f
        bra FLA_PK
    FLA_SUB:
        movf __B0, w
        subwf __A0, f
        movf __B1, w
        subwfb __A1, f
        movf __B2, w
        subwfb __A2, f
        movf __B3, w
        subwfb __A3, f
        movf __A0, w
        iorwf __A1, w
        iorwf __A2, w
        iorwf __A3, w
        btfsc STATUS, 2
        bra FLA_RET
    FLA_NL:
        btfsc __A3, 7
        bra FLA_PK
        movf __A3, f
        btfss STATUS, 2
        bra FLA_BIT
        movf __A2, w
        movwf __A3
        movf __A1, w
        movwf __A2
        movf __A0, w
        movwf __A1
        clrf __A0
        movlw 8
        subwf __C0, f
        movlw 0
        subwfb __C1, f
        bra FLA_NL
    FLA_BIT:
        lslf __A0, f
        rlf __A1, f
        rlf __A2, f
        rlf __A3, f
        movlw 1
        subwf __C0, f
        movlw 0
        subwfb __C1, f
        bra FLA_NL
    FLA_PK:
    End Asm
        Pack()
    Asm
    FLA_RET:
    End Asm
End Function

Public Function FMul(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Asm
        movf __A3, w
        xorwf __B3, w
        andlw 0x80
        movwf __D0
        rlf __A2, w
        rlf __A3, w
        movwf __C0
        rlf __B2, w
        rlf __B3, w
        movwf __D2
        incf __C0, w
        btfss STATUS, 2
        bra FLM_1
        movf __A2, w
        andlw 0x7F
        iorwf __A1, w
        iorwf __A0, w
        btfss STATUS, 2
        bra FLM_NAN
    FLM_1:
        incf __D2, w
        btfss STATUS, 2
        bra FLM_2
        movf __B2, w
        andlw 0x7F
        iorwf __B1, w
        iorwf __B0, w
        btfss STATUS, 2
        bra FLM_NAN
    FLM_2:
        incf __C0, w
        btfsc STATUS, 2
        bra FLM_AI
        incf __D2, w
        btfss STATUS, 2
        bra FLM_FIN
        movf __C0, f
        btfsc STATUS, 2
        bra FLM_NAN
        bra FLM_INF
    FLM_AI:
        movf __D2, f
        btfsc STATUS, 2
        bra FLM_NAN
    FLM_INF:
        clrf __A0
        clrf __A1
        movlw 0x80
        movwf __A2
        movlw 0x7F
        bra FLM_SG
    FLM_NAN:
        clrf __A0
        clrf __A1
        movlw 0xC0
        movwf __A2
        movlw 0x7F
        bra FLM_OUT
    FLM_ZERO:
        clrf __A0
        clrf __A1
        clrf __A2
        movlw 0
    FLM_SG:
        iorwf __D0, w
    FLM_OUT:
        movwf __A3
        bra FLM_RET
    FLM_FIN:
        movf __C0, f
        btfsc STATUS, 2
        bra FLM_ZERO
        movf __D2, f
        btfsc STATUS, 2
        bra FLM_ZERO
        movf __D2, w
        addwf __C0, f
        clrf __C1
        movlw 0
        addwfc __C1, f
        movlw 127
        subwf __C0, f
        movlw 0
        subwfb __C1, f
        movf __A0, w
        movwf __D1
        movf __A1, w
        movwf __D3
        movf __A2, w
        iorlw 0x80
        movwf __A0
        bsf __B2, 7
        clrf __A1
        clrf __A2
        clrf __A3
        movlw 24
        movwf __D2
    FLM_ML:
        bcf STATUS, 0
        btfss __D1, 0
        bra FLM_SH
        movf __B0, w
        addwf __A1, f
        movf __B1, w
        addwfc __A2, f
        movf __B2, w
        addwfc __A3, f
    FLM_SH:
        rrf __A3, f
        rrf __A2, f
        rrf __A1, f
        rrf __A0, f
        rrf __D3, f
        rrf __D1, f
        decfsz __D2, f
        bra FLM_ML
        movf __D3, w
        iorwf __D1, w
        btfss STATUS, 2
        bsf __A0, 0
        btfsc __A3, 7
        bra FLM_TOP
        lslf __D3, f
        rlf __A0, f
        rlf __A1, f
        rlf __A2, f
        rlf __A3, f
        bra FLM_PK
    FLM_TOP:
        incf __C0, f
        btfsc STATUS, 2
        incf __C1, f
    FLM_PK:
    End Asm
        Pack()
    Asm
    FLM_RET:
    End Asm
End Function

Public Function FDiv(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Asm
        movf __A3, w
        xorwf __B3, w
        andlw 0x80
        movwf __D0
        rlf __A2, w
        rlf __A3, w
        movwf __C0
        rlf __B2, w
        rlf __B3, w
        movwf __D2
        incf __C0, w
        btfss STATUS, 2
        bra FLD_1
        movf __A2, w
        andlw 0x7F
        iorwf __A1, w
        iorwf __A0, w
        btfss STATUS, 2
        bra FLD_NAN
    FLD_1:
        incf __D2, w
        btfss STATUS, 2
        bra FLD_2
        movf __B2, w
        andlw 0x7F
        iorwf __B1, w
        iorwf __B0, w
        btfss STATUS, 2
        bra FLD_NAN
    FLD_2:
        incf __C0, w
        btfss STATUS, 2
        bra FLD_3
        incf __D2, w
        btfsc STATUS, 2
        bra FLD_NAN
        bra FLD_INF
    FLD_3:
        incf __D2, w
        btfsc STATUS, 2
        bra FLD_ZERO
        movf __D2, f
        btfss STATUS, 2
        bra FLD_5
        movf __C0, f
        btfsc STATUS, 2
        bra FLD_NAN
    FLD_INF:
        clrf __A0
        clrf __A1
        movlw 0x80
        movwf __A2
        movlw 0x7F
        bra FLD_SG
    FLD_NAN:
        clrf __A0
        clrf __A1
        movlw 0xC0
        movwf __A2
        movlw 0x7F
        bra FLD_OUT
    FLD_5:
        movf __C0, f
        btfss STATUS, 2
        bra FLD_GO
    FLD_ZERO:
        clrf __A0
        clrf __A1
        clrf __A2
        movlw 0
    FLD_SG:
        iorwf __D0, w
    FLD_OUT:
        movwf __A3
        bra FLD_RET
    FLD_GO:
        movf __A0, w
        movwf __C2
        movf __A1, w
        movwf __C3
        movf __A2, w
        movwf __D1
        clrf __C1
        movf __D2, w
        subwf __C0, f
        movlw 0
        subwfb __C1, f
        movlw 127
        addwf __C0, f
        movlw 0
        addwfc __C1, f
        bsf __D1, 7
        bsf __B2, 7
        movf __B0, w
        subwf __C2, w
        movf __B1, w
        subwfb __C3, w
        movf __B2, w
        subwfb __D1, w
        btfsc STATUS, 0
        bra FLD_LP0
        lslf __C2, f
        rlf __C3, f
        rlf __D1, f
        bsf __D0, 0
        movlw 1
        subwf __C0, f
        movlw 0
        subwfb __C1, f
    FLD_LP0:
        movlw 32
        movwf __D3
    FLD_LP:
        movf __B0, w
        subwf __C2, f
        movf __B1, w
        subwfb __C3, f
        movf __B2, w
        subwfb __D1, f
        btfsc STATUS, 0
        bra FLD_TAKE
        btfsc __D0, 0
        bra FLD_TAKE
        movf __B0, w
        addwf __C2, f
        movf __B1, w
        addwfc __C3, f
        movf __B2, w
        addwfc __D1, f
        bcf STATUS, 0
        bra FLD_Q
    FLD_TAKE:
        bsf STATUS, 0
    FLD_Q:
        rlf __A0, f
        rlf __A1, f
        rlf __A2, f
        rlf __A3, f
        bcf __D0, 0
        lslf __C2, f
        rlf __C3, f
        rlf __D1, f
        btfsc STATUS, 0
        bsf __D0, 0
        decfsz __D3, f
        bra FLD_LP
        movf __C2, w
        iorwf __C3, w
        iorwf __D1, w
        btfsc __D0, 0
        iorlw 1
        btfsc STATUS, 2
        bra FLD_ST
        bsf __A0, 0
    FLD_ST:
        bcf __D0, 0
    End Asm
        Pack()
    Asm
    FLD_RET:
    End Asm
End Function

' -1, 0 or 1 for a < b, a = b, a > b (+0 equals -0); 2 when either is NaN.
Private Function Cmp(ByVal a As LongWord, ByVal b As LongWord) As ShortInt
    Asm
        movf __A3, w
        andlw 0x7F
        xorlw 0x7F
        btfss STATUS, 2
        bra FLC_B
        btfss __A2, 7
        bra FLC_B
        movf __A2, w
        andlw 0x7F
        iorwf __A1, w
        iorwf __A0, w
        btfss STATUS, 2
        bra FLC_NAN
    FLC_B:
        movf __B3, w
        andlw 0x7F
        xorlw 0x7F
        btfss STATUS, 2
        bra FLC_Z
        btfss __B2, 7
        bra FLC_Z
        movf __B2, w
        andlw 0x7F
        iorwf __B1, w
        iorwf __B0, w
        btfss STATUS, 2
        bra FLC_NAN
    FLC_Z:
        movf __A3, w
        andlw 0x7F
        iorwf __A2, w
        iorwf __A1, w
        iorwf __A0, w
        movwf __C0
        movf __B3, w
        andlw 0x7F
        iorwf __B2, w
        iorwf __B1, w
        iorwf __B0, w
        iorwf __C0, w
        btfsc STATUS, 2
        bra FLC_EQ
        movf __A3, w
xorwf __B3, w
andlw 0x80
btfss STATUS, 2
bra FLC_DIFF
        movf __A3, w
        movwf __D0
        movf __B0, w
        subwf __A0, f
        movf __B1, w
        subwfb __A1, f
        movf __B2, w
        subwfb __A2, f
        movf __B3, w
        subwfb __A3, f
        movf __A0, w
        iorwf __A1, w
        iorwf __A2, w
        iorwf __A3, w
        btfsc STATUS, 2
        bra FLC_EQ
        movlw 1
        btfss STATUS, 0
        movlw 0xFF
        btfsc __D0, 7
        sublw 0
        bra FLC_ST
    FLC_DIFF:
        movlw 0xFF
        btfss __A3, 7
        movlw 1
        bra FLC_ST
    FLC_EQ:
        movlw 0
        bra FLC_ST
    FLC_NAN:
        movlw 2
    FLC_ST:
    End Asm
End Function


' The sign of a, as Cmp(a, 0) gives it: -1, 0 (either zero) or 1; 2 for NaN. The operand is in __A only.
Private Function FSign(ByVal a As LongWord) As ShortInt
    Asm
        movf __A3, w
        andlw 0x7F
        iorwf __A2, w
        iorwf __A1, w
        iorwf __A0, w
        btfsc STATUS, 2
        bra FLS_ST
        movf __A3, w
        andlw 0x7F
        xorlw 0x7F
        btfss STATUS, 2
        bra FLS_V
        btfss __A2, 7
        bra FLS_V
        movf __A2, w
        andlw 0x7F
        iorwf __A1, w
        iorwf __A0, w
        btfsc STATUS, 2
        bra FLS_V
        movlw 2
        bra FLS_ST
    FLS_V:
        movlw 1
        btfsc __A3, 7
        movlw 0xFF
    FLS_ST:
    End Asm
End Function

' a times two to the power k (k in __B0, signed; the operand is in __A), the same bits as FMul / FDiv by that
' power of two: a NaN gives the NaN, infinity stays, a zero (or a denormal) gives a signed zero, an exponent
' that reaches 255 gives infinity and one that reaches 0 or below a signed zero.
Public Function FScale(ByVal a As LongWord, ByVal k As ShortInt) As LongWord
    Asm
        rlf __A2, w
        rlf __A3, w
        movwf __C0
        movf __C0, f
        btfsc STATUS, 2
        bra FLK_Z
        incf __C0, w
        btfsc STATUS, 2
        bra FLK_S
        movf __B0, w
        addwf __C0, f
        btfsc __B0, 7
        bra FLK_NEG
        btfsc STATUS, 0
        bra FLK_INF
        incf __C0, w
        btfsc STATUS, 2
        bra FLK_INF
        bra FLK_PUT
    FLK_NEG:
        btfss STATUS, 0
        bra FLK_Z
        movf __C0, f
        btfsc STATUS, 2
        bra FLK_Z
    FLK_PUT:
        lsrf __C0, f
        bcf __A2, 7
        btfsc STATUS, 0
        bsf __A2, 7
        movf __A3, w
        andlw 0x80
        iorwf __C0, w
        movwf __A3
        return
    FLK_S:
        movf __A2, w
        andlw 0x7F
        iorwf __A1, w
        iorwf __A0, w
        btfsc STATUS, 2
        return
        clrf __A0
        clrf __A1
        movlw 0xC0
        movwf __A2
        movlw 0x7F
        movwf __A3
        return
    FLK_INF:
        clrf __A0
        clrf __A1
        movlw 0x80
        movwf __A2
        movlw 0x7F
        bra FLK_SG
    FLK_Z:
        clrf __A0
        clrf __A1
        clrf __A2
        movlw 0
    FLK_SG:
        btfsc __A3, 7
        iorlw 0x80
        movwf __A3
    End Asm
End Function

' The Float for the unsigned magnitude in __A3..__A0 and the sign bit in __D0 (bit 7); leaves it in __A3..__A0.
Private Sub FromMag()
    Asm
        movf __A3, w
        iorwf __A2, w
        iorwf __A1, w
        iorwf __A0, w
        btfss STATUS, 2
        bra FLF_GO
        return
    FLF_GO:
    FLF_N:
        btfsc __A3, 7
        bra FLF_P
        movf __A3, f
        btfss STATUS, 2
        bra FLF_B
        movf __A2, w
        movwf __A3
        movf __A1, w
        movwf __A2
        movf __A0, w
        movwf __A1
        clrf __A0
        movlw 8
        subwf __C0, f
        bra FLF_N
    FLF_B:
        lslf __A0, f
        rlf __A1, f
        rlf __A2, f
        rlf __A3, f
        decf __C0, f
        bra FLF_N
    FLF_P:
    End Asm
        Pack()
End Sub

Public Function FFromLong(ByVal v As LongInt) As LongWord
    Asm
        movf __A3, w
        andlw 0x80
        movwf __D0
        btfsc STATUS, 2
        bra FLL_P
        comf __A0, f
        comf __A1, f
        comf __A2, f
        comf __A3, f
        movlw 1
        addwf __A0, f
        movlw 0
        addwfc __A1, f
        addwfc __A2, f
        addwfc __A3, f
    FLL_P:
        clrf __C1
        movlw 158
        movwf __C0
    End Asm
        FromMag ()
    Asm
    End Asm
End Function

Public Function FFromULong(ByVal v As LongWord) As LongWord
    Asm
        clrf __D0
        clrf __C1
        movlw 158
        movwf __C0
    End Asm
        FromMag ()
    Asm
    End Asm
End Function

' A Byte or a Word (only __A0, or __A1:__A0, is read): the same value as FFromULong, entered with the
' magnitude already moved up so that FromMag does not shift whole bytes.
Public Function FFromByte(ByVal v As Byte) As LongWord
    Asm
        clrf __D0
        clrf __C1
        movlw 134
        movwf __C0
        movf __A0, w
        movwf __A3
        clrf __A0
        clrf __A1
        clrf __A2
    End Asm
        FromMag ()
    Asm
    End Asm
End Function

Public Function FFromWord(ByVal v As Word) As LongWord
    Asm
        clrf __D0
        clrf __C1
        movlw 142
        movwf __C0
        movf __A1, w
        movwf __A3
        movf __A0, w
        movwf __A2
        clrf __A0
        clrf __A1
    End Asm
        FromMag ()
    Asm
    End Asm
End Function

' Truncates toward zero; out of range saturates to the LongInt limits, NaN gives 0.
Public Function FToLong(ByVal a As LongWord) As LongInt
    Asm
        movf __A3, w
        andlw 0x80
        movwf __D0
        rlf __A2, w
        rlf __A3, w
        movwf __C0
movlw 127
subwf __C0, w
btfsc STATUS, 0
bra FLT_GE
    FLT_Z:
        clrf __A0
        clrf __A1
        clrf __A2
        clrf __A3
        bra FLT_OUT
    FLT_GE:
movlw 158
subwf __C0, w
btfsc STATUS, 0
bra FLT_BIG
        bsf __A2, 7
        clrf __A3
movlw 150
subwf __C0, w
btfsc STATUS, 0
bra FLT_L
        movf __C0, w
        sublw 150
        movwf __D3
    FLT_R:
        lsrf __A2, f
        rrf __A1, f
        rrf __A0, f
        decfsz __D3, f
        bra FLT_R
        bra FLT_NEG
    FLT_L:
        movlw 150
        subwf __C0, w
        btfsc STATUS, 2
        bra FLT_NEG
        movwf __D3
    FLT_LL:
        lslf __A0, f
        rlf __A1, f
        rlf __A2, f
        rlf __A3, f
        decfsz __D3, f
        bra FLT_LL
    FLT_NEG:
        btfss __D0, 7
        bra FLT_OUT
        comf __A0, f
        comf __A1, f
        comf __A2, f
        comf __A3, f
        movlw 1
        addwf __A0, f
        movlw 0
        addwfc __A1, f
        addwfc __A2, f
        addwfc __A3, f
        bra FLT_OUT
    FLT_BIG:
        incf __C0, w
        btfss STATUS, 2
        bra FLT_SAT
        movf __A2, w
        andlw 0x7F
        iorwf __A1, w
        iorwf __A0, w
        btfss STATUS, 2
        bra FLT_Z
    FLT_SAT:
movlw 0xFF
movwf __A0
movwf __A1
movwf __A2
        movlw 0x7F
        movwf __A3
        btfss __D0, 7
        bra FLT_OUT
        clrf __A0
        clrf __A1
        clrf __A2
        movlw 0x80
        movwf __A3
    FLT_OUT:
    End Asm
End Function
#endif

Public Function FSub(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Result = FAdd(a, b Xor SignBit)
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

