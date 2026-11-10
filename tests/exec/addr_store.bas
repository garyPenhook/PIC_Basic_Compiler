' `w = @x` and ByRef arguments store the address bytes straight into the destination (no detour through __A).
' The routines below change the variables through their addresses; AD_BAD counts wrong results.
' expect: AD_BAD=0 AD_X=6 AD_DONE=1
Program Ad
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim x As Byte
Dim a(4) As Byte
Dim w As Word
Dim p0 As Word
Dim p3 As Word
Dim q1 As Word
Dim q2 As Word
Dim bad As Byte
Dim done As Byte
Sub Bump(ByRef v As Byte, ByVal by As Byte)
    v = v + by
End Sub
Sub Two(ByRef u As Byte, ByRef v As Byte)
    u = u + 1
    v = v + 2
End Sub
x = PORTA
x = 5 + (x And 0)
a(2) = 8
Bump(x, 1)
Bump(a(2), 1)
Two(a(0), a(3))
If a(0) <> 1 Then
    bad = bad + 1
End If
If a(3) <> 2 Then
    bad = bad + 1
End If
If a(2) <> 9 Then
    bad = bad + 1
End If
p0 = @a(0)
p3 = @a(3)
If p3 - p0 <> 3 Then
    bad = bad + 1
End If
w = @x
If w = p0 Then
    bad = bad + 1
End If
w = @w
q2 = @w
If w <> q2 Then
    bad = bad + 1
End If
q1 = @PORTA
q2 = @PORTA
If q1 <> q2 Then
    bad = bad + 1
End If
w = @x
If q1 = w Then
    bad = bad + 1
End If
done = 1
