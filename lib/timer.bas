Module Timer
' Timer0, Timer1 and Timer2 helpers (PIC18F27/47Q10: DS40002043F chapters 19, 20, 21; PIC16F17126/46:
' DS40002343F chapters 22, 23, 24; PIC18F0x/1xQ41: DS40002214G chapters 24, 25, 26). The control registers have
' the same layout on all of them; the interrupt flag registers and the source-selection constants below
' differ, and are chosen with `#if _has(PIR1.TMR1IF)` (true for the PIC16F171xx, whose Timer1 and Timer2 flags
' are in PIR1 and PIR2) and `#if _has(PIR3.TMR1IF)` (true for the PIC18-Q41, whose flags are in PIR3). The module only configures the timer and reads its
' flag. It declares no interrupt handler, so it never claims a vector: to be interrupted, call
' Timer0EnableInterrupt, write your own `Interrupt` and call Timer0Ack in it (flags are not
' cleared by hardware). To run your own code on each overflow instead, use the TimerNOnExpire event
' and TimerNService below.
'
' Clock source is FOSC/4 [Table 19-1, T0CS = 010]. In 8-bit mode the timer counts 0..period and
' then restarts, so one overflow takes (period + 1) * 2^prescale instruction cycles
' (prescale 0..15 selects 1:1 to 1:32768 [T0CON1]).
'
' PIC16F183xx (DS40001799F, DS40001800E, DS40001795K, DS40001839E, chapters 26, 27 and 28; chosen with `#if _has(T1CON.TMR1CS)`): Timer0 is the same. Timer1 has no
' clock-select register: T1CON = TMR1CS<1:0> (bits 7-6) | T1CKPS<1:0> (5-4) | T1SOSC | T1SYNC | TMR1ON [Register 27-1], T1GCON holds the gate source
' T1GSS<1:0> [Register 27-2], and there is no RD16 bit (bit 1 is unimplemented, although 27.4 describes it), so Timer1Read reads TMR1H twice. Timer2
' is the older one: T2CON = T2OUTPS<3:0> (6-3) | TMR2ON (2) | T2CKPS<1:0> (1-0) with prescalers 1, 4, 16, 64 [Register 28-1]; PR2 and TMR2; no hardware-limit
' modes, so there are no T2Mode*/T2Rst* constants and no Timer2StartLimit. The Timer2 prescale argument is 0..3 for 1:1, 1:4, 1:16, 1:64. The flags are in PIR1 (TMR1IF bit 0, TMR2IF
' bit 1, TMR1GIF bit 7) and PIR0 (TMR0IF bit 5). No Timer1 secondary oscillator or Timer0 clock source constants are offered.
'
' PIC16F152xx (DS40002195E, chapters 19, 20 and 21; chosen with `#if _has(ADCON1.PREF)`): Timer0 is the same, Timer1 (T1CON, T1CLK, T1GATE, T1GCON, RD16) and Timer2 (T2CON, T2HLT, T2CLKCON, T2RST,
' T2PR) have the layout of the PIC16F171xx, with the flags in PIR0 (TMR0IF bit 5), PIR1 (TMR1IF bit 5, TMR2IF bit 6) and PIR2 (TMR1GIF bit 5) [12.9.5 to 12.9.7] and their enables in PIE0 and PIE1. The clock,
' gate and reset source codes are the part's own [Tables 20-4, 20-5, 21-4 p.174-197]: there is no secondary oscillator and no comparator, and the CCP1, CCP2, PWM3 and PWM4 outputs are the gate and reset sources.
' The handler type of the TimerNOnExpire hooks.
Public Type TTimerEvent = Event()
#if _has(T1CON.TMR1CS)
' Timer1 clock sources, the TMR1CS field of T1CON [DS40001839E Table 27-2 p.285]. T1ClkPin counts rising edges on the pin selected by T1CKIPPS.
Public Const T1ClkFosc4 = 0
Public Const T1ClkFosc = 1
Public Const T1ClkPin = 2
Public Const T1ClkLfIntOsc = 3

' Timer1 gate sources, the T1GSS field of T1GCON [Register 27-2 p.294]. T1GatePin is the pin selected by T1GPPS; the comparator outputs may be synchronised.
Public Const T1GatePin = 0
Public Const T1GateTmr0 = 1
Public Const T1GateCmp1 = 2
Public Const T1GateCmp2 = 3
#elseif _has(ADCON1.PREF)
' Timer1 clock sources, the CS field of T1CLK [DS40002195E Table 20-4 p.174]. T1ClkPin counts rising edges on the pin selected by T1CKIPPS; T1ClkMfIntOsc is the 500 kHz MFINTOSC,
' T1ClkMfIntOsc32 the 32 kHz one.
Public Const T1ClkPin = 0
Public Const T1ClkFosc4 = 1
Public Const T1ClkFosc = 2
Public Const T1ClkHfIntOsc = 3
Public Const T1ClkLfIntOsc = 4
Public Const T1ClkSfIntOsc = 5
Public Const T1ClkMfIntOsc = 6
Public Const T1ClkMfIntOsc32 = 7
Public Const T1ClkTmr0 = 8

' Timer1 gate sources, the GSS field of T1GATE [Table 20-5 p.175]. T1GatePin is the pin selected by T1GPPS; T1GateTmr2 is the postscaled Timer2 output.
Public Const T1GatePin = 0
Public Const T1GateTmr0 = 1
Public Const T1GateTmr2 = 2
Public Const T1GateCcp1 = 3
Public Const T1GateCcp2 = 4
Public Const T1GatePwm3 = 5
Public Const T1GatePwm4 = 6
#elseif _has(PIR3.TMR1IF)
' Timer1 clock sources, the CS field of T1CLK [DS40002214G Table 25-4]. T1ClkPin counts rising edges on the
' pin selected by T1CKIPPS; T1ClkSosc needs OSCEN.SOSCEN set and time to stabilise. T1ClkMfIntOsc is the
' 500 kHz MFINTOSC, T1ClkMfIntOsc32 the 32 kHz one.
Public Const T1ClkPin = 0
Public Const T1ClkFosc4 = 1
Public Const T1ClkFosc = 2
Public Const T1ClkHfIntOsc = 3
Public Const T1ClkLfIntOsc = 4
Public Const T1ClkMfIntOsc = 5
Public Const T1ClkMfIntOsc32 = 6
Public Const T1ClkSosc = 7
Public Const T1ClkExtOsc = 8
Public Const T1ClkRef = 9
Public Const T1ClkTmr0 = 10
Public Const T1ClkTmr3 = 12

' Timer1 gate sources, the GSS field of T1GATE [DS40002214G Table 25-5]. T1GatePin is the pin selected by T1GPPS.
Public Const T1GatePin = 0
Public Const T1GateTmr0 = 1
Public Const T1GateTmr2 = 3
Public Const T1GateTmr4 = 5
Public Const T1GateSmt1 = 6
Public Const T1GateCcp1 = 7
Public Const T1GateNco1 = 14
Public Const T1GateCmp1 = 15
Public Const T1GateCmp2 = 16
Public Const T1GateZcd = 17
#elseif _has(PIR1.TMR1IF)
' Timer1 clock sources, the CS field of T1CLK [DS40002343F Table 23-4]. T1ClkPin counts rising edges on the
' pin selected by T1CKIPPS; T1ClkSosc needs the secondary oscillator enabled and time to stabilise.
Public Const T1ClkPin = 0
Public Const T1ClkFosc4 = 1
Public Const T1ClkFosc = 2
Public Const T1ClkHfIntOsc = 3
Public Const T1ClkLfIntOsc = 4
Public Const T1ClkSfIntOsc = 5
Public Const T1ClkMfIntOsc = 6
#if _has(OSCEN.SOSCEN)
Public Const T1ClkSosc = 8
#else
' PIC16F13145 family (DS40002519D Table 22-4 p.245): no secondary oscillator; 7 is the 32 kHz MFINTOSC (6 is the 500 kHz one)
' and 9 is EXTOSC.
Public Const T1ClkMfIntOsc32 = 7
Public Const T1ClkExtOsc = 9
#endif
Public Const T1ClkTmr0 = 11

' Timer1 gate sources, the GSS field of T1GATE [DS40002343F Table 23-5]. T1GatePin is the pin selected by T1GPPS.
Public Const T1GatePin = 0
Public Const T1GateTmr0 = 1
Public Const T1GateTmr2 = 3
Public Const T1GateCcp1 = 7
Public Const T1GateCcp2 = 8
Public Const T1GateCmp1 = 18
Public Const T1GateCmp2 = 19
#else
' Timer1 clock sources, the CS field of T1CLK [Table 20-2]. T1ClkPin counts rising edges on the
' T1CKI pin (RC0 at reset, T1CKIPPS); T1ClkSosc needs OSCEN.SOSCEN set and time to stabilise.
Public Const T1ClkPin = 0
Public Const T1ClkFosc4 = 1
Public Const T1ClkFosc = 2
Public Const T1ClkHfIntOsc = 3
Public Const T1ClkLfIntOsc = 4
Public Const T1ClkMfIntOsc = 5
Public Const T1ClkSosc = 6
Public Const T1ClkTmr0 = 8

' Timer1 gate sources, the GSS field of T1GATE [Table 20-4]. T1GatePin is the T1G pin (RB5 at
' reset, T1GPPS).
Public Const T1GatePin = 0
Public Const T1GateTmr0 = 1
Public Const T1GateTmr2 = 3
Public Const T1GateCcp1 = 8
Public Const T1GateCcp2 = 9
Public Const T1GateCmp1 = 12
Public Const T1GateCmp2 = 13
#endif

#if Not _has(T1CON.TMR1CS)
' Timer2 operating modes, the MODE field of T2HLT [Table 21-3]. The "Gate" and "Reset" modes
' keep the free-running period; the "OneShot" modes stop at the period match and clear ON;
' the "Mono" modes stop at the period match but leave ON set. Edge and level are those of the
' reset source.
Public Const T2ModeSoftware = 0
Public Const T2ModeGateHigh = 1
Public Const T2ModeGateLow = 2
Public Const T2ModeResetAnyEdge = 3
Public Const T2ModeResetRising = 4
Public Const T2ModeResetFalling = 5
Public Const T2ModeResetLow = 6
Public Const T2ModeResetHigh = 7
Public Const T2ModeOneShot = 8
Public Const T2ModeOneShotRising = 9
Public Const T2ModeOneShotFalling = 10
Public Const T2ModeOneShotAnyEdge = 11
Public Const T2ModeOneShotRisingReset = 12
Public Const T2ModeOneShotFallingReset = 13
Public Const T2ModeOneShotRisingLow = 14
Public Const T2ModeOneShotFallingHigh = 15
Public Const T2ModeMonoRising = 17
Public Const T2ModeMonoFalling = 18
Public Const T2ModeMonoAnyEdge = 19
Public Const T2ModeOneShotLevelHigh = 22
Public Const T2ModeOneShotLevelLow = 23
#endif

#if _has(T1CON.TMR1CS)
' No Timer2 reset sources on the PIC16F183xx.
#elseif _has(ADCON1.PREF)
' Timer2 external reset sources, the RSEL field of T2RST [DS40002195E Table 21-4 p.197]. T2RstPin is the pin selected by T2INPPS.
Public Const T2RstPin = 0
Public Const T2RstCcp1 = 1
Public Const T2RstCcp2 = 2
Public Const T2RstPwm3 = 3
Public Const T2RstPwm4 = 4
#elseif _has(PIR3.TMR1IF)
' Timer2 external reset sources, the RSEL field of T2RST [DS40002214G Table 26-4]. T2RstPin is the pin
' selected by T2INPPS; T2RstPwmNP1 / T2RstPwmNP2 are the outputs of PWM module N (PWMNS1P1 / PWMNS1P2).
Public Const T2RstPin = 0
Public Const T2RstTmr4 = 2
Public Const T2RstCcp1 = 4
Public Const T2RstPwm1P1 = 5
Public Const T2RstPwm1P2 = 6
Public Const T2RstPwm2P1 = 7
Public Const T2RstPwm2P2 = 8
Public Const T2RstPwm3P1 = 9
Public Const T2RstPwm3P2 = 10
Public Const T2RstCmp1 = 11
Public Const T2RstCmp2 = 12
Public Const T2RstZcd = 13
#elseif _has(PIR1.TMR1IF)
' Timer2 external reset sources, the RSEL field of T2RST [DS40002343F Table 24-4]. T2RstPin is the pin
' selected by T2INPPS. The PIC16F13145 family (DS40002519D Table 23-4 p.268) has no Timer4, and the same CCP and comparator codes.
Public Const T2RstPin = 0
#if _has(T4CON)
Public Const T2RstTmr4 = 2
#endif
Public Const T2RstCcp1 = 4
Public Const T2RstCcp2 = 5
Public Const T2RstCmp1 = 14
Public Const T2RstCmp2 = 15
#else
' Timer2 external reset sources, the RSEL field of T2RST [Table 21-2]. T2RstPin is the T2IN pin
' (RC3 at reset, T2INPPS).
Public Const T2RstPin = 0
Public Const T2RstTmr4 = 2
Public Const T2RstTmr6 = 3
Public Const T2RstCcp1 = 4
Public Const T2RstCcp2 = 5
Public Const T2RstPwm3 = 6
Public Const T2RstPwm4 = 7
Public Const T2RstCmp1 = 8
Public Const T2RstCmp2 = 9
#endif

#if _has(T1CON.TMR1CS)
Dim Tmr0If As PIR0.5
Dim Tmr0Ie As PIE0.5
Dim Tmr1If As PIR1.0
Dim Tmr1GIf As PIR1.7
Dim Tmr1Ie As PIE1.0
Dim Tmr2If As PIR1.1
Dim Tmr2Ie As PIE1.1
#elseif _has(ADCON1.PREF)
Dim Tmr0If As PIR0.5
Dim Tmr0Ie As PIE0.5
Dim Tmr1If As PIR1.5
Dim Tmr1GIf As PIR2.5
Dim Tmr1Ie As PIE1.5
Dim Tmr2If As PIR1.6
Dim Tmr2Ie As PIE1.6
#elseif _has(PIR3.TMR1IF)
' PIR3 / PIE3 bits 7, 4 and 3 [DS40002214G 11.13.21, 11.13.10].
Dim Tmr0If As PIR3.7
Dim Tmr0Ie As PIE3.7
Dim Tmr1If As PIR3.4
Dim Tmr1Ie As PIE3.4
Dim Tmr2If As PIR3.3
Dim Tmr2Ie As PIE3.3
#elseif _has(PIR1.TMR1IF)
Dim Tmr0If As PIR0.5
Dim Tmr0Ie As PIE0.5
Dim Tmr1If As PIR1.6
Dim Tmr1GIf As PIR1.7
Dim Tmr1Ie As PIE1.6
Dim Tmr2If As PIR2.2
Dim Tmr2Ie As PIE2.2
#else
Dim Tmr0If As PIR0.5
Dim Tmr0Ie As PIE0.5
Dim Tmr1If As PIR4.0
Dim Tmr1Ie As PIE4.0
Dim Tmr2If As PIR4.1
Dim Tmr2Ie As PIE4.1
#endif
Dim T1GoDone As T1GCON.3
Dim T1GateVal As T1GCON.2
#if _has(T1CON.TMR1CS)
Dim Tmr2On As T2CON.2
#else
Dim Tmr2On As T2CON.7
#endif

' 8-bit periodic timer. period = 0..255.
Public Sub Timer0Start(ByVal prescale As Byte, ByVal period As Byte)
    T0CON0 = 0
    T0CON1 = 64 + (prescale And 15)
    TMR0H = period
    TMR0L = 0
    Tmr0If = 0
    T0CON0 = 128
End Sub

' 16-bit free-running timer, read with Timer0Read.
Public Sub Timer0Start16(ByVal prescale As Byte)
    T0CON0 = 0
    T0CON1 = 64 + (prescale And 15)
    TMR0L = 0
    TMR0H = 0
    Tmr0If = 0
    T0CON0 = 144
End Sub

Public Sub Timer0Stop()
    T0CON0 = 0
End Sub

' 16-bit count. TMR0L is read first, which latches TMR0H [19.1.2].
Public Function Timer0Read() As Word
    Dim lo As Byte
    lo = TMR0L
    Result = TMR0H * 256 + lo
End Function

' True once per overflow; clears the flag when it reports it.
Public Function Timer0Expired() As Boolean
    Result = False
    If Tmr0If = 1 Then
        Tmr0If = 0
        Result = True
    End If
End Function

Public Sub Timer0Ack()
    Tmr0If = 0
End Sub

Public Sub Timer0EnableInterrupt()
    Tmr0If = 0
    Tmr0Ie = 1
End Sub

Public Sub Timer0DisableInterrupt()
    Tmr0Ie = 0
End Sub

' Event hook: assign a handler to Timer0OnExpire, start the timer, and call Timer0Service regularly (from the
' main loop, or from your own Interrupt inside Save(0, Timer0Service)). Each overflow acknowledges the flag and
' calls the handler once. An unassigned Timer0OnExpire does nothing.
Public Dim Timer0OnExpire As TTimerEvent
Public Sub Timer0Service()
    If Timer0Expired() Then
        Timer0OnExpire()
    End If
End Sub

' Timer1: 16-bit, FOSC/4 clock [Table 20-2, T1CLK CS = 00001], T1CON = CKPS[5:4] | RD16 | ON
' [20.14.1]; no gate [T1GCON = 0]. It overflows every 65536 * 2^prescale instruction cycles
' (prescale 0..3 selects 1:1 to 1:8). With RD16 set, reading TMR1L latches TMR1H.
Public Sub Timer1Start(ByVal prescale As Byte)
    T1CON = 0
#if Not _has(T1CON.TMR1CS)
    T1CLK = 1
#endif
    T1GCON = 0
    TMR1L = 0
    TMR1H = 0
    Tmr1If = 0
#if _has(T1CON.TMR1CS)
    T1CON = (prescale And 3) * 16 + 1
#else
    T1CON = (prescale And 3) * 16 + 3
#endif
End Sub

' Timer1 from any clock in T1Clk*, free-running and ungated. The external sources are
' synchronised to the system clock (SYNC = 0), so the pulses must be longer than a system clock
' cycle; asynchronous operation (for Sleep) is not offered. The input pin of T1ClkPin must be a
' digital input (ANSELx = 0, TRISx = 1). In counter mode a falling edge must be seen before the
' first rising edge counts [20.2.2 note], so the first pulse after a start may be missed.
Public Sub Timer1StartSource(ByVal clk As Byte, ByVal prescale As Byte)
    T1CON = 0
#if Not _has(T1CON.TMR1CS)
    T1CLK = clk And 31
#endif
    T1GCON = 0
    TMR1L = 0
    TMR1H = 0
    Tmr1If = 0
#if _has(T1CON.TMR1CS)
    T1CON = (clk And 3) * 64 + (prescale And 3) * 16 + 1
#else
    T1CON = (prescale And 3) * 16 + 3
#endif
End Sub

' Counts rising edges on the T1CKI pin.
Public Sub Timer1StartCounter(ByVal prescale As Byte)
    Timer1StartSource(T1ClkPin, prescale)
End Sub

' Counts only while the gate source (one of T1Gate*) is at the given level: high with
' activeHigh, low without [Table 20-3]. The gate is set up before
' the timer is switched on, so no count is taken ungated. Timer1GateState reads the live gate. On the PIC16F17126/46 TMR1GIF is
' cleared after the gate writes (erratum 1.7.1, DS80001009E: writing the gate source can set it).
Public Sub Timer1StartGated(ByVal clk As Byte, ByVal prescale As Byte, ByVal source As Byte, ByVal activeHigh As Boolean)
    T1CON = 0
#if _has(T1CON.TMR1CS)
    If activeHigh Then
        T1GCON = 192 + (source And 3)
    Else
        T1GCON = 128 + (source And 3)
    End If
#else
    T1CLK = clk And 31
    T1GATE = source And 31
    If activeHigh Then
        T1GCON = 192
    Else
        T1GCON = 128
    End If
#endif
    TMR1L = 0
    TMR1H = 0
    Tmr1If = 0
#if _has(PIR1.TMR1IF)
    Tmr1GIf = 0
#endif
#if _has(T1CON.TMR1CS)
    T1CON = (clk And 3) * 64 + (prescale And 3) * 16 + 1
#else
    T1CON = (prescale And 3) * 16 + 3
#endif
End Sub

' Measures one gate pulse: the timer counts during the first pulse of the gate source after
' this call, then holds. Timer1PulseDone reports the end of the pulse and Timer1Read is its
' length in clock counts. With fullCycle the gate toggles on every rising edge, so the measured
' time is a whole period of the source instead of its high (or low) time [20.7.3, 20.7.4].
Public Sub Timer1StartPulse(ByVal clk As Byte, ByVal prescale As Byte, ByVal source As Byte, ByVal activeHigh As Boolean, ByVal fullCycle As Boolean)
    T1CON = 0
#if _has(T1CON.TMR1CS)
    If activeHigh Then
        T1GCON = 192 + (source And 3)
    Else
        T1GCON = 128 + (source And 3)
    End If
#else
    T1CLK = clk And 31
    T1GATE = source And 31
    If activeHigh Then
        T1GCON = 192
    Else
        T1GCON = 128
    End If
#endif
    If fullCycle Then
        T1GCON = T1GCON Or 32
    End If
    T1GCON = T1GCON Or 16
    TMR1L = 0
    TMR1H = 0
    Tmr1If = 0
#if _has(PIR1.TMR1IF)
    Tmr1GIf = 0
#endif
#if _has(T1CON.TMR1CS)
    T1CON = (clk And 3) * 64 + (prescale And 3) * 16 + 1
#else
    T1CON = (prescale And 3) * 16 + 3
#endif
    T1GCON = T1GCON Or 8
End Sub

' True once the pulse started by Timer1StartPulse has ended (GGO/DONE cleared by hardware).
Public Function Timer1PulseDone() As Boolean
    Result = False
    If T1GoDone = 0 Then
        Result = True
    End If
End Function

' The current state of the gate [GVAL]; it is not affected by the gate enable.
Public Function Timer1GateState() As Boolean
    Result = False
    If T1GateVal = 1 Then
        Result = True
    End If
End Function

Public Sub Timer1Stop()
    T1CON = 0
End Sub

Public Function Timer1Read() As Word
    Dim lo As Byte
#if _has(T1CON.TMR1CS)
    ' No RD16 buffer: read the high byte before and after the low byte; when it changed the low byte wrapped in between, so read it again.
    Dim hi As Byte
    Dim hi2 As Byte
    hi = TMR1H
    lo = TMR1L
    hi2 = TMR1H
    If hi2 <> hi Then
        lo = TMR1L
    End If
    Result = hi2 * 256 + lo
#else
    lo = TMR1L
    Result = TMR1H * 256 + lo
#endif
End Function

' True once per overflow; clears the flag when it reports it.
Public Function Timer1Expired() As Boolean
    Result = False
    If Tmr1If = 1 Then
        Tmr1If = 0
        Result = True
    End If
End Function

Public Sub Timer1Ack()
    Tmr1If = 0
End Sub

Public Sub Timer1EnableInterrupt()
    Tmr1If = 0
    Tmr1Ie = 1
End Sub

Public Sub Timer1DisableInterrupt()
    Tmr1Ie = 0
End Sub

' Event hook: assign a handler to Timer1OnExpire, start the timer, and call Timer1Service regularly (from the
' main loop, or from your own Interrupt inside Save(0, Timer1Service)). Each overflow acknowledges the flag and
' calls the handler once. An unassigned Timer1OnExpire does nothing.
Public Dim Timer1OnExpire As TTimerEvent
Public Sub Timer1Service()
    If Timer1Expired() Then
        Timer1OnExpire()
    End If
End Sub

' Timer2: 8-bit, FOSC/4 clock [Table 21-1, T2CLKCON CS = 00001], free-running period mode
' [T2HLT MODE = 00000, Table 21-3], T2CON = ON | CKPS[6:4] | OUTPS[3:0] [21.9.3]. T2TMR counts
' 0..period and restarts; the flag is set on every (postscale + 1)th match, so it is set every
' (period + 1) * 2^prescale * (postscale + 1) instruction cycles (prescale 0..7 selects 1:1 to
' 1:128, postscale 0..15 selects 1:1 to 1:16). T2TMR is not cleared by a T2CON write [21.1].
Public Sub Timer2Start(ByVal prescale As Byte, ByVal postscale As Byte, ByVal period As Byte)
    T2CON = 0
#if _has(T1CON.TMR1CS)
    PR2 = period
    TMR2 = 0
    Tmr2If = 0
    T2CON = 4 + (prescale And 3) + (postscale And 15) * 8
#else
    T2CLKCON = 1
    T2HLT = 0
    T2RST = 0
    T2PR = period
    T2TMR = 0
    Tmr2If = 0
    T2CON = 128 + (prescale And 7) * 16 + (postscale And 15)
#endif
End Sub

' Timer2 with a hardware-limit mode: mode is one of T2Mode*, source one of T2Rst* [T2HLT, T2RST]
' (prescale, postscale and period as for Timer2Start). The clock stays FOSC/4 and the control
' bits PSYNC, CPOL and CSYNC stay 0. Writing ON arms the timer: in the edge and level modes it
' then waits for the reset source, and in the one-shot modes it runs once and clears ON, which
' Timer2Running reports. Use Timer2Running, not the flag, to see a one-shot end: the data sheet
' does not say that TMR2IF is set when ON clears, and with a postscaler it would need
' postscale + 1 period matches. Edge-triggered modes need six timer clocks between triggers,
' level modes a level of at least three [21.5]. The T2RstPin input must be a digital input (ANSELx = 0,
' TRISx = 1).
#if Not _has(T1CON.TMR1CS)
Public Sub Timer2StartLimit(ByVal prescale As Byte, ByVal postscale As Byte, ByVal period As Byte, ByVal mode As Byte, ByVal source As Byte)
    T2CON = 0
    T2CLKCON = 1
    T2HLT = mode And 31
    T2RST = source And 31
    T2PR = period
    T2TMR = 0
    Tmr2If = 0
    T2CON = 128 + (prescale And 7) * 16 + (postscale And 15)
End Sub
#endif

' True while the timer is on; a one-shot timer clears ON after its period [Table 21-3 note 2].
Public Function Timer2Running() As Boolean
    Result = False
    If Tmr2On = 1 Then
        Result = True
    End If
End Function

' Turning the timer off also resets its counters [21.9.3].
Public Sub Timer2Stop()
    T2CON = 0
End Sub

Public Function Timer2Read() As Byte
#if _has(T1CON.TMR1CS)
    Result = TMR2
#else
    Result = T2TMR
#endif
End Function

' True once per period; clears the flag when it reports it.
Public Function Timer2Expired() As Boolean
    Result = False
    If Tmr2If = 1 Then
        Tmr2If = 0
        Result = True
    End If
End Function

Public Sub Timer2Ack()
    Tmr2If = 0
End Sub

Public Sub Timer2EnableInterrupt()
    Tmr2If = 0
    Tmr2Ie = 1
End Sub

Public Sub Timer2DisableInterrupt()
    Tmr2Ie = 0
End Sub

' Event hook: assign a handler to Timer2OnExpire, start the timer, and call Timer2Service regularly (from the
' main loop, or from your own Interrupt inside Save(0, Timer2Service)). Each overflow acknowledges the flag and
' calls the handler once. An unassigned Timer2OnExpire does nothing.
Public Dim Timer2OnExpire As TTimerEvent
Public Sub Timer2Service()
    If Timer2Expired() Then
        Timer2OnExpire()
    End If
End Sub
