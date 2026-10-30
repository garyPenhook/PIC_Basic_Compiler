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
' counts ADC clocks [33.7.10] and is set to cover 5 us, the 10 kohm worked example of Equation
' 33-1 (4.62 us). A higher source impedance needs a longer time: write ADACQ after AdcInit.
'
' PIC16F13145 family (DS40002519D, chapter 32, 10 bits; chosen with `#if _has(CLBCON)`): the same registers; channels RA0..RA2, RA4, RA5 = 0..2, 4, 5,
' RB4..RB7 = 12..15, RC0..RC7 = 16..23 (RB and RC6, RC7 on the 20-pin parts, RC on the 14- and 20-pin ones), VSS 58, temperature indicator 59,
' DAC1 60, FVR buffer 1 62 and buffer 2 63 [Table 32-6 p.465]. Silicon erratum 1.1.1 (DS80001115F, revision A2): the real minimum TAD
' is 2 us, not the 1 us of AD20, so the conversion clock is chosen for TAD >= 2 us on this family (the limit is 9 us, AD20 p.557).
' CPON resets to 01 there (CPCON p.514), so no charge pump write is needed.
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
#if _has(ADCPCON)
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
#if _has(CLBCON) Or (_has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON))
Public Const AdcMax = 1023
#else
Public Const AdcMax = 4095
#endif

' Acquisition time set by SetClock, in microseconds: 5 us is the 10 kohm worked example of the Q10 (4.62 us);
' the Q41's own example for 12 bits is 7.79 us (Equation 40-1), covered by 8 us. [40.3]
#if _has(ADCPCON)
Const AcqUs = 8
#else
Const AcqUs = 5
#endif

' Smallest TAD in nanoseconds: 1 us [AD20], 2 us on the PIC16F13145 family (erratum 1.1.1).
#if _has(CLBCON)
Const MinTadNs = 2000
#else
Const MinTadNs = 1000
#endif

Dim AdcGo As ADCON0.0
Dim FvrReady As FVRCON.6
Dim lastCh As Byte
Dim fosc As LongWord

' Sets the conversion clock for at least `minNs` nanoseconds per TAD and the acquisition time
' to 5 us: ADCS = n with n + 1 = ceil(FOSC * minNs / 2e9), at least 1 and at most 64.
Sub SetClock(ByVal minNs As Word)
    Dim m As LongWord
    Dim acq As LongWord
    m = (fosc / 1000 * minNs + 1999999) / 2000000
    If m < 1 Then
        m = 1
    End If
    If m > 64 Then
        m = 64
    End If
    ADCLK = Byte(m - 1)
    ' ADACQ = ceil(AcqUs / TAD) with TAD = 2 * m / FOSC
    acq = (fosc * AcqUs + m * 2000000 - 1) / (m * 2000000)
    If acq > 255 Then
        acq = 255
    End If
    ADACQ = Byte(acq)
End Sub

Public Sub AdcInit()
    fosc = LongWord(_Clock * 1000000)
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
    ' Errata 1.6.1 (DS80001009E, all silicon revisions): CPON resets to 00 (off) instead of 01; write 01, charge pump on
    ' when the ADC is enabled and VDD < 4.6 V [40.7.1].
    CPCON = 64
#endif
    SetClock(MinTadNs)
    lastCh = 255
    ' ADON, ADFM = 1 (right-justified), ADCS = 0 (FOSC); ADGO is set later, not with ADON [33.2.1].
    ADCON0 = 132
End Sub

' Makes the pin of channel 0..23 an analog input (TRISx = 1, ANSELx = 1) [33.1.1]. Other
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
    End If
End Sub

' Positive reference = VDD, negative = VSS (the reset state).
Public Sub AdcRefVdd()
    ADREF = 0
    FVRCON = FVRCON And 252
    SetClock(MinTadNs)
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
    ADREF = 3
#if _has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)
    SetClock(8000)
#else
    SetClock(MinTadNs)
#endif
End Sub

' One conversion on the currently selected channel; returns the result (0..AdcMax).
Function Convert() As Word
    Dim lo As Byte
    AdcGo = 1
    While AdcGo = 1
    Wend
    lo = ADRESL
    Result = ADRESH * 256 + lo
End Function

' Converts channel `ch` (0..63, see the AdcCh constants) and returns 0..AdcMax.
Public Function AdcRead(ByVal ch As Byte) As Word
#if _has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)
    Dim dummy As Word
#endif
    ch = ch And 63
    If ch <> lastCh Then
        ADPCH = ch
#if _has(PRODL) and _has(ADREF.ADPREF) and not _has(ADCPCON)
        dummy = Convert()
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
