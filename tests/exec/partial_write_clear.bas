' A write to part of a local or Result (`w.Byte0 = k`) does not set the rest of it: the entry clear stays. The
' frames of Dirty and the routines after it share addresses, so a missing clear shows as a non-zero high byte.
' Also: a Break in an inner loop does not stop the outer loop's write from counting.
' expect: T_R0=4294967290 T_R1=7 T_R2=4294967290 T_R3=9 T_R4=4294967290 T_R5=11 T_R6=3
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim R0, R1, R2, R3, R4, R5, R6 As LongWord
Dim K As Byte

' Leaves ones in its frame.
NoInline Function Dirty() As LongWord
    Dim a, b As LongWord
    a = $FFFFFFFF
    b = a
    Result = b Xor 5
End Function

NoInline Function LowOnly(ByVal k As Byte) As Word
    Dim w As Word
    w.Byte0 = k
    Result = w
End Function

NoInline Function ResLow(ByVal k As Byte) As LongWord
    Result.Byte0 = k
End Function

NoInline Function Inner(ByVal k As Byte) As Byte
    Dim i, j, x As Byte
    For i = 1 To 3
        x = k
        j = 0
        While j < 10
            If j = 2 Then
                Break
            End If
            j = j + 1
        Wend
    Next
    Result = x + j - 2 - 8
End Function

R0 = Dirty()
R1 = LowOnly(7)
R2 = Dirty()
R3 = ResLow(9)
R4 = Dirty()
K = 19
R5 = Inner(K)
R6 = LowOnly(3)
