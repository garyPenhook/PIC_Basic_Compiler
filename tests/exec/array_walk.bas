' Loops over a Byte array indexed by the loop variable walk it with FSR0 (INDF0 / POSTINC0) and, when the variable
' has no other use, count the passes down. Fills, sums, updates in place, Break, Continue, a counted loop inside,
' all 256 values of a Byte index, and bodies that must not walk (a second array, a call, another element).
' expect: T_R0=32640 T_R1=29340 T_R2=87 T_R3=20640 T_R4=2 T_R5=3027 T_R6=205 T_R7=23664 T_R8=897 T_R9=1008 T_R10=269 T_R11=2593
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim A(300) As Byte
Dim B(40) As Byte
Dim R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11 As LongWord
Dim crc As Byte

Function Twice(ByVal x As Byte) As Byte
    Result = x + x
End Function

Sub Fill()
    Dim i As Byte
    For i = 0 To 255
        A(i) = i * 3 + 1
    Next
    For i = 0 To 255
        R0 = R0 + A(i)
    Next
    For i = 10 To 49
        A(i) = 7
    Next
    For i = 0 To 255
        R1 = R1 + A(i)
    Next
End Sub

Sub Cond()
    Dim i As Byte
    For i = 0 To 199
        If A(i) > 100 Then
            A(i) = A(i) - 100
            R2 = R2 + 1
        End If
    Next
    For i = 0 To 255
        R3 = R3 + A(i)
    Next
    For i = 0 To 255
        If A(i) = 7 Then
            Break
        End If
        R4 = R4 + 1
    Next
    For i = 5 To 119
        If (A(i) And 1) = 0 Then
            Continue
        End If
        R5 = R5 + A(i)
    Next
End Sub

Sub DoCrc()
    Dim i, j As Byte
    crc = $FF
    For i = 0 To 63
        crc = crc Xor A(i)
        For j = 1 To 8
            If (crc And $80) <> 0 Then
                crc = (crc << 1) Xor $31
            Else
                crc = crc << 1
            End If
        Next
    Next
    R6 = crc
End Sub

Sub Update()
    Dim i As Byte
    For i = 20 To 59
        A(i) = A(i) + 1
    Next
    For i = 0 To 255
        A(i) = A(i) Xor i
    Next
    For i = 0 To 255
        R7 = R7 + A(i)
    Next
End Sub

Sub NoWalk()
    Dim i As Byte
    For i = 0 To 39
        B(i) = A(i)
    Next
    For i = 0 To 39
        R8 = R8 + B(i)
    Next
    For i = 0 To 29
        R9 = R9 + Twice(A(i))
    Next
    For i = 0 To 99
        R10 = R10 Xor A(i)
    Next
    R10 = R10 + i
    For i = 0 To 49
        R11 = R11 + A(i) + A(i + 1)
    Next
End Sub

Fill()
Cond()
DoCrc()
Update()
NoWalk()
