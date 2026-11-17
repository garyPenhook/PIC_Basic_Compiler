' PIC16F18346 LED blink: first BASIC program.
' Connect: RC0 -> 330 ohm series resistor -> LED anode; LED cathode -> VSS.
'          Use the device datasheet for supply, decoupling and ICSP connections.
' Expect: LED alternates on/off every 500 ms (one complete cycle per second).
' Status: assembled and checked in basil-sim; not yet tested on a real chip.
' Tutorial: docs/PIC16-BASIC-TUTORIAL.md
Program Blink
Device = 16F18346
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON

Dim led As PORTC.0

ANSELC = 0
LATC = 0
Output(led)
While True
    Toggle(led)
    DelayMS(500)
Wend
