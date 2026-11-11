' expect: LR_BADPIN=0 LR_BADDUP=0 LR_GOOD=1 LR_REFUSED=0 LR_LAT=48 LR_LATOFF=0
' Every pin position refuses a pin above 23, every pair of positions refuses a shared pin, and a refused LcdInit
' leaves the module disabled (the routines do nothing) instead of driving the pins of the earlier setup.
Program Lr
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "lcd"
Dim badpin As Byte
Dim baddup As Byte
Dim good As Byte
Dim refused As Byte
Dim lat As Byte
Dim latoff As Byte
badpin = Lcd.LcdInit(24, 17, 18, 19, 20, 21, 2)
badpin = badpin Or Lcd.LcdInit(16, 24, 18, 19, 20, 21, 2)
badpin = badpin Or Lcd.LcdInit(16, 17, 24, 19, 20, 21, 2)
badpin = badpin Or Lcd.LcdInit(16, 17, 18, 24, 20, 21, 2)
badpin = badpin Or Lcd.LcdInit(16, 17, 18, 19, 24, 21, 2)
badpin = badpin Or Lcd.LcdInit(16, 17, 18, 19, 20, 255, 2)
' The last pin equals each of the others, and two neighbours share a pin.
baddup = Lcd.LcdInit(21, 17, 18, 19, 20, 21, 2)
baddup = baddup Or Lcd.LcdInit(16, 21, 18, 19, 20, 21, 2)
baddup = baddup Or Lcd.LcdInit(16, 17, 21, 19, 20, 21, 2)
baddup = baddup Or Lcd.LcdInit(16, 17, 18, 21, 20, 21, 2)
baddup = baddup Or Lcd.LcdInit(16, 17, 18, 19, 21, 21, 2)
baddup = baddup Or Lcd.LcdInit(16, 17, 17, 19, 20, 21, 2)
baddup = baddup Or Lcd.LcdInit(16, 17, 18, 19, 19, 20, 2)
TRISC = 255
ANSELC = 255
LATC = 0
' A good setup, then a refused one: the old pins must not be driven afterwards.
good = Lcd.LcdInit(16, 17, 18, 19, 20, 21, 2)
lat = LATC And 63
refused = Lcd.LcdInit(16, 17, 18, 19, 20, 20, 2)
LATC = 0
Lcd.LcdWrite("X")
Lcd.LcdClear()
latoff = LATC
