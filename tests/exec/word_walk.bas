' expect: WALK_SINK=8679
Program Walk
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim data(256) As Word
Dim i As Byte
Volatile Dim idx As Byte
Volatile Dim sink As LongWord
idx = 127
data(idx) = 1000
idx = 128
data(idx) = 2000
idx = 255
data(idx) = 3000
sink = data(127) + LongWord(data(128)) + data(255)
For i = 126 To 129
    data(i) = Word(i) * 3
Next
For i = 126 To 129
    If i = 127 Then
        Continue
    End If
    sink = sink + data(i)
Next
For i = 129 To 126 Step -1
    sink = sink + data(i)
Next
