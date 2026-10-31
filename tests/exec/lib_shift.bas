' expect: LS_TRIS1=3 LS_BADIN=0 LS_TRIS=0 LS_ANS=0 LS_LAT=0 LS_IN8=0 LS_IN16=0 LS_TRIS2=1
Program Ls
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "shift"
Dim tris1 As Byte
Dim badin As Byte
Dim tris As Byte
Dim ans As Byte
Dim lat As Byte
Dim in8 As Byte
Dim in16 As Word
Dim tris2 As Byte
TRISC = 255
ANSELC = 255
LATC = 0
' Refused (pin above 23, same pin twice, zero bits): nothing is sent, the port keeps its state.
Shift.ShiftOut(255, 24, 17, False, 8)
Shift.ShiftOut(255, 16, 16, False, 8)
Shift.ShiftOut(255, 16, 17, False, 0)
tris1 = TRISC And 3
badin = Shift.ShiftIn(30, 17, False, 8)
' RC0 = data, RC1 = clock, both outputs; 0 sent, so both low.
Shift.ShiftOut(0, 16, 17, False, 8)
tris = TRISC And 3
ans = ANSELC And 3
lat = LATC And 3
' ShiftIn makes the data pin an input (the pin is floating in the simulator; only the set-up is checked).
in8 = Shift.ShiftIn(16, 17, False, 8) And 0
tris2 = TRISC And 3
in16 = Shift.ShiftIn16(16, 17, True, 16) And 0
