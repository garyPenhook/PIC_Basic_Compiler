' expect: LI_CON=132 LI_CH=13 LI_TA=32 LI_NA=32 LI_UP=1 LI_CH2=63 LI_OK=1
Program Li
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "adc"
Dim con As Byte
Dim ch As Byte
Dim ch2 As Byte
Dim ta As Byte
Dim na As Byte
Dim up As Byte
Dim ok As Byte
Dim rd As Word
TRISB = 0
ANSELB = 0
rd = Adc.ADin(13)
con = ADCON0
ch = ADPCH
ta = TRISB
na = ANSELB
up = 1
rd = Adc.ADin(Adc.AdcChFvr)
ch2 = ADPCH
ok = 1
