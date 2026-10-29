; basil output for PIC16F17146
#include <xc.inc>

CONFIG CONFIG1 = 0x3F8C
CONFIG CONFIG2 = 0x3FFF
CONFIG CONFIG3 = 0x3F9F
CONFIG CONFIG4 = 0x3FFF
CONFIG CONFIG5 = 0x3FFF

; ---- data (addresses chosen by the compiler)
ISR_N equ 0x048  ; n (2 bytes)
ISR_HITS equ 0x03E  ; hits (2 bytes)
ISR_OK equ 0x058  ; ok (1 byte)
ISR_R1 equ 0x044  ; r1 (4 bytes)
ISR_R2 equ 0x04A  ; r2 (4 bytes)
ISR_HV equ 0x04E  ; hv (8 bytes)
ISR_ARR equ 0x02C  ; arr (8 bytes)
ISR_TICK__J equ 0x059  ; j (1 byte)
ISR_TICK__P equ 0x040  ; p (2 bytes)
ISR_MIX__X equ 0x037  ; x (2 bytes)
ISR_MIX__RESULT equ 0x034  ; Result (2 bytes)
ISR_WORK__RESULT equ 0x039  ; Result (4 bytes)
ISR_WORK__I equ 0x07D  ; i (1 byte)
ISR_WORK__ACC equ 0x020  ; acc (4 bytes)
ISR_WORK__W equ 0x07E  ; w (2 bytes)
ISR_WORK__K equ 0x036  ; k (1 byte)
ISR_WORK__H1 equ 0x03D  ; (hidden) (1 byte)
ISR_MIX__T equ 0x042  ; t (2 bytes)
__A0 equ 0x070
__A1 equ 0x071
__A2 equ 0x072
__A3 equ 0x073
__B0 equ 0x074
__B1 equ 0x075
__B2 equ 0x076
__B3 equ 0x077
__C0 equ 0x078
__C1 equ 0x079
__C2 equ 0x07A
__C3 equ 0x07B
__D0 equ 0x07C
ISR_TICK__TMP equ 0x056
ISR_WORK__TMP equ 0x024
__SAV0 equ 0x05A
__ISV0 equ 0x0A0

PSECT code,class=CODE,abs,delta=2
    ORG 0x0000
    goto __reset
    ORG 0x0004
    ; Interrupt Tick
__ISR_H:
ISR_TICK:
    movf __A0, w
    movlb 1
    movwf __ISV0
    movf __A1, w
    movwf __ISV0+1
    movf __A2, w
    movwf __ISV0+2
    movf __A3, w
    movwf __ISV0+3
    movf __B0, w
    movwf __ISV0+4
    movf __B1, w
    movwf __ISV0+5
    movf __B2, w
    movwf __ISV0+6
    movf __B3, w
    movwf __ISV0+7
    movf __C0, w
    movwf __ISV0+8
    movf __C1, w
    movwf __ISV0+9
    movf __C2, w
    movwf __ISV0+10
    movf __C3, w
    movwf __ISV0+11
    movf __D0, w
    movwf __ISV0+12
    movlb 1
    bcf PIR0, 5
    movlb 0
    incf ISR_HITS, f
    btfsc STATUS, 2
    incf ISR_HITS+1, f
    movf ISR_HITS, w
    movwf __A0
    movf ISR_HITS+1, w
    movwf __A1
    movlw 0x05
    movwf __B0
    movlw 0x00
    movwf __B1
    call __mul2
    movf __A0, w
    movlb 0
    movwf ISR_TICK__TMP
    movf __A1, w
    movwf ISR_TICK__TMP+1
    movf ISR_HITS, w
    movwf __A0
    movf ISR_HITS+1, w
    movwf __A1
    movlw 0x03
    andwf __A0, f
    clrf __A1
    lslf __A0, f
    rlf __A1, f
    movlw 0x2E
    addwf __A0, w
    movwf FSR0L
    movlw 0x20
    addwfc __A1, w
    movwf FSR0H
    movf ISR_TICK__TMP, w
    movwi 0[FSR0]
    movf ISR_TICK__TMP+1, w
    movwi 1[FSR0]
    movf ISR_HITS, w
    movwf __A0
    movf ISR_HITS+1, w
    movwf __A1
    movlw 0x03
    andwf __A0, f
    clrf __A1
    lslf __A0, f
    rlf __A1, f
    movlw 0x2E
    addwf __A0, w
    movwf FSR0L
    movlw 0x20
    addwfc __A1, w
    movwf FSR0H
    moviw 0[FSR0]
    movwf __A0
    moviw 1[FSR0]
    movwf __A1
    movlw 0x07
    movwf __B0
    movlw 0x00
    movwf __B1
    call __mul2
    movf __A0, w
    movlb 0
    movwf ISR_TICK__P
    movf __A1, w
    movwf ISR_TICK__P+1
    movf ISR_TICK__P, w
    movwf __A0
    movf ISR_TICK__P+1, w
    movwf __A1
    clrf __A1
    movf __A0, w
    movwf ISR_TICK__J
    movf __A0, w
    movwf __SAV0
    movf __A1, w
    movwf __SAV0+1
    movf __A2, w
    movwf __SAV0+2
    movf __A3, w
    movwf __SAV0+3
    movf __B0, w
    movwf __SAV0+4
    movf __B1, w
    movwf __SAV0+5
    movf __B2, w
    movwf __SAV0+6
    movf __B3, w
    movwf __SAV0+7
    movf __C0, w
    movwf __SAV0+8
    movf __C1, w
    movwf __SAV0+9
    movf __C2, w
    movwf __SAV0+10
    movf __C3, w
    movwf __SAV0+11
    movf __D0, w
    movwf __SAV0+12
    movf ISR_MIX__X, w
    movwf __SAV0+13
    movf ISR_MIX__X+1, w
    movwf __SAV0+14
    movf ISR_MIX__RESULT, w
    movwf __SAV0+15
    movf ISR_MIX__RESULT+1, w
    movwf __SAV0+16
    movf ISR_MIX__T, w
    movwf __SAV0+17
    movf ISR_MIX__T+1, w
    movwf __SAV0+18
    movf ISR_TICK__P, w
    movwf __A0
    movf ISR_TICK__P+1, w
    movwf __A1
    movf __A0, w
    movwf ISR_MIX__X
    movf __A1, w
    movwf ISR_MIX__X+1
    call ISR_MIX
    movlb 0
    movf ISR_MIX__RESULT, w
    movwf __A0
    movf ISR_MIX__RESULT+1, w
    movwf __A1
    movf __A0, w
    movwf ISR_TICK__P
    movf __A1, w
    movwf ISR_TICK__P+1
    movf __SAV0, w
    movwf __A0
    movf __SAV0+1, w
    movwf __A1
    movf __SAV0+2, w
    movwf __A2
    movf __SAV0+3, w
    movwf __A3
    movf __SAV0+4, w
    movwf __B0
    movf __SAV0+5, w
    movwf __B1
    movf __SAV0+6, w
    movwf __B2
    movf __SAV0+7, w
    movwf __B3
    movf __SAV0+8, w
    movwf __C0
    movf __SAV0+9, w
    movwf __C1
    movf __SAV0+10, w
    movwf __C2
    movf __SAV0+11, w
    movwf __C3
    movf __SAV0+12, w
    movwf __D0
    movf __SAV0+13, w
    movwf ISR_MIX__X
    movf __SAV0+14, w
    movwf ISR_MIX__X+1
    movf __SAV0+15, w
    movwf ISR_MIX__RESULT
    movf __SAV0+16, w
    movwf ISR_MIX__RESULT+1
    movf __SAV0+17, w
    movwf ISR_MIX__T
    movf __SAV0+18, w
    movwf ISR_MIX__T+1
    movlb 0
    movf ISR_HITS, w
    movwf __A0
    movf ISR_HITS+1, w
    movwf __A1
    movlw 0x2C
    subwf __A0, w
    movlw 0x01
    subwfb __A1, w
    btfsc STATUS, 0
    bra _L2
    movf ISR_HITS, w
    movwf __A0
    movf ISR_HITS+1, w
    movwf __A1
    movlw 0x1F
    andwf __A0, f
    clrf __A1
    movf __A0, w
    movwf ISR_TICK__TMP
    movf __A1, w
    movwf ISR_TICK__TMP+1
    movlw 0xC8
    movwf __A0
    clrf __A1
    movf ISR_TICK__TMP, w
    addwf __A0, f
    movf ISR_TICK__TMP+1, w
    addwfc __A1, f
    movf __A0, w
    movlb 3
    movwf TMR0H
    bra _L1
_L2:
    movlb 3
    clrf T0CON0
_L1:
__isr_end0:
    movlb 1
    movf __ISV0, w
    movwf __A0
    movf __ISV0+1, w
    movwf __A1
    movf __ISV0+2, w
    movwf __A2
    movf __ISV0+3, w
    movwf __A3
    movf __ISV0+4, w
    movwf __B0
    movf __ISV0+5, w
    movwf __B1
    movf __ISV0+6, w
    movwf __B2
    movf __ISV0+7, w
    movwf __B3
    movf __ISV0+8, w
    movwf __C0
    movf __ISV0+9, w
    movwf __C1
    movf __ISV0+10, w
    movwf __C2
    movf __ISV0+11, w
    movwf __C3
    movf __ISV0+12, w
    movwf __D0
    retfie
__reset:
    movlw 0x0C
    movwf FSR0L
    movlw 0x20
    movwf FSR0H
    movlw 8
    movwf __D0
    clrw
_L3:
    movwi FSR0++
    decfsz __D0, f
    bra _L3
    movlb 0
    clrf 0x03E
    clrf 0x03F
    movlw 0x24
    movwf FSR0L
    movlw 0x20
    movwf FSR0H
    movlw 18
    movwf __D0
    clrw
_L4:
    movwi FSR0++
    decfsz __D0, f
    bra _L4
    clrf 0x058
    movlb 1
    bsf PIE0, 5
    bsf INTCON, 6
    bsf INTCON, 7
    call ISR_WORK
    movlb 0
    movf ISR_WORK__RESULT, w
    movwf __A0
    movf ISR_WORK__RESULT+1, w
    movwf __A1
    movf ISR_WORK__RESULT+2, w
    movwf __A2
    movf ISR_WORK__RESULT+3, w
    movwf __A3
    movf __A0, w
    movwf ISR_R1
    movf __A1, w
    movwf ISR_R1+1
    movf __A2, w
    movwf ISR_R1+2
    movf __A3, w
    movwf ISR_R1+3
    clrf ISR_N
    clrf ISR_N+1
    movlw 0x41
    movlb 3
    movwf T0CON1
    movlw 0x80
    movwf T0CON0
    call ISR_WORK
    movlb 0
    movf ISR_WORK__RESULT, w
    movwf __A0
    movf ISR_WORK__RESULT+1, w
    movwf __A1
    movf ISR_WORK__RESULT+2, w
    movwf __A2
    movf ISR_WORK__RESULT+3, w
    movwf __A3
    movf __A0, w
    movwf ISR_R2
    movf __A1, w
    movwf ISR_R2+1
    movf __A2, w
    movwf ISR_R2+2
    movf __A3, w
    movwf ISR_R2+3
_L5:
    movlb 3
    movf T0CON0, f
    btfsc STATUS, 2
    bra _L6
_L7:
    bra _L5
_L6:
_L8:
    bcf INTCON, 7
    btfsc INTCON, 7
    bra _L8
    movlb 0
    movf ISR_HITS, w
    movwf __A0
    movf ISR_HITS+1, w
    movwf __A1
    movf __A0, w
    movwf ISR_N
    movf __A1, w
    movwf ISR_N+1
    movf ISR_R2, w
    xorwf ISR_R1, w
    btfss STATUS, 2
    bra _L10
    movf ISR_R2+1, w
    xorwf ISR_R1+1, w
    btfss STATUS, 2
    bra _L10
    movf ISR_R2+2, w
    xorwf ISR_R1+2, w
    btfss STATUS, 2
    bra _L10
    movf ISR_R2+3, w
    xorwf ISR_R1+3, w
    btfss STATUS, 2
    bra _L10
_L11:
    movlw 0x01
    movlb 0
    movwf ISR_OK
_L10:
_L9:
    movlb 0
    clrf ISR_R1
    clrf ISR_R1+1
    clrf ISR_R1+2
    clrf ISR_R1+3
__halt:
    bra __halt
    ; Sub/Function Mix
ISR_MIX:
    movlb 0
    movf ISR_MIX__X, w
    movwf __A0
    movf ISR_MIX__X+1, w
    movwf __A1
    movlw 0x03
    movwf __B0
    movlw 0x00
    movwf __B1
    call __mul2
    movf __A0, w
    movlb 0
    movwf ISR_MIX__T
    movf __A1, w
    movwf ISR_MIX__T+1
    movf ISR_MIX__T, w
    movwf __A0
    movf ISR_MIX__T+1, w
    movwf __A1
    movlw 0x01
    addwf __A0, f
    movlw 0x00
    addwfc __A1, f
    movf __A0, w
    movwf ISR_MIX__RESULT
    movf __A1, w
    movwf ISR_MIX__RESULT+1
    return
    ; Sub/Function Work
ISR_WORK:
    clrf ISR_WORK__I
    clrf ISR_WORK__W
    clrf ISR_WORK__W+1
    movlb 0
    clrf ISR_WORK__K
    clrf ISR_WORK__ACC
    clrf ISR_WORK__ACC+1
    clrf ISR_WORK__ACC+2
    clrf ISR_WORK__ACC+3
    clrf ISR_WORK__I
_L12:
    movf ISR_WORK__I, w
    movwf __A0
    movlw 0x07
    movwf __B0
    call __mul1
    movf __A0, w
    movlb 0
    movwf ISR_WORK__TMP
    movf ISR_WORK__I, w
    movwf __A0
    clrf __A1
    movlw 0x0C
    addwf __A0, w
    movwf FSR0L
    movlw 0x20
    addwfc __A1, w
    movwf FSR0H
    movf ISR_WORK__TMP, w
    movwi 0[FSR0]
_L13:
    movlw 0x07
    xorwf ISR_WORK__I, w
    btfsc STATUS, 2
    bra _L14
_L15:
    incf ISR_WORK__I, f
    bra _L12
_L14:
    clrf ISR_WORK__I
    movlw 0x08
    movlb 0
    movwf ISR_WORK__H1
_L16:
    movf ISR_WORK__I, w
    movwf __A0
    clrf __A1
    movlw 0x0C
    addwf __A0, w
    movwf FSR0L
    movlw 0x20
    addwfc __A1, w
    movwf FSR0H
    moviw 0[FSR0]
    movwf __A0
    clrf __A1
    movf __A0, w
    movwf ISR_WORK__W
    movf __A1, w
    movwf ISR_WORK__W+1
    movf ISR_WORK__W, w
    movwf __A0
    movf ISR_WORK__W+1, w
    movwf __A1
    movf __A0, w
    movlb 0
    movwf ISR_MIX__X
    movf __A1, w
    movwf ISR_MIX__X+1
    call ISR_MIX
    movlb 0
    movf ISR_MIX__RESULT, w
    movwf __A0
    movf ISR_MIX__RESULT+1, w
    movwf __A1
    clrf __A2
    clrf __A3
    movf __A0, w
    movwf ISR_WORK__TMP
    movf __A1, w
    movwf ISR_WORK__TMP+1
    movf __A2, w
    movwf ISR_WORK__TMP+2
    movf __A3, w
    movwf ISR_WORK__TMP+3
    movf ISR_WORK__W, w
    movwf __A0
    movf ISR_WORK__W+1, w
    movwf __A1
    clrf __A2
    clrf __A3
    movlw 0x2C
    movwf __B0
    movlw 0x01
    movwf __B1
    movlw 0x00
    movwf __B2
    movlw 0x00
    movwf __B3
    call __mul4
    movf __A0, w
    movlb 0
    movwf ISR_WORK__TMP+4
    movf __A1, w
    movwf ISR_WORK__TMP+5
    movf __A2, w
    movwf ISR_WORK__TMP+6
    movf __A3, w
    movwf ISR_WORK__TMP+7
    movf ISR_WORK__ACC, w
    movwf __A0
    movf ISR_WORK__ACC+1, w
    movwf __A1
    movf ISR_WORK__ACC+2, w
    movwf __A2
    movf ISR_WORK__ACC+3, w
    movwf __A3
    movf ISR_WORK__TMP+4, w
    addwf __A0, f
    movf ISR_WORK__TMP+5, w
    addwfc __A1, f
    movf ISR_WORK__TMP+6, w
    addwfc __A2, f
    movf ISR_WORK__TMP+7, w
    addwfc __A3, f
    movf ISR_WORK__TMP, w
    addwf __A0, f
    movf ISR_WORK__TMP+1, w
    addwfc __A1, f
    movf ISR_WORK__TMP+2, w
    addwfc __A2, f
    movf ISR_WORK__TMP+3, w
    addwfc __A3, f
    movf __A0, w
    movwf ISR_WORK__ACC
    movf __A1, w
    movwf ISR_WORK__ACC+1
    movf __A2, w
    movwf ISR_WORK__ACC+2
    movf __A3, w
    movwf ISR_WORK__ACC+3
    movf ISR_WORK__I, w
    movwf ISR_WORK__K
    movf ISR_WORK__K, w
    movwf __A0
    clrf __A1
    movlw 0x0C
    addwf __A0, w
    movwf FSR0L
    movlw 0x20
    addwfc __A1, w
    movwf FSR0H
    moviw 0[FSR0]
    movwf __A0
    clrf __A1
    clrf __A2
    clrf __A3
    movlw 0x03
    movwf __B0
    movlw 0x00
    movwf __B1
    movlw 0x00
    movwf __B2
    movlw 0x00
    movwf __B3
    call __udiv4
    movf __A0, w
    movlb 0
    movwf ISR_WORK__TMP
    movf __A1, w
    movwf ISR_WORK__TMP+1
    movf __A2, w
    movwf ISR_WORK__TMP+2
    movf __A3, w
    movwf ISR_WORK__TMP+3
    movf ISR_WORK__ACC, w
    movwf __A0
    movf ISR_WORK__ACC+1, w
    movwf __A1
    movf ISR_WORK__ACC+2, w
    movwf __A2
    movf ISR_WORK__ACC+3, w
    movwf __A3
    movf ISR_WORK__TMP, w
    addwf __A0, f
    movf ISR_WORK__TMP+1, w
    addwfc __A1, f
    movf ISR_WORK__TMP+2, w
    addwfc __A2, f
    movf ISR_WORK__TMP+3, w
    addwfc __A3, f
    movf __A0, w
    movwf ISR_WORK__ACC
    movf __A1, w
    movwf ISR_WORK__ACC+1
    movf __A2, w
    movwf ISR_WORK__ACC+2
    movf __A3, w
    movwf ISR_WORK__ACC+3
_L17:
    movlb 0
    decfsz ISR_WORK__H1, f
    bra _L19
    bra _L18
_L19:
    incf ISR_WORK__I, f
    bra _L16
_L18:
    movlb 0
    movf ISR_WORK__ACC, w
    movwf __A0
    movf ISR_WORK__ACC+1, w
    movwf __A1
    movf ISR_WORK__ACC+2, w
    movwf __A2
    movf ISR_WORK__ACC+3, w
    movwf __A3
    lsrf __A3, f
    rrf __A2, f
    rrf __A1, f
    rrf __A0, f
    lsrf __A3, f
    rrf __A2, f
    rrf __A1, f
    rrf __A0, f
    lsrf __A3, f
    rrf __A2, f
    rrf __A1, f
    rrf __A0, f
    movf __A0, w
    movwf ISR_WORK__TMP
    movf __A1, w
    movwf ISR_WORK__TMP+1
    movf __A2, w
    movwf ISR_WORK__TMP+2
    movf __A3, w
    movwf ISR_WORK__TMP+3
    movf ISR_WORK__ACC, w
    movwf __A0
    movf ISR_WORK__ACC+1, w
    movwf __A1
    movf ISR_WORK__ACC+2, w
    movwf __A2
    movf ISR_WORK__ACC+3, w
    movwf __A3
    movf ISR_WORK__TMP, w
    xorwf __A0, f
    movf ISR_WORK__TMP+1, w
    xorwf __A1, f
    movf ISR_WORK__TMP+2, w
    xorwf __A2, f
    movf ISR_WORK__TMP+3, w
    xorwf __A3, f
    movf __A0, w
    movwf ISR_WORK__ACC
    movf __A1, w
    movwf ISR_WORK__ACC+1
    movf __A2, w
    movwf ISR_WORK__ACC+2
    movf __A3, w
    movwf ISR_WORK__ACC+3
    movf ISR_WORK__ACC, w
    movwf __A0
    movf ISR_WORK__ACC+1, w
    movwf __A1
    movf ISR_WORK__ACC+2, w
    movwf __A2
    movf ISR_WORK__ACC+3, w
    movwf __A3
    movf __A0, w
    movwf ISR_WORK__RESULT
    movf __A1, w
    movwf ISR_WORK__RESULT+1
    movf __A2, w
    movwf ISR_WORK__RESULT+2
    movf __A3, w
    movwf ISR_WORK__RESULT+3
    return
    ; helper mul1
__mul1:
    clrf __C0
    movlw 8
    movwf __D0
_L20:
    lsrf __B0, f
    btfss STATUS, 0
    bra _L21
    movf __A0, w
    addwf __C0, f
_L21:
    lslf __A0, f
    decfsz __D0, f
    bra _L20
    movf __C0, w
    movwf __A0
    return
    ; helper mul2
__mul2:
    clrf __C0
    clrf __C1
    movlw 16
    movwf __D0
_L22:
    lsrf __B1, f
    rrf __B0, f
    btfss STATUS, 0
    bra _L23
    movf __A0, w
    addwf __C0, f
    movf __A1, w
    addwfc __C1, f
_L23:
    lslf __A0, f
    rlf __A1, f
    decfsz __D0, f
    bra _L22
    movf __C0, w
    movwf __A0
    movf __C1, w
    movwf __A1
    return
    ; helper mul4
__mul4:
    clrf __C0
    clrf __C1
    clrf __C2
    clrf __C3
    movlw 32
    movwf __D0
_L24:
    lsrf __B3, f
    rrf __B2, f
    rrf __B1, f
    rrf __B0, f
    btfss STATUS, 0
    bra _L25
    movf __A0, w
    addwf __C0, f
    movf __A1, w
    addwfc __C1, f
    movf __A2, w
    addwfc __C2, f
    movf __A3, w
    addwfc __C3, f
_L25:
    lslf __A0, f
    rlf __A1, f
    rlf __A2, f
    rlf __A3, f
    decfsz __D0, f
    bra _L24
    movf __C0, w
    movwf __A0
    movf __C1, w
    movwf __A1
    movf __C2, w
    movwf __A2
    movf __C3, w
    movwf __A3
    return
    ; helper udiv4
__udiv4:
    clrf __C0
    clrf __C1
    clrf __C2
    clrf __C3
    movlw 32
    movwf __D0
_L26:
    lslf __A0, f
    rlf __A1, f
    rlf __A2, f
    rlf __A3, f
    rlf __C0, f
    rlf __C1, f
    rlf __C2, f
    rlf __C3, f
    movf __B0, w
    subwf __C0, w
    movf __B1, w
    subwfb __C1, w
    movf __B2, w
    subwfb __C2, w
    movf __B3, w
    subwfb __C3, w
    btfss STATUS, 0
    bra _L27
    movf __B0, w
    subwf __C0, f
    movf __B1, w
    subwfb __C1, f
    movf __B2, w
    subwfb __C2, f
    movf __B3, w
    subwfb __C3, f
    bsf __A0, 0
_L27:
    decfsz __D0, f
    bra _L26
    return
;SYM ISR_MIX 0x0178
;SYM ISR_TICK 0x0004
;SYM ISR_WORK 0x0194
;SYM __ISR_H 0x0004
;SYM __halt 0x0177
;SYM __isr_end0 0x00EB
;SYM __mul1 0x02A2
;SYM __mul2 0x02B0
;SYM __mul4 0x02C5
;SYM __reset 0x0107
;SYM __udiv4 0x02E8
    END __reset
