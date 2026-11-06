' expect: EX2_A=1 EX2_B=123 EX2_C=3 EX2_D=1
Program Ex2
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim s As String(10) = "abc123"
Dim t As String(10) = "xxy"
Dim a As Byte
Dim b As Word
Dim c As Byte
Dim d As Byte
Dim n As Byte
Sub Count()
    Dim k As Byte
    k = 0
    GoSub Inc1
    GoSub Inc1
    GoSub Inc1
    c = k
    Exit
Inc1:
    k = k + 1
    Return
End Sub
' a loop condition that builds a String every pass
n = 0
While Left$(t, 1) = "x"
    t = Mid$(t, 1)
    Inc(n)
Wend
If n = 2 Then
    a = 1
EndIf
b = Word(Val(Right$(s, 3)))
Count()
If Left$(s, 1) = Left$("alpha", 1) And Right$(s, 1) <> Left$(s, 1) Then
    d = 1
EndIf
