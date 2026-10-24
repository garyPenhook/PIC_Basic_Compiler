' expect: LA_CLK=31 LA_ACQ=5 LA_CON=132 LA_REF=0 LA_CLK2=63 LA_ACQ2=3 LA_REF2=3 LA_TA=32 LA_NA=32 LA_CH=13 LA_RD=0 LA_MV=3300 LA_FV=3 LA_RD=0 LA_OK=1
Program La
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
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
Adc.AdcInit()
clk = ADCLK
acq = ADACQ
con = ADCON0
ref = ADREF
TRISB = 0
ANSELB = 0
Adc.AdcPin(13)
ta = TRISB
na = ANSELB
rd = Adc.AdcRead(13)
ch = ADPCH
mv = Adc.AdcMillivolts(1023, 3300)
Adc.AdcRefFvr(4)
clk2 = ADCLK
acq2 = ADACQ
ref2 = ADREF
ok = 1
fv = FVRCON And 3
rd = Adc.AdcReadAvg(13, 0)
