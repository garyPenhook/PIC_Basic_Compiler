Module Adc
' ADC with computation (ADCC), basic mode, right-justified results (PIC18F27/47Q10: DS40002043F,
' chapter 33, 10 bits; PIC16F17126/46: DS40002343F, chapter 33, 12 bits; PIC18F0x/1xQ41: DS40002214G,
' chapter 40, 12 bits). ADCON0, ADCLK, ADREF, ADPCH, ADACQ and FVRCON are used with the same bit layout on
' all of them. What differs is chosen with `#if _has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)` (the Q10; the Q41 pack
' lists ADPREF as a legacy name of ADREF.PREF, so `_has(ADREF.ADPREF)` alone is true there too) and
' `#if _has(ADCPCON)` (true for the Q41, which has the ADC charge pump register): the resolution
' (`AdcMax`), the channel numbers of the internal sources, the pins that exist, and the errata
' workarounds. The PIC16F171xx has no errata for the channel change or the FVR reference (DS80001009E; its erratum
' 1.6.1, the charge pump off after a Reset, is worked around in AdcInit), and
' the Q41 none either (DS80000901H lists only the double-sample erratum 1.1.2, which this module does not
' use), so they carry neither workaround. Its erratum 1.1.2 (ADACQ/ADPRE only delay the next conversion and do not lengthen the sample
' time of the current one) applies to the 5 us acquisition below: for a high-impedance source slow the
' conversion clock or the oscillator, or use the ADCRC clock, as the erratum says.
' Conversions are started by software and the clock is derived from FOSC, so `Clock` must be FOSC
' in MHz. The module is not reentrant: do not call it from a handler and from the main program.
'
' Conversion clock [33.1.4, ADCLK, Table 39-14 AD20]: TAD = 2 * (n + 1) / FOSC and must lie in
' 1..9 us (Q41: 0.5..9 us, AD20 [DS40002214G 48.4.8], so the same choice is inside its range). AdcInit picks the smallest TAD >= 1 us. Acquisition is done by the hardware: ADACQ
' counts ADC clocks on the Q10 [33.7.10] and FOSC clocks on the other ADCC parts [DS40002214G 40.7.10] and is set to cover AcqUs, the 10 kohm worked example of Equation
' 33-1 (4.62 us). A higher source impedance needs a longer time: write ADACQ after AdcInit.
'
' PIC16F13145 family (DS40002519D, chapter 32, 10 bits; chosen with `#if _has(CLBCON)`): the same registers; channels RA0..RA2, RA4, RA5 = 0..2, 4, 5,
' RB4..RB7 = 12..15, RC0..RC7 = 16..23 (RB and RC6, RC7 on the 20-pin parts, RC on the 14- and 20-pin ones), VSS 58, temperature indicator 59,
' DAC1 60, FVR buffer 1 62 and buffer 2 63 [Table 32-6 p.465]. Silicon erratum 1.1.1 (DS80001115F, revision A2): the real minimum TAD
' is 2 us, not the 1 us of AD20, so the conversion clock is chosen for TAD >= 2 us on this family (the limit is 9 us, AD20 p.557).
' CPON resets to 01 there (CPCON p.514), so no charge pump write is needed.
'
' PIC16F13214/15/24/25/44/45 (DS40002686B, chapter 32, 10 bits; also chosen with `#if _has(CLBCON)`, told from the PIC16F13145 family by `_has(HLVDCON0)`): the same registers and the same
' channel numbers [ADPCH, Table 32-6 p.508: RA0..RA2 = 0..2, ADCG1 3, RA4 and RA5 = 4 and 5, RB4..RB7 = 12..15, RC0..RC7 = 16..23, VSS 58, temperature indicator 59, DAC1 60, FVR buffer 1 62 and
' buffer 2 63; RB and RC6, RC7 on the 20-pin parts, RC0..RC5 on the 14-pin ones, port A only on the 8-pin]. ADCLK = FOSC / (2 (n + 1)), ADREF.PREF, ADACQ in FOSC clocks [p.506-510]. TAD is 0.5..9 us
' with FOSC as the clock (AD20, p.610) and the errata (DS80001213B) list nothing for the ADC, so the 2 us of the PIC16F13145 family's erratum does not apply: MinTadNs = 500. CPON resets to 01 [CPCON p.565].
' PIC16F183xx (DS40001799F, DS40001800E, DS40001795K, DS40001839E, chapter 22, 10 bits; chosen with `#if _has(ADCON0.CHS)`): the older
' ADC without ADCC. ADCON0 holds CHS<5:0> (bits 7-2), GO/DONE (bit 1) and ADON; ADCON1 holds ADFM, ADCS<2:0>, ADNREF and ADPREF<1:0> [Registers 22-1, 22-2].
' Channels: RA0..RA2, RA4, RA5 = 0..2, 4, 5, RB4..RB7 = 12..15, RC0..RC7 = 16..23, VSS 60, temperature indicator 61, DAC1 62 and FVR 63 [Register 22-1].
' The conversion clock is FOSC/n with n = 2, 4, 8, 16, 32, 64 (ADCS = 000, 100, 001, 101, 010, 110) [Table 22-1] and TAD must be 1..9 us (AD20, the same in all four data sheets), so SetClock (constants worked out by the compiler from `Clock`) uses the
' smallest n with n / FOSC >= 1 us. There is no ADACQ: the acquisition time is a software delay of 5 us (the 4.62 us worked example of Equation 22-1) after
' the channel is selected or changed [22.3]. The positive reference is VDD (ADPREF = 00) or the FVR (11) at the gain of ADFVR [Register 22-2, 16-1]. FVRRDY always reads 1 there.
' The silicon errata of the latest revisions (DS80000666H, DS80000667E, DS80000668L, DS80000709H) list nothing for the ADC conversion or reference except the
' auto-conversion trigger in Sleep (not used here), so no workaround is applied.
'
' PIC16F152xx (DS40002195E, chapter 27, 10 bits; chosen with `#if _has(ADCON1.PREF)` inside the branches above): the same register layout as the PIC16F183xx (ADCON0 = CHS<5:0> | GO | ON,
' ADCON1 = FM | CS<2:0> | PREF<1:0> with the same CS codes, no ADNREF, no ADACQ) [Registers 27-1, 27-2 p.328-329]. Channels: RA0..RA2, RA4, RA5 = 0..2, 4, 5, RB5..RB7 = 13..15, RC2..RC5 = 18..21 (no channel for RB4, RC0, RC1,
' RC6, RC7), VSS 27 and FVR buffer 1 30; there is no temperature indicator and no DAC channel. The positive reference is VDD (PREF = 00) or the FVR (11) [27.4.2]. TAD must be 0.5..9 us (AD20, Table 32-12 p.378), so SetClock (constants worked out by the compiler from `Clock`) uses
' the smallest FOSC/n with n / FOSC >= 0.5 us. CPON resets to 00 (charge pump off) [CPCON p.335], so AdcInit writes 01: the pump runs when the ADC is on and VDD < 4.6 V. The silicon errata (DS80000918K) list nothing for the ADC.
'
' PIC16F153xx (DS40001897C, DS40001889E, DS40001865F, DS40001853E and DS40001866E, chapter 20, 10 bits; chosen with `#if _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)` inside the branches above, after the PIC16F152xx test): the registers of the
' PIC16F183xx with ADCON1 = ADFM | ADCS<2:0> | ADPREF<1:0> and no ADNREF [Registers 20-1, 20-2 p.280-282 of DS40001866E], no ADACQ and no charge pump; the channel numbers are the part's own (see AdcChVss). The positive
' reference is VDD (ADPREF = 00), the VREF+ pin (10) or the FVR (11). TAD must be 1..9 us (AD20, Table 37-13 p.492 of DS40001889E). Silicon erratum 1.1 (DS80000721D, DS80000717K, DS80000725F, current revisions; the
' PIC16(L)F15313/23 and 15324/44 errata documents list no ADC issue, but the ADC is the same): the FVR as positive reference increases the missing codes, workaround 1 raises TAD to 8 us. AdcRefFvr therefore selects the slowest
' FOSC/n (n up to 64) while the FVR is the reference, which meets 8 us only at FOSC <= 8 MHz; at a higher FOSC use AdcRefVdd (workaround 2) when the missing codes matter. The other errata items are specifications only.
'
' PIC16F18056/76 (DS40002325C, chapter 31, 10 bits [AD01 p.529]; chosen with `Not _has(OSCCON1)` inside the ADCC branch): the same registers as the PIC16F17126 with a 10-bit result. Channels [Table 31-6 p.428]: RA0..RA7 = 0..7, RB0..RB7 = 8..15,
' RC0..RC7 = 16..23, RD0..RD7 = 24..31 and RE0..RE2 = 32..34 (the 40-pin PIC16F18076 only; the 28-pin PIC16F18056 has port A, B and C and RE3 as an input), ADCG1 35, VSS 58, temperature indicator 59, FVR buffer 1 62 and
' buffer 2 63; there is no DAC channel (60 and 61 are reserved). TAD is 1..8 us (AD20 p.529). Erratum 1.1.1 (DS80001014D, all silicon): CPON resets to 00 (off), so AdcInit writes 01 as on the PIC16F171xx.
'
' Errata (DS80000832G):
'  1.4.4  after the input channel changes, the first conversion can have its top bit wrongly set
'         (a fall of more than 3.2 V faster than 11 V/us). AdcRead converts once and drops the
'         result whenever the channel differs from the one it used last.
'  1.4.1  the FVR as positive reference gives missing codes unless TAD >= 8 us. AdcRefFvr slows the
'         conversion clock to the first TAD >= 8 us; ADCS is only 6 bits wide, so with FOSC above
'         16 MHz the slowest clock is below 8 us and the workaround cannot be met (see AdcRefFvr).
'  1.4.2  Burst Average mode is not used here.
' The pin that is read must be an analog input: call AdcPin first (ANSELx resets to 1 but the
' pin may have been changed by `Gpio.GpioAllDigital`).
' ADC channel numbers, the ADPCH values of Table 33-1. Pins: RA0..RA7 = 0..7, RB0..RB7 = 8..15,
' RC0..RC7 = 16..23.
#if _has(ADCON1.PREF)
Public Const AdcChVss = 27
Public Const AdcChFvr = 30
#elseif _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)
' PIC16F153xx, ADCON0.CHS [DS40001866E Register 20-1 p.280, the other data sheets alike]: RA0..RA7 = 0..7, RB0..RB7 = 8..15, RC0..RC7 = 16..23, RD0..RD7 = 24..31, RE0..RE2 = 32..34, RF0..RF7 = 40..47
' (the pins the part has), AVSS 59, temperature indicator 60, DAC1 61, FVR buffer 1 62 and buffer 2 63. AdcChFvr is buffer 1, the one the ADC reference uses (ADFVR).
Public Const AdcChVss = 59
Public Const AdcChTemp = 60
Public Const AdcChDac = 61
Public Const AdcChFvr = 62
Public Const AdcChFvr2 = 63
#elseif _has(ADCON0.CHS)
Public Const AdcChVss = 60
Public Const AdcChTemp = 61
Public Const AdcChDac = 62
Public Const AdcChFvr = 63
#elseif _has(ADCPCON)
' PIC18F0x/1xQ41, ADPCH [DS40002214G 40.7.8]: RA0..RA5 = 0..5, RB4..RB7 = 12..15, RC0..RC7 = 16..23 (RB
' on the 20-pin parts only; RA3 is input only). AdcChFvr is FVR buffer 1, the one the ADC reference uses
' (ADFVR); AdcChFvr2 is buffer 2 (CDAFVR).
Public Const AdcChDac2 = 58
Public Const AdcChVss = 59
Public Const AdcChTemp = 60
Public Const AdcChDac = 61
Public Const AdcChFvr = 62
Public Const AdcChFvr2 = 63
#elseif _has(PRODL) and _has(ADREF.ADPREF)
Public Const AdcChVss = 60
Public Const AdcChTemp = 61
Public Const AdcChDac = 62
Public Const AdcChFvr = 63
#elseif Not _has(OSCCON1)
' PIC16F18056/76, ADPCH [DS40002325C Table 31-6 p.428]: RA0..RA7 = 0..7, RB = 8..15, RC = 16..23, RD = 24..31 and RE0..RE2 = 32..34 on the 40-pin part. AdcChFvr is FVR buffer 1, the one the ADC
' reference uses (ADFVR); AdcChFvr2 is buffer 2. There is no DAC channel.
Public Const AdcChVss = 58
Public Const AdcChTemp = 59
Public Const AdcChFvr = 62
Public Const AdcChFvr2 = 63
#else
' PIC16F17126/46, ADPCH [DS40002343F Table 33-6]: RA0, RA1, RA2, RA4, RA5 = 0, 1, 2, 4, 5 (3 is the guard
' ring ADCG1, not a pin); RB4..RB7 = 12..15 and RC0..RC7 = 16..23 (RB and RC6, RC7 on the 20-pin part only).
' AdcChFvr is FVR buffer 1, the one the ADC reference uses (ADFVR).
Public Const AdcChVss = 58
Public Const AdcChTemp = 59
Public Const AdcChDac = 60
#if _has(CLBCON)
Public Const AdcChFvr2 = 63
#else
Public Const AdcChDac2 = 61
#endif
Public Const AdcChFvr = 62
#endif

' Largest result: 10 bits on the Q10 [DS40002043F AD01], 12 bits on the PIC16F171xx [DS40002343F AD01] and
' the Q41 [DS40002214G AD01].
#if _has(ADCON0.CHS) Or _has(CLBCON) Or (_has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)) Or Not _has(OSCCON1)
Public Const AdcMax = 1023
#else
Public Const AdcMax = 4095
#endif

' Acquisition time written by SetClock, in microseconds: 5 us is the 10 kohm worked example of the Q10 (4.62 us);
' the Q41's own example for 12 bits is 7.79 us (Equation 40-1), covered by 8 us. [40.3]
#if _has(ADCPCON)
Const AcqUs = 8
#else
Const AcqUs = 5
#endif

' Smallest TAD in nanoseconds: 1 us [AD20], 2 us on the PIC16F13145 family (erratum 1.1.1), 0.5 us on the PIC16F152xx and PIC16F132xx parts.
#if _has(CLBCON) And Not _has(HLVDCON0)
Const MinTadNs = 2000
#elseif _has(CLBCON) Or _has(ADCON1.PREF)
Const MinTadNs = 500
#else
Const MinTadNs = 1000
#endif

#if _has(ADCON0.CHS)
Dim AdcGo As ADCON0.1
#else
Dim AdcGo As ADCON0.0
#endif
Dim FvrReady As FVRCON.6
Dim lastCh As Byte
Dim adinUp As Boolean

' FOSC in Hz. Everything SetClock needs is known when the program is compiled, so the divisions below are
' done by the compiler and SetClock is a few register writes (it used to be about 400 words of 32-bit arithmetic).
Const FoscHz As LongWord = LongWord(_Clock * 1000000)
' (As before, the ADC clock follows `Clock`, not a FOSC changed at run time with Intosc.)

#if _has(ADCON0.CHS)
' FOSC/n with n >= FOSC * MinTadNs / 1e9: ADCS codes for n = 2, 4, 8, 16, 32, 64 are 0, 4, 1, 5, 2, 6 [Register 22-2].
Const AdcN As LongWord = (FoscHz / 1000 * MinTadNs + 999999) / 1000000

' Sets the conversion clock for at least MinTadNs nanoseconds per TAD.
Sub SetClock()
    Dim code As Byte
    code = 6
    If AdcN <= 32 Then
        code = 2
    End If
    If AdcN <= 16 Then
        code = 5
    End If
    If AdcN <= 8 Then
        code = 1
    End If
    If AdcN <= 4 Then
        code = 4
    End If
    If AdcN <= 2 Then
        code = 0
    End If
    ADCON1 = (ADCON1 And 143) Or (code << 4)
End Sub

#if _has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF)
' The same for TAD >= 8 us (silicon erratum 1.1 of DS80000721D, DS80000717K and DS80000725F, AdcRefFvr): the slowest FOSC/n (n = 64) when 8 us cannot be reached.
Const AdcNSlow As LongWord = (FoscHz / 1000 * 8000 + 999999) / 1000000

Sub SetClockSlow()
    Dim code As Byte
    code = 6
    If AdcNSlow <= 32 Then
        code = 2
    End If
    If AdcNSlow <= 16 Then
        code = 5
    End If
    If AdcNSlow <= 8 Then
        code = 1
    End If
    If AdcNSlow <= 4 Then
        code = 4
    End If
    If AdcNSlow <= 2 Then
        code = 0
    End If
    ADCON1 = (ADCON1 And 143) Or (code << 4)
End Sub
#endif
#else
' ADCS = m - 1 with m = ceil(FOSC * TAD / 2e9), 1..64, and ADACQ = ceil(AcqUs / TAD) with TAD = 2 * m / FOSC, at most 255
' on the Q10, where ADACQ counts ADC clocks [DS40002043F 33.7.10]. The ADCC of the Q41 and the PIC16F171xx has a 13-bit ADACQ
' counted in FOSC clocks (or ADCRC clocks with CS = 1) [DS40002214G 40.7.10, DS40002343F 33.5.11, DS40002519D 32.5.10]:
' ADACQ = ceil(FOSC * AcqUs / 1e6), at most 8191.
Const AdcM As LongWord = Min(Max((FoscHz / 1000 * MinTadNs + 1999999) / 2000000, 1), 64)
#if _has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)
Const AdcAcq As LongWord = Min((FoscHz * AcqUs + AdcM * 2000000 - 1) / (AdcM * 2000000), 255)
#else
Const AdcAcq As LongWord = Min((FoscHz / 1000 * AcqUs + 999) / 1000, 8191)
#endif

' Sets the conversion clock for at least MinTadNs nanoseconds per TAD and the acquisition time to AcqUs.
Sub SetClock()
    ADCLK = Byte(AdcM - 1)
#if _has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)
    ADACQ = Byte(AdcAcq)
#else
    ADACQ = Word(AdcAcq)
#endif
End Sub

#if _has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)
' The same for TAD >= 8 us (erratum 1.4.1, AdcRefFvr).
Const AdcMSlow As LongWord = Min(Max((FoscHz / 1000 * 8000 + 1999999) / 2000000, 1), 64)
Const AdcAcqSlow As LongWord = Min((FoscHz * AcqUs + AdcMSlow * 2000000 - 1) / (AdcMSlow * 2000000), 255)

Sub SetClockSlow()
    ADCLK = Byte(AdcMSlow - 1)
    ADACQ = Byte(AdcAcqSlow)
End Sub
#endif
#endif

Public Sub AdcInit()
#if _has(ADCON0.CHS)
    ADCON0 = 0
    ADCON1 = 128
    ADACT = 0
#if _has(ADCON1.PREF)
    ' CPON resets to 00 (off) [CPCON p.335]; 01 = on when the ADC is enabled and VDD < 4.6 V.
    CPCON = 64
#endif
    SetClock()
    lastCh = 255
    ' ADON with channel 0; ADFM = 1 (right-justified) is set above; the channel is selected by AdcRead.
    ADCON0 = 1
End Sub
#else
    ADCON0 = 0
    ADCON1 = 0
    ADCON2 = 0
    ADCON3 = 0
    ADCAP = 0
    ADPRE = 0
    ADACT = 0
    ADREF = 0
#if _has(ADCPCON)
    ' The charge pump runs when the ADC asks for it [40.4, ADCP]; it keeps the converter accurate at low VDD.
    ADCPCON = 128
#elseif _has(CPCON) And Not _has(CLBCON)
    ' Errata 1.6.1 (DS80001009E, all silicon revisions; PIC16F18056/76: 1.1.1, DS80001014D): CPON resets to 00 (off) instead of 01; write 01, charge pump on
    ' when the ADC is enabled and VDD < 4.6 V [40.7.1].
    CPCON = 64
#endif
    SetClock()
    lastCh = 255
    ' ADON, ADFM = 1 (right-justified), ADCS = 0 (FOSC); ADGO is set later, not with ADON [33.2.1].
    ADCON0 = 132
End Sub
#endif

' Makes the pin of channel 0..23 (0..34 on a part with port D and E, the PIC16F18076 and the larger PIC16F153xx; 40..47 for port F, the PIC16(L)F15385/86) an analog input (TRISx = 1, ANSELx = 1) [33.1.1]. Other
' channel numbers are internal and need no pin.
Public Sub AdcPin(ByVal ch As Byte)
    Dim m As Byte
    m = 1 << (ch And 7)
    If ch < 8 Then
        TRISA = TRISA Or m
        ANSELA = ANSELA Or m
#if _has(TRISB)
    ElseIf ch < 16 Then
        TRISB = TRISB Or m
        ANSELB = ANSELB Or m
#endif
#if _has(TRISC)
#if _has(TRISB)
    ElseIf ch < 24 Then
#else
    ' No port B (the 14-pin PIC16F131xx parts): channels 8..15 are not pins and must not reach port C.
    ElseIf ch >= 16 And ch < 24 Then
#endif
        TRISC = TRISC Or m
        ANSELC = ANSELC Or m
#endif
#if _has(TRISD)
    ElseIf ch >= 24 And ch < 32 Then
        TRISD = TRISD Or m
        ANSELD = ANSELD Or m
    ElseIf ch >= 32 And ch < 35 Then
        TRISE = TRISE Or m
        ANSELE = ANSELE Or m
#endif
#if _has(TRISF)
    ElseIf ch >= 40 And ch < 48 Then
        TRISF = TRISF Or m
        ANSELF = ANSELF Or m
#endif
    End If
End Sub

' Positive reference = VDD, negative = VSS (the reset state).
Public Sub AdcRefVdd()
#if _has(ADCON0.CHS)
    ADCON1 = ADCON1 And 252
    lastCh = 255
#else
    ADREF = 0
#endif
    FVRCON = FVRCON And 252
    SetClock()
End Sub

' Positive reference = FVR at gain 1, 2 or 4 (1.024, 2.048, 4.096 V; the output cannot exceed VDD)
' [30.4.1]. Waits for FVRRDY. Errata 1.4.1: TAD is raised to >= 8 us when ADCS allows it.
Public Sub AdcRefFvr(ByVal gain As Byte)
    ' ADFVR field: 1 = 1x, 2 = 2x, 3 = 4x
    If gain >= 4 Then
        gain = 3
    End If
    If gain = 0 Then
        gain = 1
    End If
    FVRCON = (FVRCON And 252) Or gain Or 128
    While FvrReady = 0
    Wend
#if _has(ADCON0.CHS)
    ADCON1 = ADCON1 Or 3
    lastCh = 255
#else
    ADREF = 3
#endif
#if (_has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)) Or (_has(ADCON0.CHS) And _has(T2HLT) And Not _has(ADCON1.PREF))
    SetClockSlow()
#else
    SetClock()
#endif
End Sub

' One conversion on the currently selected channel; returns the result (0..AdcMax).
Function Convert() As Word
    AdcGo = 1
    While AdcGo = 1
    Wend
    ' ADRESL first, then ADRESH, straight into Result (no temporary).
    Result = ADRESL
    Result.Byte1 = ADRESH
End Function

' Converts channel `ch` (0..63, see the AdcCh constants) and returns 0..AdcMax.
Public Function AdcRead(ByVal ch As Byte) As Word
    ch = ch And 63
    If ch <> lastCh Then
#if _has(ADCON0.CHS)
        ADCON0 = (ch << 2) Or 1
        DelayUs(5)
#else
        ADPCH = ch
#endif
#if _has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)
        ' The first conversion after a channel change is dropped (erratum 1.4.4).
        Convert()
#endif
        lastCh = ch
    End If
    Result = Convert()
End Function

' Mean of `count` (1..64) conversions, rounded down; 0 for a count of 0.
Public Function AdcReadAvg(ByVal ch As Byte, ByVal count As Byte) As Word
    Dim sum As Word
    Dim i As Byte
    sum = 0
    i = 0
    While i < count
        sum = sum + AdcRead(ch)
        Inc(i)
    Wend
    Result = 0
    If count > 0 Then
        Result = sum / count
    End If
End Function

' Converts a result to millivolts for a reference of `vrefMv` millivolts: raw * vref / AdcMax.
Public Function AdcMillivolts(ByVal raw As Word, ByVal vrefMv As Word) As Word
    Result = Word(LongWord(raw) * vrefMv / AdcMax)
End Function

' ADin: the one-call read. The first call runs AdcInit; a call for another channel than the last one makes
' that channel's pin an analog input (AdcPin; internal channels 24..63 need none). Then one conversion, 0..AdcMax.
' Calling AdcInit or AdcRef... afterwards is fine (they keep the module state); a program that sets the ADC up
' by hand before the first ADin has it set up again by that call.
Public Function ADin(ByVal ch As Byte) As Word
    If Not adinUp Then
        AdcInit()
        adinUp = True
    End If
    ch = ch And 63
    If ch <> lastCh Then
        AdcPin(ch)
    End If
    Result = AdcRead(ch)
End Function
