' expect: SSR_R1=1 SSR_R2=1 SSR_R3=1 SSR_R4=1
Program Ssr
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim s As String(10) = "hello"
Dim u As String(10)
Dim names(3) As String(8)
Dim ix(3) As Byte = (2, 0, 1)
Dim j As Byte
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Sub Cut(ByRef d As String(10), ByRefConst x As String)
    Left(d, x, 3)
End Sub
Sub Tail(ByRef d As String(10), ByRef x As String(10))
    Right(d, x, 2)
    Mid(x, x, 1, 3)
End Sub
Function Pick() As Byte
    Result = 1
End Function
Cut(u, s)
If u = "hel" Then
    r1 = 1
EndIf
Cut(u, "abcdef")
If u = "abc" Then
    r2 = 1
EndIf
Tail(u, s)
If u = "lo" And s = "ell" Then
    r3 = 1
EndIf
names(0) = "abcdef"
names(1) = "ghijkl"
names(2) = "mnopqr"
j = 1
Mid(names(ix(j)), names(ix(2)), 1, 3)
Left(names(Pick()), names(ix(0)), 2)
If names(0) = "hij" And names(1) = "mn" Then
    r4 = 1
EndIf
