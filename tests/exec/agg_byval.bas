' expect: ABV_R1=4 ABV_R2=3 ABV_R3=88 ABV_R4=3 ABV_R5=1 ABV_R6=1 ABV_R7=1 ABV_R8=1 ABV_R9=6 ABV_R10=1 ABV_R11=7 ABV_R12=0 ABV_R13=1 ABV_R14=3 ABV_R15=1 ABV_R16=410 ABV_R17=3
Program Abv
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Structure Pt
    x As Byte
    y As Word
End Structure
Dim p As Pt = (3, 300)
Dim s As String(8)
Dim t As String(4)
Dim u As String(9)
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Byte
Dim r7 As Byte
Dim r8 As Byte
Dim r9 As Byte
Dim r10 As Byte
Dim r11 As Byte
Dim r12 As Byte
Dim r13 As Byte
Dim r14 As Byte
Dim r15 As Byte
Dim r16 As Word
Dim r17 As Byte
Dim nm(3) As String(8)
Dim kk(3) As Byte
Dim ii As Byte
Dim bq As Pt
' the callee may change its copy; the caller's stays
Function Bump(ByVal v As Pt) As Byte
    v.x = v.x + 1
    Result = v.x
End Function
Function Shout(ByVal v As String(8)) As Byte
    v(0) = "X"
    Result = Byte(v(0))
End Function
Function Same(ByVal a As String(8), ByVal b As String(8)) As Boolean
    Result = a = b
End Function
Function Lenx(ByVal a As String(8)) As Byte
    Dim i As Byte
    i = 0
    While a(i) <> #0
        i = i + 1
    Wend
    Result = i
End Function
Function Mk(ByVal x As Byte) As Pt
    Result.x = x
    Result.y = 7
End Function
Function Hello() As String(6)
    Result = "hello"
End Function
Function Word2(ByVal i As Byte) As String(4)
    If i = 0 Then
        Result = "ab"
    Else
        Result = "cde"
    End If
End Function
Function TakeConst(ByRefConst a As String(8)) As Byte
    Result = Byte(a(1))
End Function
' Reentrant results
Reentrant Function Rep(ByVal n As Byte) As String(9)
    If n = 0 Then
        Result = ""
    Else
        Result = "a" + Rep(n - 1)
    End If
End Function
Reentrant Function Build(ByVal n As Byte) As Pt
    Dim q As Pt
    If n = 0 Then
        Result.x = 0
        Result.y = 0
    Else
        q = Build(n - 1)
        Result.x = q.x + n
        Result.y = q.y + 100
    End If
End Function
s = "hello"
r1 = Bump(p)
r2 = p.x
r3 = Shout(s)
r3 = r3 + 0
If s(0) = "h" Then
    r4 = 3
EndIf
If Same(s, "hello") Then
    r5 = 1
EndIf
r6 = Lenx("abc") - 2
' a function result passed on, and compared
If Same(Hello(), "hello") Then
    r7 = 1
EndIf
If Hello() = "hello" Then
    r8 = 1
EndIf
r9 = Lenx(Hello() + "x")
If Word2(1) <> Word2(0) And Word2(0) = "ab" Then
    r10 = 1
EndIf
r11 = Bump(Mk(6))
r12 = TakeConst(Hello() + "!") - 101
If Word2(0) + Word2(1) = "abcde" Then
    r13 = 1
EndIf
' Reentrant
u = Rep(3)
r14 = Lenx(u)
If Rep(2) = "aa" Then
    r15 = 1
EndIf
t = "z"
bq = Build(4)
r16 = bq.y + bq.x
nm(2) = "two"
kk(1) = 2
ii = 1
If nm(kk(ii)) = "two" Then
    r17 = 1
EndIf
While nm(kk(ii)) = "two" And r17 < 3
    r17 = r17 + 1
Wend
