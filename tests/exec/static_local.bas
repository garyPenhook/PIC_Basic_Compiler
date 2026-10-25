' expect: SL_A=3 SL_B=13 SL_C=3 SL_D=1 SL_E=4 SL_F=6 SL_G=4 SL_H=5
' Static locals keep their value between calls, are initialised once and are not cleared on entry.
Program SL
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a As Byte
Dim b As Byte
Dim c As Byte
Dim d As Byte
Dim e As Byte
' never read: only Volatile keeps the stores
Volatile Dim f As Byte
Volatile Dim g As Byte
Volatile Dim h As Byte
Sub Tick()
    Static Dim n As Byte
    Static Dim m As Byte = 10
    Dim plain As Byte
    Static Dim t(3) As Byte = (1, 2, 3)
    Inc(n)
    Inc(m)
    Inc(plain)
    t(0) = t(0) + 1
    a = n
    b = m
    d = plain
    e = t(0)
End Sub
Sub Other()
    Dim x As Byte
    x = 5
    h = x
End Sub
Function Counter() As Byte
    Static Dim k As Word
    k = k + 2
    Result = Byte(k)
End Function
Tick()
Tick()
Tick()
Other()
c = a
f = Counter()
f = Counter()
f = Counter()
g = Counter() - 4
