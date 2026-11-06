' expect: LA_CLK=15 LA_ACQ=160 LA_CON=132 LA_REF=0 LA_CP=64 LA_CLK2=15 LA_ACQ2=160 LA_REF2=3 LA_TA=2 LA_NA=2 LA_MV=3300 LA_FV=3 LA_RD=0 LA_VSS=58 LA_FVRC=62 LA_TB=16 LA_NB=16
' ADC library on the PIC16F18056 at 32 MHz (DS40002325C chapter 31): ADCLK = n with 2 * (n + 1) / FOSC >= 1 us (AD20 p.529) gives n = 15, ADACQ covers 5 us (160 clocks of FOSC),
' ADCON0 = ON | FM (132), RC1 (channel 17) and RB4 (channel 12) become analog inputs, the 10-bit scale gives 3300 mV for 1023 (AD01), FVR as reference sets ADREF = 3. Erratum 1.1.1 (DS80001014D): AdcInit
' writes CPON = 01 to CPCON (64). VSS is channel 58 and the FVR buffer 1 channel 62 [Table 31-6 p.428]. The simulator does not run the ADC (ADGO never clears), so no conversion is made.
Program La
Device = 16F18056
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
Dim tb As Byte
Dim nb As Byte
Dim rd As Word
Dim mv As Word
Dim fv As Byte
Dim cp As Byte
Dim vss As Byte
Dim fvrc As Byte
Adc.AdcInit()
clk = ADCLK
acq = Byte(ADACQ)
con = ADCON0
cp = CPCON And 192
ref = ADREF
TRISC = 0
ANSELC = 0
TRISB = 0
ANSELB = 0
Adc.AdcPin(17)
Adc.AdcPin(12)
ta = TRISC
na = ANSELC
tb = TRISB
nb = ANSELB
mv = Adc.AdcMillivolts(1023, 3300)
Adc.AdcRefFvr(4)
clk2 = ADCLK
acq2 = Byte(ADACQ)
ref2 = ADREF
fv = FVRCON And 3
rd = Adc.AdcReadAvg(17, 0)
vss = Adc.AdcChVss
fvrc = Adc.AdcChFvr
