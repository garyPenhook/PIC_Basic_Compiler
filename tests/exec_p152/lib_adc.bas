' expect: LA_CON=1 LA_CS=208 LA_CP=64 LA_CS2=211 LA_FV=130 LA_TA=4 LA_NA=4 LA_CS3=208 LA_MV=3300 LA_RD=0 LA_VSS=27 LA_FVRC=30
' ADC library on the PIC16F152xx at 32 MHz (PIC16F15244; DS40002195E chapter 27). ADCON1 = FM (128) | CS << 4 where FOSC/16 (CS = 101, TAD = 0.5 us, the smallest choice of at least 0.5 us, AD20) gives 208.
' ADCON0 = ON (1) with channel 0. CPCON = 64 (CPON = 01, reset value 00; CPT and CPRDY are read only and masked). RC2 (channel 18) becomes an analog input (TRISC and ANSELC bit 2 = 4). The 10-bit scale gives
' 3300 mV for 1023. AdcRefFvr(2) sets PREF = 11 (ADCON1 = 211) and FVRCON = FVREN | ADFVR 2x (130, FVRRDY masked); AdcRefVdd clears PREF again (208). VSS is channel 27 and the FVR buffer 30 [Register 27-1 p.328].
' The simulator does not run the ADC (GO never clears), so no conversion is made.
Program La
Device = 16F15244
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHZ, WDTE = OFF, LVP = ON
Include "adc"
Dim con As Byte
Dim cs As Byte
Dim cp As Byte
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
cp = CPCON And 192
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
