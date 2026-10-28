' expect: T_X=170 T_Y=1 T_Z=0
' devices: 18F27Q10
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim led As PORTB.0
Dim btn As PORTA.1
Dim x As Byte
Dim y, z As Bit
Output(led)
Output(PORTC)
High(led)
LATC = 170
x = LATC
y = LATB.0
Toggle(led)
z = LATB.0
Toggle(led)
y = LATB.0
Low(led)
Input(btn)
