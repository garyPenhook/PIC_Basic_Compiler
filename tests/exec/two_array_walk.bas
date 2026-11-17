' expect: PAIR_SINK=500770
Program Pair
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a(130) As Integer
Dim b(130) As Byte
Dim c(2) As Byte
Dim d(2) As LongInt
Dim i As Byte
Volatile Dim sink As LongInt
a(126) = -2
a(127) = -1
a(128) = 0
a(129) = 1
b(126) = 127
b(127) = 128
b(128) = 129
b(129) = 130
sink = 0
' Walk across linear RAM banks and the 127/128 index boundary.
For i = 126 To 129
    sink = sink + a(i) * b(i)
Next
' The body also reads the induction variable.
For i = 126 To 129
    sink = sink + a(i) + b(i) + i
Next
' Zero iterations must leave the result unchanged.
For i = 129 To 126
    sink = sink + a(i) * b(i)
Next

' Different strides and signed widening must preserve both pointers.
c(0) = 3
c(1) = 4
d(0) = -100000
d(1) = 200000
For i = 0 To 1
    sink = sink + d(i) * c(i)
Next
