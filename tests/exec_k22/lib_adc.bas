' expect: LA_A0=512 LA_B0=1000 LA_NONE=0 LA_FVR=333 LA_C2=166 LA_C2F=182 LA_C1F=8 LA_REF=1 LA_MV=1651
' stim: lib_adc.stim.toml
' ADC library on the PIC18(L)F2x/4xK22 (DS40001412H chapter 17): channels are pin numbers, translated to AN numbers (RA0 = AN0,
' RB0 = pin 8 = AN12, RA4 has no analog input and reads 0), AdcChFvr is CHS 31. At 64 MHz ADCON2 = ADFM | ACQT 100 (8 TAD) | ADCS 110
' (FOSC/64, TAD = 1 us) = 166, and 182 (ACQT 110, 16 TAD) on the FVR channel; AdcRefFvr selects PVCFG = 10 (ADCON1 = 8) and waits
' for FVRST. AdcMillivolts(512, 3300) = 512 * 3300 / 1023 = 1651.
Program La
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "adc"
Dim a0 As Word
Dim b0 As Word
Dim none As Word
Dim fvr As Word
Dim c2 As Byte
Dim c2f As Byte
Dim c1f As Byte
Dim ref As Byte
Dim mv As Word
Adc.AdcInit()
Adc.AdcPin(0)
Adc.AdcPin(8)
a0 = Adc.AdcRead(0)
c2 = ADCON2
b0 = Adc.ADin(8)
none = Adc.AdcRead(4)
Adc.AdcRefFvr(2)
c1f = ADCON1
If VREFCON0.FVRST = 1 Then
    ref = 1
End If
fvr = Adc.AdcRead(Adc.AdcChFvr)
c2f = ADCON2
Adc.AdcRefVdd()
mv = Adc.AdcMillivolts(a0, 3300)
