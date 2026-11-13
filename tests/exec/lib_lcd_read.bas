' expect: LR_NONE=0 LR_BAD1=0 LR_BAD2=0 LR_OK=1 LR_ST=85 LR_RD=85 LR_TRIS=0 LR_RW=0
' stim: lib_lcd_read.stim.toml
' LcdRwInit, LcdStatus, LcdRead with R/W on RC6 and the display's bus (DB4..DB7 = RC2..RC5) held at 0101 by the stimulus:
' both nibbles read 5, so the byte is 55H (85) and the busy flag (bit 7) is clear. Before LcdRwInit the reads give 0, and a
' pin that is one of the six, or above 23, is refused. After a read the bus pins are outputs again and R/W is low.
Program Lr
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "lcd"
Dim none As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim ok As Byte
Dim st As Byte
Dim rd As Byte
Dim tris As Byte
Dim rw As Byte
TRISC = 255
ANSELC = 255
bad1 = Lcd.LcdRwInit(22)
ok = Lcd.LcdInit(16, 17, 18, 19, 20, 21, 2)
none = Lcd.LcdStatus()
bad2 = Lcd.LcdRwInit(18) + Lcd.LcdRwInit(24)
ok = Lcd.LcdRwInit(22)
Lcd.LcdGoto(0, 0)
st = Lcd.LcdStatus()
rd = Lcd.LcdRead()
tris = TRISC And 124
rw = LATC And 64
