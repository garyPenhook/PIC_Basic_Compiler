' expect: REFS_S=45 REFS_X=11 REFS_Y=7 REFS_Z=33 REFS_W=1500 REFS_T=2 REFS_S=3
Program Refs
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim b(10) As Byte
Dim v(3) As Word
Dim i As Byte
Dim s As Byte
Dim x As Byte
Dim y As Byte
Dim z As Byte
Dim w As Word
Dim t As Byte
Sub Fill(a() As Byte, ByVal n As Byte)
    Dim k As Byte
    For k = 0 To n - 1
        a(k) = k
    Next
End Sub
Function Total(a() As Byte, ByVal n As Byte) As Byte
    Dim k As Byte
    Dim r As Byte
    r = 0
    For k = 0 To n - 1
        r = r + a(k)
    Next
    Result = r
End Function
Sub Swap(ByRef p As Byte, ByRef q As Byte)
    Dim tmp As Byte
    tmp = p
    p = q
    q = tmp
End Sub
Sub Add3(ByRef p As Byte)
    p = p + 3
    Inc(p)
End Sub
Sub Wd(a() As Word)
    a(1) = 1500
End Sub
Function Via(a() As Byte, ByVal n As Byte) As Byte
    Result = Total(a, n)
End Function
Fill(b, 10)
s = Total(b, 10)
x = 7
y = 11
Swap(x, y)
z = 29
Add3(z)
Wd(v)
w = v(1)
t = Via(b, 4) + 3
b(0) = 5
t = 2
b(0) = b(t) + 1
s = b(0)
