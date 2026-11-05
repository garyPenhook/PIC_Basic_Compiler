' (x And K) = 0 / <> 0 tests only the bytes K touches: btfsc/btfss for one bit, movlw/andwf for several bits in a byte,
' one test per non-zero mask byte for wider masks. Run-time arguments so the optimiser cannot fold them.
' expect: T_R0=1 T_R1=0 T_R2=0 T_R3=1 T_R4=1 T_R5=0 T_R6=0 T_R7=1
' expect: T_R8=1 T_R9=0 T_R10=1 T_R11=0 T_R12=1 T_R13=0 T_R14=1 T_R15=0
' expect: T_R16=1 T_R17=0 T_R18=0 T_R19=1 T_R20=1 T_R21=0 T_R22=8 T_R23=0
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim R0 As Byte
Dim R1 As Byte
Dim R2 As Byte
Dim R3 As Byte
Dim R4 As Byte
Dim R5 As Byte
Dim R6 As Byte
Dim R7 As Byte
Dim R8 As Byte
Dim R9 As Byte
Dim R10 As Byte
Dim R11 As Byte
Dim R12 As Byte
Dim R13 As Byte
Dim R14 As Byte
Dim R15 As Byte
Dim R16 As Byte
Dim R17 As Byte
Dim R18 As Byte
Dim R19 As Byte
Dim R20 As Byte
Dim R21 As Byte
Dim R22 As Byte
Dim R23 As Byte

' One bit, set / clear, <> and =.
Function B1Ne(ByVal x As Byte) As Byte
    Result = 0
    If (x And $10) <> 0 Then
        Result = 1
    End If
End Function
Function B1Eq(ByVal x As Byte) As Byte
    Result = 0
    If (x And $10) = 0 Then
        Result = 1
    End If
End Function
' Several bits in one byte.
Function BmNe(ByVal x As Byte) As Byte
    Result = 0
    If (x And $0C) <> 0 Then
        Result = 1
    End If
End Function
Function BmEq(ByVal x As Byte) As Byte
    Result = 0
    If (x And $0C) = 0 Then
        Result = 1
    End If
End Function
' A Word mask spanning both bytes (two tests), and one touching only the high byte.
Function WNe(ByVal x As Word) As Byte
    Result = 0
    If (x And $8001) <> 0 Then
        Result = 1
    End If
End Function
Function WEq(ByVal x As Word) As Byte
    Result = 0
    If (x And $8001) = 0 Then
        Result = 1
    End If
End Function
Function WHiNe(ByVal x As Word) As Byte
    Result = 0
    If (x And $0300) <> 0 Then
        Result = 1
    End If
End Function
' A LongWord mask in the top byte and the bottom byte.
Function LNe(ByVal x As LongWord) As Byte
    Result = 0
    If (x And $80000004) <> 0 Then
        Result = 1
    End If
End Function
Function LEq(ByVal x As LongWord) As Byte
    Result = 0
    If (x And $80000004) = 0 Then
        Result = 1
    End If
End Function
' Inside a loop condition (jump taken on the other sense).
Function CountBits(ByVal x As Word) As Byte
    Dim n As Byte
    n = 0
    While (x And $FFFF) <> 0
        If (x And 1) <> 0 Then
            n = n + 1
        End If
        x = x >> 1
    Wend
    Result = n
End Function

R0 = B1Ne($10)
R1 = B1Ne($EF)
R2 = B1Eq($10)
R3 = B1Eq($EF)
R4 = BmNe($04)
R5 = BmNe($F3)
R6 = BmEq($04)
R7 = BmEq($F3)
R8 = WNe($0001)
R9 = WNe($7FFE)
R10 = WNe($8000)
R11 = WEq($0001)
R12 = WEq($7FFE)
R13 = WEq($8001)
R14 = WHiNe($0100)
R15 = WHiNe($FCFF)
R16 = LNe($00000004)
R17 = LNe($7FFFFFFB)
R18 = LEq($00000004)
R19 = LEq($7FFFFFFB)
R20 = LNe($80000000)
R21 = LEq($80000000)
R22 = CountBits($0F0F)
R23 = CountBits(0)
End
