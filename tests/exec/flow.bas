' expect: T_SUM=55 T_DOWN=30 T_STEP3=120 T_W=45 T_R=10 T_SEL1=2 T_SEL2=7 T_SEL3=9 T_SEL4=100 T_BRK=5 T_CNT=8 T_NEST=100 T_GT=7 T_FLAG=1 T_NEG=253 T_BIG=500500
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Byte
Dim sum As Word
Dim down As Integer
Dim step3 As Word
Dim w As Byte
Dim r As Byte
Dim sel1, sel2, sel3, sel4 As Byte
Dim brk, cnt, nest As Byte
Dim j As Byte
Dim gt As Byte
Dim flag As Boolean
Dim neg As ShortInt
Dim big As LongWord
Dim n As Word
Dim lim As Byte
lim = 10
For i = 1 To lim
    sum = sum + i
Next
For i = 1 To 10
    sum = sum + i
Next
sum = sum - 55
For i = 5 To 1 Step -1
    down = down + i * 2
Next
For i = 0 To 30 Step 3
    step3 = step3 + i
Next
step3 = step3 - 45
w = 0
While w < 45
    w = w + 5
Wend
r = 0
Repeat
    r = r + 1
Until r >= 10
i = 2
Select i
    Case 1
        sel1 = 1
    Case 2, 3
        sel1 = 2
    Case Else
        sel1 = 99
End Select
i = 15
Select i
    Case 1 To 5
        sel2 = 1
    Case 6 To 10
        sel2 = 2
    Case > 10
        sel2 = 7
End Select
i = 200
Select i
    Case < 100
        sel3 = 1
    Case Else
        sel3 = 9
End Select
Select i
    Case 200
        sel4 = 100
End Select
For i = 1 To 100
    If i = 6 Then
        Break
    End If
    brk = i
Next
cnt = 0
For i = 1 To 10
    If (i And 1) = 1 Then
        Continue
    End If
    cnt = cnt + 1
    If i > 8 Then
        cnt = cnt + 3
    End If
Next
For i = 1 To 10
    For j = 1 To 10
        nest = nest + 1
    Next
Next
gt = 3
If gt > 5 Then
    gt = 1
ElseIf gt > 2 And gt < 4 Then
    gt = 7
Else
    gt = 2
End If
flag = (gt = 7) And (cnt <> 0) Or False
neg = -3
neg = neg - 0
down = down + 0
For n = 1 To 1000
    big = big + n
Next
GoTo skip
gt = 99
skip:
