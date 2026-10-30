' expect: SSL_R1=104 SSL_R2=101 SSL_R3=0 SSL_R4=0 SSL_R5=108 SSL_R6=111 SSL_R7=0 SSL_R8=108 SSL_R9=0 SSL_R10=0 SSL_R11=0 SSL_R12=0 SSL_R13=0 SSL_R14=0 SSL_R15=1 SSL_R16=1 SSL_R17=1 SSL_R18=1 SSL_R19=104 SSL_R20=0 SSL_R21=101 SSL_R22=108 SSL_R23=3
Program Ssl
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "strings"
Dim s As String(10) = "hello"
Dim t As String(3)
Dim u As String(10)
Dim names(2) As String(8)
Dim n As Byte
Dim w As Word
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
' Left
Left(u, s, 2)
r1 = Byte(u(0))
r2 = Byte(u(1))
r3 = Byte(u(2))
r4 = 0
If u = "he" Then
    r15 = 1
EndIf
' Right
Right(u, s, 2)
If u = "lo" Then
    r16 = 1
EndIf
' Mid with and without a count
Mid(u, s, 1, 3)
If u = "ell" Then
    r17 = 1
EndIf
Mid(u, s, 3)
r5 = Byte(u(0))
r6 = Byte(u(1))
r7 = Byte(u(2))
' cut off at the destination size
Left(t, s, 9)
r8 = Byte(t(2))
r9 = Byte(t(3))
' a count past the end, a start past the end, a count of 0
Left(u, s, 200)
r10 = Len(u) - 5
Mid(u, s, 9, 2)
r11 = Len(u)
r12 = r11
Right(u, s, 0)
r13 = Len(u)
r14 = r13
' run-time arguments
n = 4
w = 300
Left(u, s, n)
If u = "hell" Then
    r18 = 1
EndIf
Right(u, s, w)
r19 = Byte(u(0))
r20 = Byte(u(5))
' in place, a literal source, an element of an array of strings
Mid(s, s, 1, 2)
r21 = Byte(s(0))
r22 = Byte(s(1))
names(1) = "abcdef"
Right(names(1), "xyz12", 3)
r23 = Len(names(1))
