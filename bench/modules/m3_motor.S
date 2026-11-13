; basil output for PIC18F27Q10
#include <xc.inc>

CONFIG CONFIG1L = 0x8C
CONFIG CONFIG1H = 0xFF
CONFIG CONFIG2L = 0xFF
CONFIG CONFIG2H = 0xFF
CONFIG CONFIG3L = 0x9F
CONFIG CONFIG3H = 0xFF
CONFIG CONFIG4L = 0xFF
CONFIG CONFIG4H = 0xFF
CONFIG CONFIG5L = 0xFF
CONFIG CONFIG6L = 0xFF
CONFIG CONFIG6H = 0xFF

; ---- data (addresses chosen by the compiler)
PINIO_DADDR equ 0x017  ; dAddr (2 bytes)
PINIO_DMASK equ 0x029  ; dMask (1 byte)
PINIO_CADDR equ 0x019  ; cAddr (2 bytes)
PINIO_CMASK equ 0x02A  ; cMask (1 byte)
ADC_LASTCH equ 0x027  ; lastCh (1 byte)
PWM_STEPS equ 0x01B  ; steps (2 bytes)
PWM_PERIOD equ 0x02B  ; period (1 byte)
PWM_CKPS equ 0x02C  ; ckps (1 byte)
PWM_NACT equ 0x028  ; nact (1 byte)
PWM_FREQ equ 0x01D  ; freq (4 bytes)
PWM_PINS equ 0x021  ; pins (4 bytes)
PWM_POLV equ 0x02D  ; polv (4 bytes)
PWM_READY equ 0x031  ; ready (1 byte)
M3_RAW equ 0x00A  ; raw (2 bytes)
M3_TARGET equ 0x008  ; target (1 byte)
M3_CUR equ 0x007  ; cur (1 byte)
M3_SAVED equ 0x00D  ; saved (1 byte)
M3_OK equ 0x010  ; ok (1 byte)
PINIO_PINOUTPUT__PIN equ 0x012  ; pin (1 byte)
PINIO_PININPUT__PIN equ 0x012  ; pin (1 byte)
ADC_ADCPIN__CH equ 0x009  ; ch (1 byte)
PWM_PWMINIT__RESULT equ 0x009  ; Result (1 byte)
PWM_PWMSTART__CH equ 0x00C  ; ch (1 byte)
PWM_PWMSTART__PIN equ 0x00F  ; pin (1 byte)
PWM_PWMSTART__RESULT equ 0x025  ; Result (1 byte)
EEPROM_EEPROMREAD__RESULT equ 0x00E  ; Result (1 byte)
TIMER_TIMER0EXPIRED__RESULT equ 0x009  ; Result (1 byte)
ADC_ADCREAD__CH equ 0x009  ; ch (1 byte)
PWM_PWMPERCENT__CH equ 0x00C  ; ch (1 byte)
PWM_PWMPERCENT__PCT equ 0x009  ; pct (1 byte)
M3_SHOW__V equ 0x014  ; v (1 byte)
PINIO_PINGET__PIN equ 0x00C  ; pin (1 byte)
PINIO_PINGET__RESULT equ 0x009  ; Result (1 byte)
EEPROM_EEPROMWRITE__VALUE equ 0x009  ; value (1 byte)
EEPROM_EEPROMWRITE__RESULT equ 0x00C  ; Result (1 byte)
EEPROM_EEPROMWRITE__IE equ 0x00F  ; ie (1 byte)
PINIO_PINSET__PIN equ 0x009  ; pin (1 byte)
PINIO_PINSET__LEVEL equ 0x00C  ; level (1 byte)
SHIFT_SHIFTOUT__DATA equ 0x009  ; data (1 byte)
SHIFT_SHIFTOUT__I equ 0x00C  ; i (1 byte)
SHIFT_SETUP__RESULT equ 0x013  ; Result (1 byte)
PINIO_DATAPUT__LEVEL equ 0x00E  ; level (1 byte)
PINIO_CLKPUT__LEVEL equ 0x00E  ; level (1 byte)
PINIO_BINDDATA__PIN equ 0x012  ; pin (1 byte)
PINIO_BINDCLK__PIN equ 0x012  ; pin (1 byte)
PINIO_PINADDR__PIN equ 0x011  ; pin (1 byte)
PINIO_PINADDR__RESULT equ 0x00E  ; Result (2 bytes)
PWM_PWMPERCENT__D equ 0x00E  ; d (2 bytes)
PWM_PWMDUTY__CH equ 0x013  ; ch (1 byte)
PWM_PWMDUTY__DUTY equ 0x025  ; duty (2 bytes)
PWM_SETDUTY__CH equ 0x014  ; ch (1 byte)
PWM_SETDUTY__D equ 0x011  ; d (2 bytes)
PWM_SETDUTY__HI equ 0x015  ; hi (1 byte)
PWM_SETDUTY__LO equ 0x016  ; lo (1 byte)
ADC_CONVERT__RESULT equ 0x00E  ; Result (2 bytes)
PWM_PWMSTART__OLD equ 0x013  ; old (1 byte)
PWM_PWMSTART__C equ 0x009  ; c (1 byte)
PWM_PINOK__CH equ 0x011  ; ch (1 byte)
PWM_PINOK__PIN equ 0x012  ; pin (1 byte)
PWM_PINOK__RESULT equ 0x014  ; Result (1 byte)
PWM_SETPPS__PIN equ 0x014  ; pin (1 byte)
PWM_SETPPS__CODE equ 0x015  ; code (1 byte)
PWM_SETCON__CH equ 0x012  ; ch (1 byte)
PWM_SETCON__V equ 0x011  ; v (1 byte)
PWM_SETPPS__SL equ 0x011  ; sl (1 byte)
PWM_SETPPS__SH equ 0x012  ; sh (1 byte)
PINIO_PININPUT__M equ 0x011  ; m (1 byte)
PINIO_PINOUTPUT__M equ 0x015  ; m (1 byte)
PINIO_PINOUTPUT__N equ 0x011  ; n (1 byte)
PINIO_PINOK__PIN_S33 equ 0x00F  ; pin (1 byte)
PINIO_PINOK__RESULT_S33 equ 0x00E  ; Result (1 byte)
PINIO_PINOK__PIN_S34 equ 0x00F  ; pin (1 byte)
PINIO_PINOK__RESULT_S34 equ 0x00E  ; Result (1 byte)
__A0 equ 0x000
__A1 equ 0x001
__B0 equ 0x002
__C0 equ 0x003
__C1 equ 0x004
__D0 equ 0x005
__D1 equ 0x006
PWM_PWMSTART__TMP equ 0x00E
PWM_SETDUTY__TMP equ 0x032

PSECT code,class=CODE,abs,delta=1
    ORG 0x0000
__reset:
    clrf 0x007, c
    clrf 0x008, c
    clrf 0x00A, c
    clrf 0x00B, c
    clrf 0x00D, c
    lfsr 0, 0x010
    movlw 34
_L1:
    clrf POSTINC0, c
    decfsz WREG, f, c
    bra _L1
    movlb 15
    clrf ANSELA, b
    clrf ANSELB, b
    clrf ANSELC, b
    clrf WPUA, b
    movlw 0x08
    movwf WPUB, b
    clrf WPUC, b
    movlw 0x0A
    rcall PINIO_PINOUTPUT
    movlw 0x0B
    rcall PINIO_PININPUT
    movlb 15
    clrf ADCON0, b
    clrf ADCON1, b
    clrf ADCON2, b
    clrf ADCON3, b
    clrf ADCAP, b
    clrf ADPRE, b
    clrf ADACT, b
    clrf ADREF, b
    movlw 0x1F
    movwf ADCLK, b
    movlw 0x05
    movwf ADACQ, b
    setf ADC_LASTCH, c
    movlw 0x84
    movwf ADCON0, b
    movlw 0x01
    iorwf TRISA, f, c
    iorwf ANSELA, f, b
    clrf PWM_PWMINIT__RESULT, c
    movf PWM_NACT, f, c
    bnz _Lr4
    movlw 0x02
    movwf PWM_CKPS, c
    movlw 0xC7
    movwf PWM_PERIOD, c
    movlw 0x20
    movwf PWM_STEPS, c
    movlw 0x03
    movwf PWM_STEPS+1, c
    movlw 0x20
    movwf PWM_FREQ, c
    movlw 0x4E
    movwf PWM_FREQ+1, c
    clrf PWM_FREQ+2, c
    clrf PWM_FREQ+3, c
    movlw 0x01
    movwf PWM_READY, c
    movwf PWM_PWMINIT__RESULT, c
_Lr4:
    movlw 0x01
    movwf PWM_PWMSTART__CH, c
    movlw 0x12
    movwf PWM_PWMSTART__PIN, c
    rcall PWM_PWMSTART
    movlw 0x02
    movwf PWM_PWMSTART__CH, c
    movlw 0x11
    movwf PWM_PWMSTART__PIN, c
    rcall PWM_PWMSTART
    movf PWM_PWMSTART__RESULT, w, c
    rcall EEPROM_EEPROMREAD
    movwf M3_SAVED, c
    clrf M3_CUR, c
    movlw 0x65
    subwf M3_SAVED, w, c
    bc _L3
    movff M3_SAVED, M3_CUR
_L3:
    clrf T0CON0, c
    movlw 0x49
    movwf T0CON1, c
    movlw 0x7C
    movwf TMR0H, c
    clrf TMR0L, c
    movlb 14
    bcf PIR0, 5, b
    movlw 0x80
    movwf T0CON0, c
_L4:
    clrf TIMER_TIMER0EXPIRED__RESULT, c
    movlb 14
    btfss PIR0, 5, b
    bra _L55
    bcf PIR0, 5, b
    movlw 0x01
    movwf TIMER_TIMER0EXPIRED__RESULT, c
_L55:
    movf TIMER_TIMER0EXPIRED__RESULT, w, c
    bz _L4
    movlw 0x00
    movwf ADC_ADCREAD__CH, c
    movlw 0x3F
    andwf ADC_ADCREAD__CH, f, c
    movf ADC_ADCREAD__CH, w, c
    xorwf ADC_LASTCH, w, c
    bz _L57
    movf ADC_ADCREAD__CH, w, c
    movlb 15
    movwf ADPCH, b
    rcall ADC_CONVERT
    movff ADC_ADCREAD__CH, ADC_LASTCH
_L57:
    rcall ADC_CONVERT
    movff ADC_CONVERT__RESULT, __A0
    movff ADC_CONVERT__RESULT+1, __A0+1
    movlw 10
    movwf __B0, c
    rcall __divk2
    movf __A0, w, c
    movwf M3_TARGET, c
    movlw 0x65
    subwf M3_TARGET, w, c
    bnc _L10
    movlw 0x64
    movwf M3_TARGET, c
_L10:
    movf M3_TARGET, w, c
    subwf M3_CUR, w, c
    bc _L12
    incf M3_CUR, f, c
    bra _L11
_L12:
    movf M3_CUR, w, c
    subwf M3_TARGET, w, c
    bc _L13
    decf M3_CUR, f, c
_L13:
_L11:
    movlw 0x01
    movwf PWM_PWMPERCENT__CH, c
    movff M3_CUR, PWM_PWMPERCENT__PCT
    rcall PWM_PWMPERCENT
    movlw 0x02
    movwf PWM_PWMPERCENT__CH, c
    movf M3_CUR, w, c
    sublw 0x64
    movwf PWM_PWMPERCENT__PCT, c
    rcall PWM_PWMPERCENT
    movf M3_CUR, w, c
    movwf M3_SHOW__V, c
    movlw 0x0A
    movwf PINIO_PINSET__PIN, c
    clrf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    movff M3_SHOW__V, SHIFT_SHIFTOUT__DATA
    clrf SHIFT_SETUP__RESULT, c
    movlw 0x01
    movwf PINIO_PINOK__RESULT_S33, c
    movf PINIO_PINOK__RESULT_S33, w, c
    bz _Lr11
    movlw 0x01
    movwf PINIO_PINOK__RESULT_S34, c
    movf PINIO_PINOK__RESULT_S34, w, c
    bz _Lr11
    movlw 0x08
    rcall PINIO_PINADDR
    movff PINIO_PINADDR__RESULT, PINIO_DADDR
    movff PINIO_PINADDR__RESULT+1, PINIO_DADDR+1
    movlw 0x01
    movwf PINIO_DMASK, c
    movlw 0x09
    rcall PINIO_PINADDR
    movff PINIO_PINADDR__RESULT, PINIO_CADDR
    movff PINIO_PINADDR__RESULT+1, PINIO_CADDR+1
    movlw 0x02
    movwf PINIO_CMASK, c
    movlw 0x00
    rcall PINIO_CLKPUT
    movlw 0x09
    rcall PINIO_PINOUTPUT
    movlw 0x01
    movwf SHIFT_SETUP__RESULT, c
_Lr11:
    movf SHIFT_SETUP__RESULT, w, c
    bz _Lr10
    movlw 0x08
    rcall PINIO_PINOUTPUT
    movlw 0x01
    movwf SHIFT_SHIFTOUT__I, c
_L73:
    movlw 0
    btfsc SHIFT_SHIFTOUT__DATA, 7, c
    movlw 1
    rcall PINIO_DATAPUT
    movf SHIFT_SHIFTOUT__DATA, w, c
    addwf WREG, w, c
    movwf SHIFT_SHIFTOUT__DATA, c
    movlw 5
    movwf __D0, c
_L83:
    decfsz __D0, f, c
    bra _L83
    movlw 0x01
    rcall PINIO_CLKPUT
    movlw 5
    movwf __D0, c
_L84:
    decfsz __D0, f, c
    bra _L84
    movlw 0x00
    rcall PINIO_CLKPUT
    movf SHIFT_SHIFTOUT__I, w, c
    incf SHIFT_SHIFTOUT__I, f, c
    xorlw 0x08
    bnz _L73
_Lr10:
    movlw 0x0A
    movwf PINIO_PINSET__PIN, c
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    movlw 0x0B
    rcall PINIO_PINGET
    movf PINIO_PINGET__RESULT, w, c
    bz __skip1
    bra _L4
__skip1:
    movf M3_CUR, w, c
    xorwf M3_SAVED, w, c
    bnz __skip2
    bra _L4
__skip2:
    movff M3_CUR, EEPROM_EEPROMWRITE__VALUE
    movlw 0x01
    movwf EEPROM_EEPROMWRITE__RESULT, c
    rcall EEPROM_EEPROMREAD
    xorwf EEPROM_EEPROMWRITE__VALUE, w, c
    bz _L62
    movf EEPROM_EEPROMWRITE__VALUE, w, c
    movwf NVMDATL, c
    movlw 0
    btfsc INTCON, 7, c
    movlw 1
    movwf EEPROM_EEPROMWRITE__IE, c
    bcf INTCON, 7, c
    bsf NVMCON0, 7, c
    movlw 0x55
    movwf NVMCON2, c
    movlw 0xAA
    movwf NVMCON2, c
    bsf NVMCON1, 4, c
    decf EEPROM_EEPROMWRITE__IE, w, c
    bnz _L66
    bsf INTCON, 7, c
_L65:
_L66:
    btfsc NVMCON1, 4, c
    bra _L65
    bcf NVMCON0, 7, c
    movlb 14
    bcf PIR7, 5, b
    rcall EEPROM_EEPROMREAD
    xorwf EEPROM_EEPROMWRITE__VALUE, w, c
    bz _L69
    clrf EEPROM_EEPROMWRITE__RESULT, c
_L69:
_L62:
    bcf NVMCON0, 4, c
    movff M3_CUR, M3_SAVED
    bra _L4
__halt:
    ; Sub/Function PinOutput
PINIO_PINOUTPUT:
    movwf PINIO_PINOUTPUT__PIN, c
    andlw 0x07
    movwf __D1, c
    movlw 0x01
    movwf __A0, c
    rcall __shl1
    movf __A0, w, c
    xorlw 0xFF
    movwf PINIO_PINOUTPUT__N, c
    movlw 0x08
    subwf PINIO_PINOUTPUT__PIN, w, c
    bc _L19
    movf PINIO_PINOUTPUT__N, w, c
    movlb 15
    andwf ANSELA, f, b
    andwf TRISA, f, c
    return
_L19:
    movlw 0x10
    subwf PINIO_PINOUTPUT__PIN, w, c
    bc _L20
    movf PINIO_PINOUTPUT__N, w, c
    movlb 15
    andwf ANSELB, f, b
    andwf TRISB, f, c
    return
_L20:
    movlw 0x18
    subwf PINIO_PINOUTPUT__PIN, w, c
    bc _L21
    movf PINIO_PINOUTPUT__N, w, c
    movlb 15
    andwf ANSELC, f, b
    andwf TRISC, f, c
_L21:
    return
    ; Sub/Function PinInput
PINIO_PININPUT:
    movwf PINIO_PININPUT__PIN, c
    andlw 0x07
    movwf __D1, c
    movlw 0x01
    movwf __A0, c
    rcall __shl1
    movf __A0, w, c
    movwf PINIO_PININPUT__M, c
    movlw 0x08
    subwf PINIO_PININPUT__PIN, w, c
    bc _L23
    movf PINIO_PININPUT__M, w, c
    xorlw 0xFF
    movlb 15
    andwf ANSELA, f, b
    movf PINIO_PININPUT__M, w, c
    iorwf TRISA, f, c
    return
_L23:
    movlw 0x10
    subwf PINIO_PININPUT__PIN, w, c
    bc _L24
    movf PINIO_PININPUT__M, w, c
    xorlw 0xFF
    movlb 15
    andwf ANSELB, f, b
    movf PINIO_PININPUT__M, w, c
    iorwf TRISB, f, c
    return
_L24:
    movlw 0x18
    subwf PINIO_PININPUT__PIN, w, c
    bc _L25
    movf PINIO_PININPUT__M, w, c
    xorlw 0xFF
    movlb 15
    andwf ANSELC, f, b
    movf PINIO_PININPUT__M, w, c
    iorwf TRISC, f, c
_L25:
    return
    ; Sub/Function PwmStart
PWM_PWMSTART:
    clrf PWM_PWMSTART__RESULT, c
    movf PWM_READY, f, c
    bz _L31
    clrf PWM_PINOK__RESULT, c
    decf PWM_PWMSTART__CH, w, c
    bz _L100
    movf PWM_PWMSTART__CH, w, c
    xorlw 0x02
    bnz _L99
_L100:
    movf PWM_PWMSTART__PIN, w, c
    addlw 0xF8
    sublw 0x0F
    bnc _L98
    movlw 0x01
    movwf PWM_PINOK__RESULT, c
    bra _L98
_L99:
    xorlw 0x01
    bz _L104
    movf PWM_PWMSTART__CH, w, c
    xorlw 0x04
    bnz _L103
_L104:
    movlw 0x08
    subwf PWM_PWMSTART__PIN, w, c
    bnc _L107
    movf PWM_PWMSTART__PIN, w, c
    addlw 0xF0
    sublw 0x07
    bnc _L106
_L107:
    movlw 0x01
    movwf PWM_PINOK__RESULT, c
_L106:
_L103:
_L98:
    movf PWM_PINOK__RESULT, w, c
    bnz _L30
_L31:
    return
_L30:
    movlw 0x04
    movwf PWM_PWMSTART__C, c
    bra _L33
_L32:
    movf PWM_PWMSTART__C, w, c
    xorwf PWM_PWMSTART__CH, w, c
    bz _L36
    decf PWM_PWMSTART__C, w, c
    lfsr 0, PWM_PINS
    movf PLUSW0, w, c
    movwf PWM_PWMSTART__TMP, c
    incf PWM_PWMSTART__PIN, w, c
    xorwf PWM_PWMSTART__TMP, w, c
    bnz _L36
    return
_L36:
    decf PWM_PWMSTART__C, f, c
_L33:
    movf PWM_PWMSTART__C, f, c
    bnz _L32
    decf PWM_PWMSTART__CH, w, c
    lfsr 0, PWM_PINS
    movf PLUSW0, w, c
    movwf PWM_PWMSTART__OLD, c
    bz _L38
    incf PWM_PWMSTART__PIN, w, c
    xorwf PWM_PWMSTART__OLD, w, c
    bz _L38
    decf PWM_PWMSTART__OLD, w, c
    rcall PINIO_PININPUT
    decf PWM_PWMSTART__OLD, w, c
    movwf PWM_SETPPS__PIN, c
    clrf PWM_SETPPS__CODE, c
    rcall PWM_SETPPS
_L38:
    movf PWM_PWMSTART__PIN, w, c
    rcall PINIO_PININPUT
    movff PWM_PWMSTART__PIN, PWM_SETPPS__PIN
    movf PWM_PWMSTART__CH, w, c
    addlw 0x04
    movwf PWM_SETPPS__CODE, c
    rcall PWM_SETPPS
    movlw 0x03
    subwf PWM_PWMSTART__CH, w, c
    bc _L40
    movff PWM_PWMSTART__CH, PWM_SETCON__CH
    movlw 0x9C
    movwf PWM_SETCON__V, c
    rcall PWM_SETCON
    bra _L39
_L40:
    movff PWM_PWMSTART__CH, PWM_SETCON__CH
    decf PWM_PWMSTART__CH, w, c
    lfsr 0, PWM_POLV
    movf PLUSW0, w, c
    movwf PWM_SETCON__V, c
    rcall PWM_SETCON
_L39:
    movff PWM_PWMSTART__CH, PWM_SETDUTY__CH
    clrf PWM_SETDUTY__D, c
    clrf PWM_SETDUTY__D+1, c
    rcall PWM_SETDUTY
    movf PWM_NACT, f, c
    bnz _L42
    clrf T2CON, c
    movlw 0x01
    movwf T2CLKCON, c
    clrf T2HLT, c
    clrf T2RST, c
    movf PWM_PERIOD, w, c
    movwf T2PR, c
    clrf T2TMR, c
    movlb 14
    bcf PIR4, 1, b
    movf PWM_CKPS, w, c
    mullw 0x10
    movf PRODL, w, c
    addlw 0x80
    movwf T2CON, c
    bra _L44
_L42:
    movlb 14
    bcf PIR4, 1, b
_L43:
_L44:
    btfss PIR4, 1, b
    bra _L43
    bcf PIR4, 1, b
    incf PWM_PWMSTART__PIN, w, c
    movwf PWM_PWMSTART__TMP, c
    decf PWM_PWMSTART__CH, w, c
    lfsr 0, PWM_PINS
    movff PWM_PWMSTART__TMP, PLUSW0
    movf PWM_PWMSTART__OLD, f, c
    bnz _L47
    incf PWM_NACT, f, c
_L47:
    movf PWM_PWMSTART__PIN, w, c
    rcall PINIO_PINOUTPUT
    movlw 0x03
    subwf PWM_PWMSTART__CH, w, c
    bnc _L49
    movff PWM_PWMSTART__CH, PWM_SETCON__CH
    decf PWM_PWMSTART__CH, w, c
    lfsr 0, PWM_POLV
    movf PLUSW0, w, c
    addlw 0x80
    movwf PWM_SETCON__V, c
    rcall PWM_SETCON
_L49:
    movlw 0x01
    movwf PWM_PWMSTART__RESULT, c
    return
    ; Sub/Function EepromRead
EEPROM_EEPROMREAD:
    setf EEPROM_EEPROMREAD__RESULT, c
    movlw 0x31
    movwf NVMADRU, c
    clrf NVMADRH, c
    clrf NVMADRL, c
    bsf NVMCON1, 0, c
_L51:
    btfsc NVMCON1, 0, c
    bra _L51
    movff NVMDATL, EEPROM_EEPROMREAD__RESULT
    movf EEPROM_EEPROMREAD__RESULT, w, c
    return
    ; Sub/Function PwmPercent
PWM_PWMPERCENT:
    movlw 0x65
    subwf PWM_PWMPERCENT__PCT, w, c
    bnc _L59
    movlw 0x64
    movwf PWM_PWMPERCENT__PCT, c
_L59:
    movff PWM_STEPS, __A0
    movff PWM_STEPS+1, __A0+1
    bcf STATUS, 0, c
    rrcf __A1, f, c
    rrcf __A0, f, c
    bcf STATUS, 0, c
    rrcf __A1, f, c
    rrcf __A0, f, c
    movf PWM_PWMPERCENT__PCT, w, c
    mulwf __A0+1, c
    movff PRODL, __A1
    mulwf __A0, c
    movff PRODL, __A0
    movf PRODH, w, c
    addwf __A1, f, c
    movlw 25
    movwf __B0, c
    rcall __divk2
    movff __A0, PWM_PWMPERCENT__D
    movff __A1, PWM_PWMPERCENT__D+1
    decf PWM_PWMPERCENT__CH, w, c
    sublw 0x03
    bnc _L86
    decf PWM_PWMPERCENT__CH, w, c
    lfsr 0, PWM_PINS
    movf PLUSW0, w, c
    bz _L88
    movff PWM_PWMPERCENT__CH, PWM_SETDUTY__CH
    movff PWM_PWMPERCENT__D, PWM_SETDUTY__D
    movff PWM_PWMPERCENT__D+1, PWM_SETDUTY__D+1
    rcall PWM_SETDUTY
_L88:
_L86:
    return
    ; Sub/Function PinGet
PINIO_PINGET:
    movwf PINIO_PINGET__PIN, c
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
    return
    ; Sub/Function PinSet
PINIO_PINSET:
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
    return
    ; Sub/Function DataPut
PINIO_DATAPUT:
    movwf PINIO_DATAPUT__LEVEL, c
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
    return
    ; Sub/Function ClkPut
PINIO_CLKPUT:
    movwf PINIO_CLKPUT__LEVEL, c
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
    return
    ; Sub/Function PinAddr
PINIO_PINADDR:
    movwf PINIO_PINADDR__PIN, c
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
    return
    ; Sub/Function SetDuty
PWM_SETDUTY:
    movlw 4
    subwf PWM_SETDUTY__D+1, w, c
    bnc _L90
    setf PWM_SETDUTY__D, c
    movlw 0x03
    movwf PWM_SETDUTY__D+1, c
_L90:
    movf PWM_SETDUTY__D+1, w, c
    mullw 64
    movf PRODL, w, c
    movwf PWM_SETDUTY__TMP, c
    movf PWM_SETDUTY__D, w, c
    rrncf WREG, w, c
    rrncf WREG, w, c
    andlw 0x3F
    iorwf PWM_SETDUTY__TMP, w, c
    movwf PWM_SETDUTY__HI, c
    movf PWM_SETDUTY__D, w, c
    mullw 64
    movf PRODL, w, c
    movwf PWM_SETDUTY__LO, c
    decf PWM_SETDUTY__CH, w, c
    bnz _L92
    movf PWM_SETDUTY__LO, w, c
    movwf CCPR1L, c
    movf PWM_SETDUTY__HI, w, c
    movwf CCPR1H, c
    return
_L92:
    movf PWM_SETDUTY__CH, w, c
    xorlw 0x02
    bnz _L93
    movf PWM_SETDUTY__LO, w, c
    movwf CCPR2L, c
    movf PWM_SETDUTY__HI, w, c
    movwf CCPR2H, c
    return
_L93:
    xorlw 0x01
    bnz _L94
    movf PWM_SETDUTY__LO, w, c
    movwf PWM3DCL, c
    movf PWM_SETDUTY__HI, w, c
    movwf PWM3DCH, c
    return
_L94:
    movf PWM_SETDUTY__LO, w, c
    movwf PWM4DCL, c
    movf PWM_SETDUTY__HI, w, c
    movwf PWM4DCH, c
    return
    ; Sub/Function Convert
ADC_CONVERT:
    movlb 15
    bsf ADCON0, 0, b
_L95:
    btfsc ADCON0, 0, b
    bra _L95
    movff ADRESL, ADC_CONVERT__RESULT
    movff ADRESH, ADC_CONVERT__RESULT+1
    return
    ; Sub/Function SetPps
PWM_SETPPS:
    clrf PWM_SETPPS__SL, c
    clrf PWM_SETPPS__SH, c
            movff FSR2L, PWM_SETPPS__SL
            movff FSR2H, PWM_SETPPS__SH
            lfsr 2, RA0PPS
            movf PWM_SETPPS__PIN, w, c
            addwf FSR2L, f, c
            movf PWM_SETPPS__CODE, w, c
            movwf INDF2, c
            movff PWM_SETPPS__SL, FSR2L
            movff PWM_SETPPS__SH, FSR2H
    return
    ; Sub/Function SetCon
PWM_SETCON:
    decf PWM_SETCON__CH, w, c
    bnz _L109
    movf PWM_SETCON__V, w, c
    movwf CCP1CON, c
    return
_L109:
    movf PWM_SETCON__CH, w, c
    xorlw 0x02
    bnz _L110
    movf PWM_SETCON__V, w, c
    movwf CCP2CON, c
    return
_L110:
    xorlw 0x01
    bnz _L111
    movf PWM_SETCON__V, w, c
    movwf PWM3CON, c
    return
_L111:
    movf PWM_SETCON__V, w, c
    movwf PWM4CON, c
    return
    ; helper divk2
__divk2:
    clrf __C0, c
    clrf __C1, c
    movlw 16
    movwf __D0, c
_L112:
    bcf STATUS, 0, c
    rlcf __A0, f, c
    rlcf __A1, f, c
    rlcf __C0, f, c
    bc _L113
    movf __B0, w, c
    subwf __C0, w, c
    bnc _L114
_L113:
    movf __B0, w, c
    subwf __C0, f, c
    bsf __A0, 0, c
_L114:
    decfsz __D0, f, c
    bra _L112
    return
    ; helper shl1
__shl1:
    movf __D1, f, c
    bz _L116
_L115:
    bcf STATUS, 0, c
    rlcf __A0, f, c
    decfsz __D1, f, c
    bra _L115
_L116:
    return
;SYM ADC_CONVERT 0x054A
;SYM EEPROM_EEPROMREAD 0x03C6
;SYM PINIO_CLKPUT 0x04B4
;SYM PINIO_CLKPUT_END 0x04CC
;SYM PINIO_CLKPUT_HI 0x04CA
;SYM PINIO_DATAPUT 0x049A
;SYM PINIO_DATAPUT_END 0x04B2
;SYM PINIO_DATAPUT_HI 0x04B0
;SYM PINIO_PINADDR 0x04CE
;SYM PINIO_PINADDR_END 0x04EA
;SYM PINIO_PINGET 0x043C
;SYM PINIO_PINGET_END 0x0468
;SYM PINIO_PINGET_GOT 0x0462
;SYM PINIO_PINGET_SHL 0x045A
;SYM PINIO_PININPUT 0x0256
;SYM PINIO_PINOUTPUT 0x0214
;SYM PINIO_PINSET 0x046A
;SYM PINIO_PINSET_END 0x0498
;SYM PINIO_PINSET_GOT 0x048C
;SYM PINIO_PINSET_HI 0x0496
;SYM PINIO_PINSET_SHL 0x0484
;SYM PWM_PWMPERCENT 0x03DE
;SYM PWM_PWMSTART 0x02A2
;SYM PWM_SETCON 0x057E
;SYM PWM_SETDUTY 0x04EC
;SYM PWM_SETPPS 0x055C
;SYM __divk2 0x05A4
;SYM __halt 0x0214
;SYM __reset 0x0000
;SYM __shl1 0x05C8
    END __reset
