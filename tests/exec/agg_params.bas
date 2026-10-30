' expect: AGP_R1=4 AGP_R2=40 AGP_R3=9 AGP_R4=110 AGP_R5=1 AGP_R6=1 AGP_R7=0 AGP_R8=110 AGP_R9=1 AGP_R10=14 AGP_R11=1
Program Agp
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Structure Pt
    x As Byte
    y As Word
End Structure
Dim p As Pt = (3, 300)
Dim a(3) As Pt = (1, 10, 2, 20, 4, 40)
Dim names(3) As String(6) = ("one", "two", "three")
Dim s As String(6)
Dim n As Byte
Dim r1 As Byte
Dim r2 As Word
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Byte
Dim r7 As Byte
Dim r8 As Byte
Dim r9 As Byte
Dim r10 As Byte
Dim r11 As Byte
Sub ShowPt(ByRefConst v As Pt)
    r1 = v.x
    r2 = v.y
End Sub
Function SumX(ByRefConst v() As Pt) As Byte
    Dim i As Byte
    Dim t As Byte
    t = 0
    For i = 0 To Bound(v)
        t = t + v(i).x
    Next
    Result = t
End Function
Sub Fill(ByRef v() As Pt)
    v(1).x = 9
End Sub
Sub Rename(ByRef v() As String(6))
    v(2) = "x" + v(0)
End Sub
Function Pick(ByRefConst v() As String(6), ByVal i As Byte) As Byte
    Result = Byte(v(i)(1))
End Function
Function Same(ByRefConst v() As String(6), ByVal i As Byte, ByRefConst t As String(6)) As Boolean
    Result = v(i) = t
End Function
ShowPt(p)
ShowPt(a(2))
Fill(a)
r3 = a(1).x
n = 7
r10 = SumX(a)
Rename(names)
r4 = Byte(names(2)(2))
If names(2) = "xone" Then
    r5 = 1
EndIf
r6 = Pick(names, 1) - 118
r7 = SumX(a) - 14
r8 = Pick(names, 0)
If Same(names, 1, "two") Then
    r9 = 1
EndIf
r11 = 1
