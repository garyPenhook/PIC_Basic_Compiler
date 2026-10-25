' expect: LO_S0=0 LO_B1=0 LO_NOBUS=0 LO_NOBUSST=4 LO_BAD1=0 LO_BAD2=0 LO_BAD3=0 LO_OK=1 LO_TRIS=0 LO_LAT=6 LO_F0=124 LO_F1=18 LO_FLAST=0 LO_F94=4
Program Lo
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "oled"
Dim s0 As Byte
Dim b1 As Byte
Dim nobus As Byte
Dim nobusst As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim ok As Byte
Dim tris As Byte
Dim lat As Byte
Dim f0 As Byte
Dim f1 As Byte
Dim flast As Byte
Dim f94 As Byte

TRISC = 255
ANSELC = 255
' Nothing initialised: the routines return and the status is 0.
Oled.OledData(1)
s0 = Oled.OledStatus()
' Bad I2C address.
b1 = Oled.OledInitI2c(200, 255)
' I2C module not set up: every transfer reports status 4 (not initialised); the init returns 0.
nobus = Oled.OledInitI2c(60, 255)
nobusst = Oled.OledStatus()
' SPI refused: D/C# above 23, CS# = D/C#, RES# = D/C#.
bad1 = Oled.OledInitSpi(24, 255, 255)
bad2 = Oled.OledInitSpi(16, 16, 255)
bad3 = Oled.OledInitSpi(16, 17, 16)
' D/C# = RC0, CS# = RC1, RES# = RC2: outputs; at the end CS# and RES# are high and D/C# low (the last
' transfer was a command).
ok = Oled.OledInitSpi(16, 17, 18)
tris = TRISC And 7
lat = LATC And 7
Oled.OledTextGoto(2, 3)
Oled.OledWrite("Hi")
Oled.OledWriteWord(1234)
Oled.OledWriteHex(171)
Oled.OledContrast(200)
Oled.OledInvert(True)
Oled.OledAllOn(False)
Oled.OledFlip(True)
Oled.OledOn(False)
Oled.OledClear()
' Font table: 'A' (code 65) is 124, 18, 18, 124, 0; the last entry (code 126) is 4, 2, 4, 2, 0.
f0 = Oled.FontByte(165)
f1 = Oled.FontByte(166)
flast = Oled.FontByte(474)
f94 = Oled.FontByte(470)
