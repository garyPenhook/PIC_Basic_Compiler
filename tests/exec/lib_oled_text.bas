' expect: LT_WRAP=0 LT_A=1 LT_FAR=1 LT_CLIP=0 LT_Y=0
Program Lt
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "oled"
Dim wrap As Byte
Dim a As Byte
Dim far As Byte
Dim clip As Byte
Dim y As Byte
Dim i As Byte

' A string longer than the 128 pixel line (a space, then 45 'H'): the characters past column 127 are
' dropped. The character that would start at 258 used to wrap the Byte x to column 2 and draw there.
Oled.OledBufClear()
Oled.OledBufText(0, 0, True, " HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH")
wrap = Oled.OledPoint(2, 1) + Oled.OledPoint(3, 1)
a = Oled.OledPoint(6, 1)
far = Oled.OledPoint(127, 3)
' A character whose x is off screen draws nothing (also x = 250, whose columns would wrap past 255).
Oled.OledBufClear()
Oled.OledBufChar(250, 0, 72, True)
Oled.OledBufChar(128, 0, 72, True)
clip = 0
i = 0
While i < 128
    clip = clip + Oled.OledPoint(i, 1) + Oled.OledPoint(i, 2)
    Inc(i)
Wend
' y off screen (y = 250: the rows would wrap to 0..): nothing drawn.
Oled.OledBufChar(0, 250, 72, True)
y = Oled.OledPoint(0, 1) + Oled.OledPoint(1, 2)
End
