' expect: DC_DC_A=96 DC_DC_B=3
' Declare Name = value (other than Xtal) is a Const; `#if` sees it too.
Program Dc
Device = 18F27Q10
Declare Xtal = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Declare Hserial_Baud = 9600
Declare Lcd_Lines = 2 + 1
Dim dc_a As Byte
Dim dc_b As Byte
dc_a = Hserial_Baud / 100
dc_b = Lcd_Lines
#if Hserial_Baud = 9600
#else
#error "Declare value not seen"
#endif
