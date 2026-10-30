' expect: SCC_R1=1 SCC_R2=0 SCC_R3=1 SCC_R4=1 SCC_R5=1 SCC_R6=0 SCC_R7=1 SCC_R8=1 SCC_R9=1 SCC_R10=1 SCC_R11=0 SCC_R12=1
Program Scc
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim s As String(10) = "ab"
Dim t As String(10) = "abcd"
Dim u As String(10)
Dim c As Char
Dim n As Byte
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
Function Same(ByRefConst x As String(10), ByRefConst y As String(10)) As Boolean
    Result = x + "!" = y + "!"
End Function
c = "d"
u = "cd"
If s + u = t Then
    r1 = 1
EndIf
If s + "c" = t Then
    r2 = 0
Else
    r2 = 0
EndIf
If t = s + "cd" Then
    r3 = 1
EndIf
If t = s + u And s + u <> "abc" Then
    r4 = 1
EndIf
If "abcd" = s + "c" + c Then
    r5 = 1
EndIf
If s + s = t Then
    r6 = 1
EndIf
If s + u = s + "cd" Then
    r7 = 1
EndIf
' in a loop, the text changes
n = 0
While s + u <> "abcdd"
    u = u + c
    Inc(n)
Wend
r8 = n
' as a Boolean value
r9 = 0
If Same(s, s) Then
    r9 = 1
EndIf
r10 = 0
If Same(s, t) = False Then
    r10 = 1
EndIf
If s + "" = t Then
    r11 = 0
EndIf
r12 = 1
