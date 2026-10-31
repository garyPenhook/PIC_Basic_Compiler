' expect: FWD_R1=1 FWD_R2=0 FWD_R3=1 FWD_R4=0 FWD_R5=10 FWD_R6=55 FWD_R7=5
Program Fwd
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim r1 As Boolean
Dim r2 As Boolean
Dim r3 As Boolean
Dim r4 As Boolean
Dim r5 As Byte
Dim r6 As Word
Dim r7 As Byte
Dim hits As Byte

Declare Reentrant Function IsEven(ByVal n As Byte) As Boolean
Declare Reentrant Function IsOdd(ByVal n As Byte) As Boolean
Declare Reentrant Sub Count(ByVal n As Byte)
Declare Reentrant Function Total(ByVal n As Byte) As Word

Reentrant Function IsEven(ByVal n As Byte) As Boolean
    If n = 0 Then
        Result = True
    Else
        Result = IsOdd(n - 1)
    End If
End Function

Reentrant Function IsOdd(ByVal n As Byte) As Boolean
    If n = 0 Then
        Result = False
    Else
        Result = IsEven(n - 1)
    End If
End Function

Reentrant Sub Count(ByVal n As Byte)
    If n > 0 Then
        Inc(hits)
        Count(n - 1)
    End If
End Sub

Reentrant Function Total(ByVal n As Byte) As Word
    If n = 0 Then
        Result = 0
    Else
        Result = n + Total(n - 1)
    End If
End Function

Declare Function Twice(ByVal n As Byte) As Byte
Sub UseTwice()
    r5 = Twice(5)
End Sub
Function Twice(ByVal n As Byte) As Byte
    Result = n * 2
End Function

UseTwice()
r1 = IsEven(10)
r2 = IsEven(7)
r3 = IsOdd(9)
r4 = IsOdd(4)
r6 = Total(10)
r7 = 0
Count(5)
r7 = hits
