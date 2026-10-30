' expect: SCA_R1=1 SCA_R2=1 SCA_R3=1 SCA_R4=1 SCA_R5=1 SCA_R6=1 SCA_R7=1 SCA_R8=1
Program Sca
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim s As String(10)
Dim t As String(10)
Dim names(3) As String(8)
Dim ix(3) As Byte = (2, 0, 1)
Dim j As Byte
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Byte
Dim r7 As Byte
Dim r8 As Byte
Function Pick() As Byte
    Result = 1
End Function
' the target after the first operand
s = "cd"
s = "ab" + s
If s = "abcd" Then
    r1 = 1
EndIf
s = "cd"
t = "x"
s = t + s + s
If s = "xcdcd" Then
    r2 = 1
EndIf
' cut off at the target's size while staged
s = "123456"
s = "abcdef" + s
If s = "abcdef1234" Then
    r3 = 1
EndIf
' an index that reads an array
names(0) = "zero"
names(1) = "one"
names(2) = "two"
j = 1
names(ix(j)) = "set"
If names(0) = "set" Then
    r4 = 1
EndIf
s = names(ix(2))
If s = "one" Then
    r5 = 1
EndIf
s = "<" + names(ix(0)) + ">"
If s = "<two>" Then
    r6 = 1
EndIf
' an index that calls a routine
names(Pick()) = "call"
If names(1) = "call" Then
    r7 = 1
EndIf
names(2) = "q" + names(Pick())
If names(2) = "qcall" Then
    r8 = 1
EndIf
