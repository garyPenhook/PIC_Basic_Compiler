' expect: LO_S0=0 LO_B1=0 LO_NOBUS=0 LO_NOBUSST=4 LO_BAD1=0 LO_BAD2=0 LO_BAD3=0 LO_OK=1 LO_TRIS=0 LO_LAT=6 LO_F0=124 LO_F1=18 LO_FLAST=0 LO_F94=4 LO_P1=1 LO_P2=0 LO_P3=1 LO_OUTP=0 LO_LN=1 LO_LMID=1 LO_RECT=1 LO_RIN=0 LO_FILL=1 LO_BUF0=1 LO_BUF1=129 LO_BBM=1 LO_TXT=1
Program Lo
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "oled"
Const Logo(3) As Byte = (1, 129, 255)
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
Dim p1 As Byte
Dim p2 As Byte
Dim p3 As Byte
Dim outp As Byte
Dim ln As Byte
Dim lmid As Byte
Dim rect As Byte
Dim rin As Byte
Dim fill As Byte
Dim buf0 As Byte
Dim buf1 As Byte
Dim bbm As Byte
Dim txt As Byte

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
' Pixel drawing in the frame buffer (no display needed to check the buffer itself).
Oled.OledBufClear()
Oled.OledPixel(0, 0, True)
Oled.OledPixel(127, 63, True)
Oled.OledPixel(5, 9, True)
Oled.OledPixel(200, 9, True)
p1 = Oled.OledPoint(5, 9)
p2 = Oled.OledPoint(5, 8)
p3 = Oled.OledPoint(127, 63)
outp = Oled.OledPoint(200, 9)
Oled.OledPixel(5, 9, False)
p2 = p2 + Oled.OledPoint(5, 9)
' Line: both ends and the middle of a diagonal; clipped line must not crash.
Oled.OledLine(10, 10, 30, 30, True)
ln = Oled.OledPoint(10, 10) And Oled.OledPoint(30, 30)
lmid = Oled.OledPoint(20, 20)
Oled.OledLine(-5, -5, 300, 70, True)
' Rectangle outline: corners set, inside clear.
Oled.OledRect(40, 40, 10, 8, True)
rect = Oled.OledPoint(40, 40) And Oled.OledPoint(49, 47)
rin = Oled.OledPoint(45, 44)
Oled.OledFillRect(60, 40, 6, 6, True)
fill = Oled.OledPoint(62, 42) And Oled.OledPoint(65, 45)
' Bitmap into the buffer: Logo is 3 columns, one page; column 1 has bits 0 and 7.
Oled.OledBufClear()
Oled.OledBufBitmap(20, 16, 3, 1, False, Logo)
buf0 = Oled.OledPoint(20, 16)
buf1 = Oled.OledPoint(21, 23) + 128 * Oled.OledPoint(21, 16)
bbm = Oled.OledPoint(22, 20)
Oled.OledBufText(0, 0, True, "A")
txt = Oled.OledPoint(0, 2)
Oled.OledBitmap(0, 1, 3, Logo)
Oled.OledUpdate()
