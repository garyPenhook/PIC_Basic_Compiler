' expect: SNM_V1=123 SNM_V2=65413 SNM_V3=0 SNM_V4=4660 SNM_V5=7 SNM_V6=100000 SNM_V7=1 SNM_V8=1 SNM_V9=1 SNM_V10=1 SNM_V11=1 SNM_V12=1 SNM_V13=1 SNM_V14=1 SNM_V15=1 SNM_V16=1 SNM_V17=1
Program Snm
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim s As String(12)
Dim t As String(3)
Dim b As Byte
Dim w As Word
Dim i As Integer
Dim si As ShortInt
Dim l As LongInt
Dim lw As LongWord
Dim v1 As LongInt
Dim v2 As LongInt
Dim v3 As LongInt
Dim v4 As LongInt
Dim v5 As LongInt
Dim v6 As LongInt
Dim v7 As Byte
Dim v8 As Byte
Dim v9 As Byte
Dim v10 As Byte
Dim v11 As Byte
Dim v12 As Byte
Dim v13 As Byte
Dim v14 As Byte
Dim v15 As Byte
Dim v16 As Byte
Dim v17 As Byte
Function Hello() As String(6)
    Result = "-42x"
End Function
Sub Show(ByVal x As String(12))
    v6 = Val(x)
End Sub
' Val
s = "123"
v1 = Val(s)
s = "-123"
v2 = 65536 + Val(s) + 0
s = "abc"
v3 = Val(s)
v4 = Val("4660")
s = " 7"
s = "+7z"
v5 = Val(s)
Show("100000")
If Val("-5") = 0 - 5 Then
    v7 = 1
EndIf
If Val(Hello()) = 0 - 42 Then
    v8 = 1
EndIf
' Str
b = 200
Str(s, b)
If s = "200" Then
    v9 = 1
EndIf
i = 0 - 1234
Str(s, i)
If s = "-1234" Then
    v10 = 1
EndIf
si = 0 - 128
Str(s, si)
If s = "-128" Then
    v11 = 1
EndIf
l = 0 - 2147483647
Str(s, l)
If s = "-2147483647" Then
    v12 = 1
EndIf
lw = 4000000000
Str(s, lw)
If s = "4000000000" Then
    v13 = 1
EndIf
w = 0
Str(s, w)
If s = "0" Then
    v14 = 1
EndIf
' cut off at the destination's size, always ended
w = 65535
Str(t, w)
If t = "655" Then
    v15 = 1
EndIf
Str(s, 99)
If s = "99" Then
    v16 = 1
EndIf
' round trip
w = 54321
Str(s, w)
If Val(s) = 54321 Then
    v17 = 1
EndIf
