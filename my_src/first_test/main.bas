

Program Blink

Device = 18F27Q10
Clock = 16

Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON

Include "intosc"          ' sets the oscillator to Clock (16 MHz)
Include "gpio"

Dim test As Float
Dim led As PORTB.0
GpioAllDigital()
Output(led)


While True
    Toggle(led)
    DelayMs(500)




Wend