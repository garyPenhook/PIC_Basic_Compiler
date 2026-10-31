' Oled on the PIC16F13145 without the frame buffer (1 KB, as much RAM as the part has): the module builds when no pixel command is used.
' expect: LT_S0=0 LT_BAD1=0 LT_BAD2=0 LT_BAD3=0 LT_OK=1 LT_TRIS=0 LT_LAT=6
Program Lt
Device = 16F13145
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "oled"
Dim s0 As Byte
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim ok As Byte
Dim tris As Byte
Dim lat As Byte

TRISC = 255
ANSELC = 255
Oled.OledData(1)
s0 = Oled.OledStatus()
bad1 = Oled.OledInitSpi(24, 255, 255)
bad2 = Oled.OledInitSpi(16, 16, 255)
bad3 = Oled.OledInitSpi(16, 17, 16)
ok = Oled.OledInitSpi(16, 17, 18)
tris = TRISC And 7
lat = LATC And 7
Oled.OledTextGoto(2, 3)
Oled.OledWrite("Hi")
Oled.OledWriteWord(1234)
