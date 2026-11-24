' dsPIC33CK64MC105 LED blink: first BASIC program.
' Connect: RB5 -> 330 ohm series resistor -> LED anode; LED cathode -> VSS.
Program Blink
Device = dsPIC33CK64MC105
Clock = 8

Dim led As LATB.5

ANSELB = 0
Output(led)
While True
    Toggle(led)
    DelayMS(500)
Wend
