

Program Blink
Device = 18F27Q10
Clock = 1

' PIC18F27Q10 configuration
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_1MHZ, CSWEN = ON, PPS1WAY = OFF, WDTE = OFF

' FEXTOSC = OFF: Oscillator not enabled
' RSTOSC = HFINTOSC_1MHZ: HFINTOSC with HFFRQ = 4 MHz and CDIV = 4:1
' PPS1WAY = OFF: PPSLOCK bit can be set and cleared repeatedly (subject to the unlock sequence)
' WDTE = OFF: WDT Disabled


Include "intosc"          ' sets the oscillator to Clock (4 MHz)
Include "gpio"
Include "serial"

Dim led As PORTB.0
Dim ticks As Word = 0

Interrupt Tick()
    PIR0.5 = 0
    Inc(ticks)
End Interrupt

Gpio.GpioAllDigital()
Output(led)
Serial.SerialInit(115200)
T0CON1 = 65
PIE0.5 = 1
Enable(Tick)
T0CON0 = 128
Do 

    Toggle(led)
    Serial.SerialWrite("tick")
    Serial.SerialNewLine()
    DelayMs(500)
Loop