' expect: STR_R1=104 STR_R2=111 STR_R3=0 STR_R4=1 STR_R5=1 STR_R6=1 STR_R7=1 STR_R8=108 STR_R9=0 STR_R10=100 STR_R11=0 STR_R12=101 STR_R13=0 STR_R14=104 STR_R15=1 STR_R16=1 STR_R17=0 STR_R18=111 STR_R19=107 STR_R20=0 STR_R21=33 STR_R22=1 STR_R23=1 STR_R24=1 STR_R25=0 STR_R26=121 STR_R27=2 STR_R28=97 STR_R29=1 STR_W1=294 STR_W2=365 STR_W3=0 STR_W4=1
Program Str
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim s As String(10)
Dim t As String(10)
Dim u As String(6)
Dim g As String = "ok"
Dim c As Char
Dim i As Byte
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
Dim r16 As Byte
Dim r17 As Byte
Dim r18 As Byte
Dim r19 As Byte
Dim r20 As Byte
Dim r21 As Byte
Dim r22 As Byte
Dim r23 As Byte
Dim r24 As Byte
Dim r25 As Byte
Dim r26 As Byte
Dim r27 As Byte
Dim r28 As Byte
Dim r29 As Byte
Dim w1 As Word
Dim w2 As Word
Dim w3 As Word
Dim w4 As Word
Function Sum(ByRefConst m As String(24)) As Word
    Dim k As Byte
    Dim acc As Word
    k = 0
    acc = 0
    While m(k) <> #0
        acc = acc + Byte(m(k))
        Inc(k)
    Wend
    Result = acc
End Function
Sub Fill(ByRef d As String(10))
    d = "hi"
    d = d + "!"
End Sub
Sub Wipe(ByRef d As String(10))
    Clear(d)
End Sub
Sub Outer(ByRef d As String(10), ByRef e As String(10))
    Fill(d)
    If d = "hi!" Then
        w4 = 1
    EndIf
    e = d
End Sub
s = "hello"
r1 = Byte(s(0))
r2 = Byte(s(4))
r3 = Byte(s(5))
t = s
If t = s Then
    r4 = 1
EndIf
If t = "hello" Then
    r5 = 1
EndIf
If t <> "hellp" Then
    r6 = 1
EndIf
If "hello" = t Then
    r7 = 1
EndIf
t = s + " world"
r8 = Byte(t(9))
r9 = Byte(t(10))
u = "ab"
u = u + "cd"
r10 = Byte(u(3))
r11 = Byte(u(4))
u = u + s
r12 = Byte(u(5))
r13 = Byte(u(6))
c = "x"
u = "ab" + c
u = u + s(0)
r14 = Byte(u(3))
If u = "abxh" Then
    r15 = 1
EndIf
Clear(u)
If u = Null Then
    r16 = 1
EndIf
u = "q"
r17 = Byte(u(1))
r18 = Byte(g(0))
r19 = Byte(g(1))
r20 = Byte(g(2))
Outer(t, s)
r21 = Byte(s(2))
If s = t Then
    r22 = 1
EndIf
If s <> "hi" Then
    r23 = 1
EndIf
If s = "hi!" And t = "hi!" Then
    r24 = 1
EndIf
' element write, variable index
For i = 0 To 2
    s(i) = "z"
Next
r25 = Byte(s(3))
s(1) = "y"
r26 = Byte(s(1))
w1 = Sum("abc")
w2 = Sum(s)
w3 = Sum("")
r27 = 2
t = "xy"
s = "ab"
s = t + s(0)
r28 = Byte(s(2))
s = "abc"
Wipe(s)
If s = Null Then
    r29 = 1
EndIf
