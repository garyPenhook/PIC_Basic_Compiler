' expect: AGR_R1=3 AGR_R2=300 AGR_R3=104 AGR_R4=1 AGR_R5=1 AGR_R6=1 AGR_R7=1 AGR_R8=7 AGR_R9=1 AGR_R10=1
Program Agr
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Structure Pt
    x As Byte
    y As Word
End Structure
Dim p As Pt
Dim q As Pt
Dim a(3) As Pt
Dim s As String(12)
Dim t As String(4)
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
Function Mk(ByVal x As Byte) As Pt
    Result.x = x
    Result.y = 300
End Function
Function Twice(ByRef v As Pt) As Pt
    Result = v
    Result.x = v.x + v.x
End Function
Function Hello() As String(6)
    Result = "hello"
End Function
Function Name(ByVal i As Byte) As String(4)
    If i = 0 Then
        Result = "ab"
    Else
        Result = "cde"
    End If
End Function
p = Mk(3)
r1 = p.x
r2 = p.y
s = Hello()
r3 = Byte(s(0))
q = Twice(p)
If q.x = 6 And q.y = 300 Then
    r4 = 1
EndIf
a(2) = Mk(9)
If a(2).x = 9 Then
    r5 = 1
EndIf
n = 2
a(n) = Mk(7)
r8 = a(2).x
' strings: a call among several parts, two calls in one expression
s = Name(0) + "-" + Name(1)
If s = "ab-cde" Then
    r6 = 1
EndIf
s = "<" + Hello() + Name(1) + ">"
If s = "<hellocde>" Then
    r7 = 1
EndIf
t = Name(1)
If t = "cde" Then
    r9 = 1
EndIf
p = Mk(1)
q = Mk(2)
If p.x = 1 And q.x = 2 Then
    r10 = 1
EndIf
