' expect: SFN_R1=1 SFN_R2=1 SFN_R3=1 SFN_R4=1 SFN_R5=1 SFN_R6=1 SFN_R7=1 SFN_R8=1 SFN_R9=1 SFN_R10=1 SFN_R11=5 SFN_R12=1
Program Sfn
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "strings"
Dim s As String(10) = "hello"
Dim u As String(20)
Dim names(2) As String(8)
Dim n As Byte
Dim w As Word
Dim i As Integer
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
' assigned
u = Left$(s, 2)
If u = "he" Then
    r1 = 1
EndIf
u = Right$(s, 3)
If u = "llo" Then
    r2 = 1
EndIf
u = Mid$(s, 1, 3)
If u = "ell" Then
    r3 = 1
EndIf
u = Mid$(s, 3)
If u = "lo" Then
    r4 = 1
EndIf
' compared and joined
If Left$(s, 1) = "h" Then
    r5 = 1
EndIf
u = Left$(s, 2) + "-" + Right$(s, 2)
If u = "he-lo" Then
    r6 = 1
EndIf
' run-time counts, nested, a literal source
n = 4
u = Left$(s, n)
If u = "hell" Then
    r7 = 1
EndIf
u = Right$(Left$(s, 4), 2)
If u = "ll" Then
    r8 = 1
EndIf
names(1) = Mid$("abcdef", 2, 2)
If names(1) = "cd" Then
    r9 = 1
EndIf
' Str$
n = 42
w = 65000
i = -123
u = Str$(n) + "/" + Str$(w) + "/" + Str$(i)
If u = "42/65000/-123" Then
    r10 = 1
EndIf
r11 = Len(Str$(w))
' in place
s = Right$(s, 3)
If s = "llo" Then
    r12 = 1
EndIf
