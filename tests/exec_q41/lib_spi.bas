' expect: LP_OK=1 LP_BAUD=15 LP_CON0=131 LP_CON1=68 LP_CON2=3 LP_TW=0 LP_PPS=27 LP_SDO=28 LP_SCKI=18 LP_SDII=17 LP_BAD1=0 LP_BAD2=0 LP_BAD3=0
' SPI library on the PIC18F16Q41: SpiInit(2000000, 0, ...) at 64 MHz gives SPI1BAUD = 64/(2*2)/1 - 1 = 15 (2 MHz),
' mode 0 = CKP 0, CKE 1 (bit 6), SSP left at 1 (bit 2): SPI1CON1 = 68; SPI1CON0 = EN | MST | BMODE = 131. SCK on RC2
' (pin 18, RC2PPS = 27), SDO on RC3 (pin 19, RC3PPS = 28), SDI on RC1 (pin 17).
Program Lp
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "spi"
Dim ok As Byte
Dim baud As Byte
Dim con0 As Byte
Dim con1 As Byte
Dim con2 As Byte
Dim tw As Byte
Dim pps As Byte
Dim sdo As Byte
Dim scki As Byte
Dim sdii As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
ok = Spi.SpiInit(2000000, 0, 18, 19, 17)
baud = SPI1BAUD
con0 = SPI1CON0
con1 = SPI1CON1
con2 = SPI1CON2
tw = SPI1TWIDTH
pps = RC2PPS
sdo = RC3PPS
scki = SPI1SCKPPS
sdii = SPI1SDIPPS
bad1 = Spi.SpiInit(2000000, 4, 18, 19, 17)
bad2 = Spi.SpiInit(2000000, 0, 18, 18, 17)
bad3 = Spi.SpiInit(20000000, 0, 18, 19, 17)
