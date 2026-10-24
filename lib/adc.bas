Module Adc
' 10-bit ADC with computation (ADCC), basic mode, right-justified results (DS40002043F, chapter 33).
' Conversions are started by software and the clock is derived from FOSC, so `Clock` must be FOSC
' in MHz. The module is not reentrant: do not call it from a handler and from the main program.
'
' Conversion clock [33.1.4, ADCLK, Table 39-14 AD20]: TAD = 2 * (n + 1) / FOSC and must lie in
' 1..9 us. AdcInit picks the smallest TAD >= 1 us. Acquisition is done by the hardware: ADACQ
' counts ADC clocks [33.7.10] and is set to cover 5 us, the 10 kohm worked example of Equation
' 33-1 (4.62 us). A higher source impedance needs a longer time: write ADACQ after AdcInit.
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
Public Const AdcChVss = 60
Public Const AdcChTemp = 61
Public Const AdcChDac = 62
Public Const AdcChFvr = 63

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
    ' ADACQ = ceil(5 us / TAD) with TAD = 2 * m / FOSC
    acq = (fosc * 5 + m * 2000000 - 1) / (m * 2000000)
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
    SetClock(1000)
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
    ElseIf ch < 16 Then
        TRISB = TRISB Or m
        ANSELB = ANSELB Or m
    ElseIf ch < 24 Then
        TRISC = TRISC Or m
        ANSELC = ANSELC Or m
    End If
End Sub

' Positive reference = VDD, negative = VSS (the reset state).
Public Sub AdcRefVdd()
    ADREF = 0
    FVRCON = FVRCON And 252
    SetClock(1000)
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
    SetClock(8000)
End Sub

' One conversion on the currently selected channel; returns the 10-bit result.
Function Convert() As Word
    Dim lo As Byte
    AdcGo = 1
    While AdcGo = 1
    Wend
    lo = ADRESL
    Result = ADRESH * 256 + lo
End Function

' Converts channel `ch` (0..63, see the AdcCh constants) and returns 0..1023.
Public Function AdcRead(ByVal ch As Byte) As Word
    Dim dummy As Word
    ch = ch And 63
    If ch <> lastCh Then
        ADPCH = ch
        dummy = Convert()
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

' Converts a result to millivolts for a reference of `vrefMv` millivolts: raw * vref / 1023.
Public Function AdcMillivolts(ByVal raw As Word, ByVal vrefMv As Word) As Word
    Result = Word(LongWord(raw) * vrefMv / 1023)
End Function
