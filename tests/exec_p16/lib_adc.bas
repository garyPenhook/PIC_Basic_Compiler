' expect: LA_CLK=15 LA_ACQ=5 LA_CON=132 LA_REF=0 LA_CP=64 LA_CLK2=15 LA_ACQ2=5 LA_REF2=3 LA_TA=2 LA_NA=2 LA_MV=3300 LA_FV=3 LA_RD=0 LA_OK=1
' ADC library on the PIC16F17146 at 32 MHz (DS40002343F chapter 33): ADCLK = n with 2 * (n + 1) / FOSC >= 1 us gives n = 15, ADACQ covers 5 us (5 ADC clocks of 1 us),
' ADCON0 = ADON | ADFM (132), RC1 (pin 17, on the 14-pin part too) becomes an analog input, the 12-bit scale gives 3300 mV for 4095, FVR as reference sets ADREF = 3 and no
' slower clock (the PIC16F171xx has no erratum for it). Errata 1.6.1 (DS80001009E): AdcInit writes CPON = 01 to CPCON (64). The simulator does not run the ADC (ADGO never clears), so no conversion is made.
Program La
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "adc"
Dim clk As Byte
Dim acq As Byte
Dim con As Byte
Dim ref As Byte
Dim clk2 As Byte
Dim acq2 As Byte
Dim ref2 As Byte
Dim ta As Byte
Dim na As Byte
Dim ch As Byte
Dim rd As Word
Dim mv As Word
Dim ok As Byte
Dim fv As Byte
Dim cp As Byte
Adc.AdcInit()
clk = ADCLK
acq = Byte(ADACQ)
con = ADCON0
cp = CPCON And 192
ref = ADREF
TRISC = 0
ANSELC = 0
Adc.AdcPin(17)
ta = TRISC
na = ANSELC
mv = Adc.AdcMillivolts(4095, 3300)
Adc.AdcRefFvr(4)
clk2 = ADCLK
acq2 = Byte(ADACQ)
ref2 = ADREF
ok = 1
fv = FVRCON And 3
rd = Adc.AdcReadAvg(17, 0)
