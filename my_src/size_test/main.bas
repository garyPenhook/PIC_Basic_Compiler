Program SizeTest
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Include "serial"

Dim led As PORTB.0
Dim count As Word
Dim avg As Word

ANSELB = 0
Output(led)
Serial.SerialInit(115200)

While True
    Toggle(led)
    count = count + 1
    avg = count / 10
    Serial.SerialWrite("tick")
    Serial.SerialNewLine()
    DelayMS(500)
Wend
