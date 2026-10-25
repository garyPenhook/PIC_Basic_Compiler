

Program Blink

Device = 18F27Q10
Clock = 16

Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON

Include "intosc"          ' sets the oscillator to Clock (16 MHz)


Dim led As PORTB.0
ANSELB = 0 ' make port B digital
Output(led)

While True
    Toggle(led)
    DelayMs(500)
Wend