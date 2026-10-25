' expect: LL_BAD1=0 LL_BAD2=0 LL_BAD3=0 LL_BAD4=0 LL_OK=1 LL_TRIS=0 LL_ANS=0 LL_LAT=48 LL_OK1=1
Program Ll
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "lcd"
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim bad4 As Byte
Dim ok As Byte
Dim tris As Byte
Dim ans As Byte
Dim lat As Byte
Dim ok1 As Byte
TRISC = 255
ANSELC = 255
' Refused: no lines, three lines, a pin above 23, a pin used twice.
bad1 = Lcd.LcdInit(16, 17, 18, 19, 20, 21, 0)
bad2 = Lcd.LcdInit(16, 17, 18, 19, 20, 21, 3)
bad3 = Lcd.LcdInit(16, 17, 18, 19, 20, 24, 2)
bad4 = Lcd.LcdInit(16, 17, 18, 19, 20, 16, 2)
' RS = RC0, E = RC1, DB4..DB7 = RC2..RC5: six outputs, digital. The last nibble written is 12
' (the display-on instruction 0CH, low nibble), so DB6 and DB7 are high.
ok = Lcd.LcdInit(16, 17, 18, 19, 20, 21, 2)
tris = TRISC And 63
ans = ANSELC And 63
lat = LATC And 63
Lcd.LcdWrite("Hi")
Lcd.LcdGoto(3, 1)
Lcd.LcdWriteWord(65535)
Lcd.LcdWriteHex(171)
Lcd.LcdCustomRow(1, 0, 31)
Lcd.LcdShift(True, False)
Lcd.LcdDisplay(True, True, True)
Lcd.LcdClear()
ok1 = Lcd.LcdInit(8, 9, 10, 11, 12, 13, 1)
