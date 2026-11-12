' expect: T_R0=4250 T_R1=6375 T_R2=8070 T_R3=10260 T_R4=5426 T_R5=17862 T_R6=8156 T_R7=9545 T_R8=4240 T_R9=17305 T_R10=5472 T_R11=19777 T_R12=16134 T_R13=7190 T_R14=18534 T_R15=4975 T_R16=15886 T_R17=26130 T_R18=6648 T_R19=14165
' Many dense Selects of different sizes (and with a first value of 0 and not 0) one after the other, so that some of the
' jump tables begin near the end of a 256-byte block of program memory and are moved to the next one (PIC18): every
' table must still be reached. Each routine is run over its whole range and a little beyond it.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Byte
Dim R0 As Word
Dim R1 As Word
Dim R2 As Word
Dim R3 As Word
Dim R4 As Word
Dim R5 As Word
Dim R6 As Word
Dim R7 As Word
Dim R8 As Word
Dim R9 As Word
Dim R10 As Word
Dim R11 As Word
Dim R12 As Word
Dim R13 As Word
Dim R14 As Word
Dim R15 As Word
Dim R16 As Word
Dim R17 As Word
Dim R18 As Word
Dim R19 As Word

Function F0(ByVal s As Byte) As Byte
    Select s
        Case 1
            Result = 5
        Case 2
            Result = 8
        Case 3
            Result = 11
        Case 4
            Result = 14
        Case 5
            Result = 17
        Case Else
            Result = 250
    End Select
End Function

Function F1(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 9
        Case 1
            Result = 12
        Case 2
            Result = 15
        Case 3
            Result = 18
        Case 4
            Result = 21
        Case 5
            Result = 24
        Case 6
            Result = 27
        Case 7
            Result = 30
        Case 8
            Result = 33
        Case Else
            Result = 250
    End Select
End Function

Function F2(ByVal s As Byte) As Byte
    Select s
        Case 3
            Result = 25
        Case 4
            Result = 28
        Case 5
            Result = 31
        Case 6
            Result = 34
        Case 7
            Result = 37
        Case 8
            Result = 40
        Case Else
            Result = 250
    End Select
End Function

Function F3(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 23
        Case 1
            Result = 26
        Case 2
            Result = 29
        Case 3
            Result = 32
        Case 4
            Result = 35
        Case 5
            Result = 38
        Case 6
            Result = 41
        Case 7
            Result = 44
        Case 8
            Result = 47
        Case 9
            Result = 50
        Case 10
            Result = 53
        Case 11
            Result = 56
        Case Else
            Result = 250
    End Select
End Function

Function F4(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 30
        Case 1
            Result = 33
        Case 2
            Result = 36
        Case 3
            Result = 39
        Case 4
            Result = 42
        Case 5
            Result = 45
        Case 6
            Result = 48
        Case Else
            Result = 250
    End Select
End Function

Function F5(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 37
        Case 1
            Result = 40
        Case 2
            Result = 43
        Case 3
            Result = 46
        Case 4
            Result = 49
        Case 5
            Result = 52
        Case 6
            Result = 55
        Case 7
            Result = 58
        Case 8
            Result = 61
        Case 9
            Result = 64
        Case 10
            Result = 67
        Case 11
            Result = 70
        Case 12
            Result = 73
        Case 13
            Result = 76
        Case 14
            Result = 79
        Case 15
            Result = 82
        Case Else
            Result = 250
    End Select
End Function

Function F6(ByVal s As Byte) As Byte
    Select s
        Case 1
            Result = 47
        Case 2
            Result = 50
        Case 3
            Result = 53
        Case 4
            Result = 56
        Case 5
            Result = 59
        Case 6
            Result = 62
        Case 7
            Result = 65
        Case 8
            Result = 68
        Case Else
            Result = 250
    End Select
End Function

Function F7(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 51
        Case 1
            Result = 54
        Case 2
            Result = 57
        Case 3
            Result = 60
        Case 4
            Result = 63
        Case 5
            Result = 66
        Case 6
            Result = 69
        Case 7
            Result = 72
        Case 8
            Result = 75
        Case 9
            Result = 78
        Case Else
            Result = 250
    End Select
End Function

Function F8(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 58
        Case 1
            Result = 61
        Case 2
            Result = 64
        Case 3
            Result = 67
        Case 4
            Result = 70
        Case Else
            Result = 250
    End Select
End Function

Function F9(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 65
        Case 1
            Result = 68
        Case 2
            Result = 71
        Case 3
            Result = 74
        Case 4
            Result = 77
        Case 5
            Result = 80
        Case 6
            Result = 83
        Case 7
            Result = 86
        Case 8
            Result = 89
        Case 9
            Result = 92
        Case 10
            Result = 95
        Case 11
            Result = 98
        Case 12
            Result = 101
        Case 13
            Result = 104
        Case Else
            Result = 250
    End Select
End Function

Function F10(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 72
        Case 1
            Result = 75
        Case 2
            Result = 78
        Case 3
            Result = 81
        Case 4
            Result = 84
        Case 5
            Result = 87
        Case Else
            Result = 250
    End Select
End Function

Function F11(ByVal s As Byte) As Byte
    Select s
        Case 3
            Result = 88
        Case 4
            Result = 91
        Case 5
            Result = 94
        Case 6
            Result = 97
        Case 7
            Result = 100
        Case 8
            Result = 103
        Case 9
            Result = 106
        Case 10
            Result = 109
        Case 11
            Result = 112
        Case 12
            Result = 115
        Case 13
            Result = 118
        Case Else
            Result = 250
    End Select
End Function

Function F12(ByVal s As Byte) As Byte
    Select s
        Case 3
            Result = 95
        Case 4
            Result = 98
        Case 5
            Result = 101
        Case 6
            Result = 104
        Case 7
            Result = 107
        Case 8
            Result = 110
        Case 9
            Result = 113
        Case 10
            Result = 116
        Case 11
            Result = 119
        Case Else
            Result = 250
    End Select
End Function

Function F13(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 93
        Case 1
            Result = 96
        Case 2
            Result = 99
        Case 3
            Result = 102
        Case 4
            Result = 105
        Case 5
            Result = 108
        Case 6
            Result = 111
        Case Else
            Result = 250
    End Select
End Function

Function F14(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 100
        Case 1
            Result = 103
        Case 2
            Result = 106
        Case 3
            Result = 109
        Case 4
            Result = 112
        Case 5
            Result = 115
        Case 6
            Result = 118
        Case 7
            Result = 121
        Case 8
            Result = 124
        Case 9
            Result = 127
        Case 10
            Result = 130
        Case 11
            Result = 133
        Case 12
            Result = 136
        Case Else
            Result = 250
    End Select
End Function

Function F15(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 107
        Case 1
            Result = 110
        Case 2
            Result = 113
        Case 3
            Result = 116
        Case 4
            Result = 119
        Case Else
            Result = 250
    End Select
End Function

Function F16(ByVal s As Byte) As Byte
    Select s
        Case 3
            Result = 123
        Case 4
            Result = 126
        Case 5
            Result = 129
        Case 6
            Result = 132
        Case 7
            Result = 135
        Case 8
            Result = 138
        Case 9
            Result = 141
        Case 10
            Result = 144
        Case Else
            Result = 250
    End Select
End Function

Function F17(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 121
        Case 1
            Result = 124
        Case 2
            Result = 127
        Case 3
            Result = 130
        Case 4
            Result = 133
        Case 5
            Result = 136
        Case 6
            Result = 139
        Case 7
            Result = 142
        Case 8
            Result = 145
        Case 9
            Result = 148
        Case 10
            Result = 151
        Case 11
            Result = 154
        Case 12
            Result = 157
        Case 13
            Result = 160
        Case 14
            Result = 163
        Case Else
            Result = 250
    End Select
End Function

Function F18(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 128
        Case 1
            Result = 131
        Case 2
            Result = 134
        Case 3
            Result = 137
        Case 4
            Result = 140
        Case 5
            Result = 143
        Case Else
            Result = 250
    End Select
End Function

Function F19(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 135
        Case 1
            Result = 138
        Case 2
            Result = 141
        Case 3
            Result = 144
        Case 4
            Result = 147
        Case 5
            Result = 150
        Case 6
            Result = 153
        Case 7
            Result = 156
        Case 8
            Result = 159
        Case 9
            Result = 162
        Case Else
            Result = 250
    End Select
End Function

For i = 0 To 7
    R0 = R0 + Word(F0(i)) * (i + 1)
Next
For i = 0 To 10
    R1 = R1 + Word(F1(i)) * (i + 1)
Next
For i = 0 To 10
    R2 = R2 + Word(F2(i)) * (i + 1)
Next
For i = 0 To 13
    R3 = R3 + Word(F3(i)) * (i + 1)
Next
For i = 0 To 8
    R4 = R4 + Word(F4(i)) * (i + 1)
Next
For i = 0 To 17
    R5 = R5 + Word(F5(i)) * (i + 1)
Next
For i = 0 To 10
    R6 = R6 + Word(F6(i)) * (i + 1)
Next
For i = 0 To 11
    R7 = R7 + Word(F7(i)) * (i + 1)
Next
For i = 0 To 6
    R8 = R8 + Word(F8(i)) * (i + 1)
Next
For i = 0 To 15
    R9 = R9 + Word(F9(i)) * (i + 1)
Next
For i = 0 To 7
    R10 = R10 + Word(F10(i)) * (i + 1)
Next
For i = 0 To 15
    R11 = R11 + Word(F11(i)) * (i + 1)
Next
For i = 0 To 13
    R12 = R12 + Word(F12(i)) * (i + 1)
Next
For i = 0 To 8
    R13 = R13 + Word(F13(i)) * (i + 1)
Next
For i = 0 To 14
    R14 = R14 + Word(F14(i)) * (i + 1)
Next
For i = 0 To 6
    R15 = R15 + Word(F15(i)) * (i + 1)
Next
For i = 0 To 12
    R16 = R16 + Word(F16(i)) * (i + 1)
Next
For i = 0 To 16
    R17 = R17 + Word(F17(i)) * (i + 1)
Next
For i = 0 To 7
    R18 = R18 + Word(F18(i)) * (i + 1)
Next
For i = 0 To 11
    R19 = R19 + Word(F19(i)) * (i + 1)
Next
