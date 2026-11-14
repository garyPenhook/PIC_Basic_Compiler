' expect: LA_CON=1 LA_CS=160 LA_CS2=227 LA_FV=130 LA_TA=4 LA_NA=4 LA_CS3=160 LA_MV=3300 LA_RD=0 LA_VSS=59 LA_FVRC=62
' ADC library on the PIC16F153xx at 32 MHz (PIC16F15356; DS40001866E chapter 20, 10 bits). ADCON1 = ADFM (128) | ADCS << 4 where FOSC/32 (ADCS = 010, TAD = 1 us, the smallest choice of at least 1 us, AD20) gives 160; ADCON0 = ADON (1)
' with channel 0. RC2 (channel 18) becomes an analog input (TRISC and ANSELC bit 2 = 4). The 10-bit scale gives 3300 mV for 1023. AdcRefFvr(2) sets ADPREF = 11 and FVRCON = FVREN | ADFVR 2x (130, FVRRDY masked); with the FVR as reference
' erratum 1.1 of DS80000725F asks for TAD >= 8 us, which FOSC/64 (2 us at 32 MHz) cannot reach, so the slowest clock is chosen (ADCS = 110: 128 | 96 | 3 = 227). AdcRefVdd clears ADPREF and goes back to FOSC/32 (160). AVSS is channel 59 and the FVR buffer 1 is
' 62 [Register 20-1 p.280 of DS40001866E]. No conversion is made (the test checks the set-up only).
Program La
Device = 16F15356
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "adc"
Dim con As Byte
Dim cs As Byte
Dim cs2 As Byte
Dim cs3 As Byte
Dim fv As Byte
Dim ta As Byte
Dim na As Byte
Dim mv As Word
Dim rd As Word
Dim vss As Byte
Dim fvrc As Byte
Adc.AdcInit()
con = ADCON0
cs = ADCON1
TRISC = 0
ANSELC = 0
Adc.AdcPin(18)
ta = TRISC
na = ANSELC
mv = Adc.AdcMillivolts(1023, 3300)
Adc.AdcRefFvr(2)
cs2 = ADCON1
fv = FVRCON And 191
Adc.AdcRefVdd()
cs3 = ADCON1
rd = Adc.AdcReadAvg(18, 0)
vss = Adc.AdcChVss
fvrc = Adc.AdcChFvr
