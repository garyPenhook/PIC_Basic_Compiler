' expect: LA_CON=1 LA_CS=160 LA_CS2=163 LA_CS3=160 LA_FV=130 LA_TA=2 LA_NA=2 LA_MV=3300 LA_RD=0
' ADC library on the PIC16F183xx at 32 MHz (PIC16F18326; DS40001839E chapter 22). ADCON1 = ADFM (128) | ADCS << 4 where FOSC/32 (ADCS = 010, TAD = 1.0 us, the smallest
' choice of at least 1 us, AD20) gives 160. ADCON0 = ADON (1) with channel 0. RC1 (channel 17) becomes an analog input (TRISC and ANSELC bit 1 = 2). The 10-bit scale gives
' 3300 mV for 1023. AdcRefFvr(2) sets ADPREF = 11 (ADCON1 = 163) and FVRCON = FVREN | ADFVR 2x (130, FVRRDY masked); AdcRefVdd clears ADPREF again (160).
' The simulator does not run the ADC (GO/DONE never clears), so no conversion is made.
Program La
Device = 16F18326
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
Adc.AdcInit()
con = ADCON0
cs = ADCON1
TRISC = 0
ANSELC = 0
Adc.AdcPin(17)
ta = TRISC
na = ANSELC
mv = Adc.AdcMillivolts(1023, 3300)
Adc.AdcRefFvr(2)
cs2 = ADCON1
fv = FVRCON And 191
Adc.AdcRefVdd()
cs3 = ADCON1
rd = Adc.AdcReadAvg(17, 0)
