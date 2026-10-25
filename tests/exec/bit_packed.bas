' expect: BITPK_R1=1 BITPK_R2=0 BITPK_R3=1 BITPK_R4=24 BITPK_R5=69 BITPK_R6=0 BITPK_R7=1 BITPK_R8=0 BITPK_R9=0 BITPK_R10=1
' expect: BITPK_R11=0 BITPK_R12=2 BITPK_R13=1 BITPK_R14=0 BITPK_R15=3 BITPK_R16=22
Program BitPk
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim big(70) As Bit
Dim fl(16) As Boolean
Dim un(8) As Boolean
Dim k As Byte
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
Sub Fill(a() As Boolean)
    a(1) = True
End Sub
Function Local() As Byte
    Dim t(20) As Boolean
    Dim j As Byte
    t(19) = True
    j = 3
    t(j) = True
    t(j + 8) = True
    Result = 0
    If t(19) Then
        Result = Result + 1
    End If
    If t(3) Then
        Result = Result + 1
    End If
    If t(11) Then
        Result = Result + 1
    End If
    If t(4) Then
        Result = Result + 10
    End If
    If t(18) Then
        Result = Result + 10
    End If
End Function
' constant indexes, across byte boundaries
big(0) = 1
big(9) = 1
big(69) = 1
If big(9) = 1 Then
    r1 = 1
End If
If big(8) = 1 Then
    r2 = 1
End If
If big(69) = 1 Then
    r3 = 1
End If
' variable indexes: every third bit
For k = 0 To 69 Step 3
    big(k) = 1
Next
For k = 0 To 69
    If big(k) = 1 Then
        r4 = r4 + 1
        r5 = k
    End If
Next
' clear and toggle through a variable index; the neighbours must not change
k = 33
big(k) = 0
If big(k) = 1 Then
    r6 = 1
End If
If big(k + 3) = 1 Then
    r7 = 1
End If
Toggle(big(k + 3))
If big(k + 3) = 1 Then
    r8 = 1
End If
If big(k + 1) = 1 Then
    r9 = 1
End If
' Boolean array
fl(15) = True
k = 7
fl(k) = True
If fl(7) Then
    r10 = 1
End If
If fl(8) Then
    r11 = 1
End If
For k = 0 To 15
    If fl(k) Then
        r12 = r12 + 1
    End If
Next
' an array passed ByRef keeps one byte per element
Fill(un)
If un(1) Then
    r13 = 1
End If
If un(0) Then
    r14 = 1
End If
' a local packed array
r15 = Local()
' total set bits after the edits above
For k = 0 To 69
    If big(k) = 1 Then
        r16 = r16 + 1
    End If
Next
End
