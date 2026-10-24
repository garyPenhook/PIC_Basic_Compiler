Program T
Device = 18F27Q10
Dim t As Byte
Dim x As Bit
t = TRISB
LATB = 0
PORTB.0 = 1
x = PORTB.RB3
FSR0 = 100
t = FSR0L
t = FSR0.Byte1
Low(PORTB.4)
