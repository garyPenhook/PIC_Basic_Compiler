' expect: T_R1=3957 T_R2=2373 T_R3=3450 T_R4=175 T_R5=10
' A Select (or an If chain) that only tests one Byte for equality with constants, with enough values packed close
' together, is a computed jump: a range test, then `addwf PCL` (PIC18) or `brw` (16F) into a table of `bra`. Covered:
' a first value of 0 and not 0, a gap in the range, one arm for several values, a value named twice in an `If` chain (the first test
' wins), no `Case Else`, a signed subject with negative values, values at the top of the byte, an `If` chain, and
' an arm that changes the subject. The routines get run-time arguments so the optimiser cannot fold the test.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim R1, R2, R3, R4 As Word
Dim R5 As Byte
Dim j As Word
Dim i As Byte
Dim k As Byte
Dim si As ShortInt

Function F1(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 10
        Case 1
            Result = 11
        Case 2
            Result = 12
        Case 3
            Result = 13
        Case 4
            Result = 14
        Case 5
            Result = 15
        Case 6
            Result = 16
        Case 7
            Result = 17
        Case 8
            Result = 18
        Case Else
            Result = 99
    End Select
End Function

Function F2(ByVal s As Byte) As Byte
    Result = 0
    Select s
        Case 1
            Result = 21
        Case 2
            Result = 22
        Case 3, 4
            Result = 23
        Case 6
            Result = 26
        Case 7
            Result = 27
        Case 8
            Result = 28
        Case 9
            Result = 29
        Case 10
            Result = 30
        Case 11
            Result = 31
        Case 12
            Result = 32
    End Select
End Function

Function F3(ByVal s As ShortInt) As Byte
    Select s
        Case -4
            Result = 40
        Case -3
            Result = 41
        Case -2
            Result = 42
        Case -1
            Result = 43
        Case 0
            Result = 44
        Case 1
            Result = 45
        Case 2
            Result = 46
        Case 3
            Result = 47
        Case 4
            Result = 48
        Case 5
            Result = 49
        Case Else
            Result = 1
    End Select
End Function

Function F4(ByVal s As Byte) As Byte
    Result = 0
    If s = 250 Then
        Result = 1
    ElseIf s = 251 Then
        Result = 2
    ElseIf s = 252 Then
        Result = 3
    ElseIf s = 252 Then
        Result = 77
    ElseIf s = 253 Then
        Result = 4
    ElseIf s = 254 Then
        Result = 5
    ElseIf s = 255 Then
        Result = 6
    End If
End Function

' The arm changes the subject: each pass of the loop must still take the arm of the value it started with.
Function F5(ByVal s As Byte) As Byte
    Dim t As Byte
    t = 0
    Select s
        Case 0
            s = 7
            t = t + 1
        Case 1
            s = 0
            t = t + 2
        Case 2
            s = 1
            t = t + 4
        Case 3
            s = 2
            t = t + 8
        Case 4
            s = 3
            t = t + 16
        Case Else
            t = t + 32
    End Select
    Result = t + s
End Function

For i = 0 To 11
    R1 = R1 + Word(F1(i)) * (i + 1)
Next
For i = 0 To 14
    R2 = R2 + Word(F2(i)) * (i + 1)
Next
k = 0
For si = -6 To 7
    k = k + 1
    R3 = R3 + Word(F3(si)) * k
Next
k = 0
For i = 246 To 255
    k = k + 1
    R4 = R4 + Word(F4(i)) * k
Next
For i = 0 To 2
    k = k + 1
    R4 = R4 + Word(F4(i)) * k
Next
R5 = F5(0) + F5(2) + F5(4) - F5(9) + F5(4)
