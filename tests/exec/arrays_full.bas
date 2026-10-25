' expect: ARRFULL_R1=5 ARRFULL_R2=600 ARRFULL_R3=300 ARRFULL_R4=2 ARRFULL_R5=1 ARRFULL_R6=40 ARRFULL_R7=150 ARRFULL_R8=3000
' expect: ARRFULL_R9=3000000 ARRFULL_R10=50 ARRFULL_R11=7 ARRFULL_R12=0 ARRFULL_R13=3 ARRFULL_R14=299 ARRFULL_R15=4 ARRFULL_R16=150
' expect: ARRFULL_R17=299 ARRFULL_R18=10 ARRFULL_R19=8 ARRFULL_R20=1 ARRFULL_R21=1 ARRFULL_R22=32 ARRFULL_R23=26 ARRFULL_R24=1
' expect: ARRFULL_R31=70 ARRFULL_R32=5000 ARRFULL_R33=40 ARRFULL_R34=1 ARRFULL_R35=33 ARRFULL_R36=2013 ARRFULL_R37=110
' expect: ARRFULL_R38=9 ARRFULL_R39=1 ARRFULL_R40=0 ARRFULL_R41=1
' expect: ARRFULL_R25=55 ARRFULL_R26=70000 ARRFULL_R27=4 ARRFULL_R28=0 ARRFULL_R29=5 ARRFULL_R30=300
Program ArrFull
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i8(4) As Byte = (1, 2, 3, 4)
Dim iw(6) As Word = (100, 200, 300, 400, 500, 600)
Dim fl(10) As Boolean
Dim bt(5) As Bit
Dim bb(4) As Byte
Dim cp(5) As Byte
Dim big(300) As Byte
Dim big2(300) As Byte
Const Tbl(5) As Byte = (10, 20, 30, 40, 50)
Const WT(3) As Word = (1000, 2000, 3000)
Const LT(2) As LongWord = (70000, 3000000)
Dim k As Byte
Dim j As Word
Dim r1 As Byte
Dim r2 As Word
Dim r3 As Word
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Byte
Dim r7 As Word
Dim r8 As Word
Dim r9 As LongWord
Dim r10 As Byte
Dim r11 As Byte
Dim r12 As Byte
Dim r13 As Word
Dim r14 As Word
Dim r15 As Word
Dim r16 As Word
Dim r17 As Word
Dim r18 As Byte
Dim r19 As Byte
Dim r20 As Byte
Dim r21 As Byte
Dim r22 As Byte
Dim r23 As Byte
Dim r24 As Byte
Dim r25 As Byte
Dim r26 As LongWord
Dim r27 As Word
Dim r28 As Byte
Dim r29 As Byte
Dim r30 As Word
Dim ones(1) As Byte = (5)
Structure Flg
    V As Byte
    F As V.0
    G As V.3
End Structure
Dim fs(3) As Flg
Dim r38 As Byte
Dim r39 As Byte
Dim r40 As Byte
Dim r41 As Byte
Dim ex As Byte
Dim r31 As Word
Dim r32 As Word
Dim r33 As Byte
Dim r34 As Byte
Dim r35 As Byte
Dim r36 As Word
Dim r37 As Byte
Dim m(3) As Byte = (1, 2, 3)
Dim pts(3) As Word

Function Twice(ByVal x As Word) As Word
    Result = x + x
End Function
Function Last(a() As Byte) As Word
    Result = Bound(a)
End Function
Function Fwd(a() As Byte) As Word
    Result = Last(a)
End Function
Function CLast(ByRefConst a() As Byte) As Word
    Result = Bound(a)
End Function
Function CSum(ByRefConst a() As Byte) As Word
    Dim n As Word
    Dim s As Word
    s = 0
    For n = 0 To Bound(a)
        s = s + a(n)
    Next
    Result = s
End Function
Sub SetAll(a() As Boolean)
    Dim n As Word
    For n = 0 To Bound(a)
        a(n) = True
    Next
End Sub
Function CountTrue(a() As Boolean) As Byte
    Dim n As Word
    Dim c As Byte
    c = 0
    For n = 0 To Bound(a)
        If a(n) Then
            Inc(c)
        EndIf
    Next
    Result = c
End Function
Sub SetB(ByRef x As Byte)
    x.5 = 1
End Sub
Function LocalSum() As Byte
    Dim t(4) As Byte = (5, 6, 7, 8)
    Dim q As Byte
    Dim n As Byte
    q = 0
    For n = 0 To 3
        q = q + t(n)
    Next
    t(0) = 0
    Result = q
End Function
Function LocalBig() As Byte
    Dim t(10) As Byte = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    Dim q As Byte
    Dim n As Byte
    q = 0
    For n = 0 To 9
        q = q + t(n)
    Next
    Result = q
End Function

r1 = i8(0) + i8(3)
r2 = iw(5)
k = 2
r3 = iw(k)
fl(3) = True
k = 5
fl(k) = True
r4 = CountTrue(fl)
k = 4
bt(k) = 1
r5 = bt(k)
k = 3
r6 = Tbl(k)
r7 = 0
For k = 0 To 4
    r7 = r7 + Tbl(k)
Next
k = 2
r8 = WT(k)
k = 1
r9 = LT(k)
cp = Tbl
r10 = cp(4)
big(299) = 7
big2 = big
r11 = big2(299)
Clear(big2)
r12 = big2(299) + big2(1)
r13 = Last(i8)
r14 = Last(big)
r15 = CLast(Tbl)
r16 = CSum(Tbl)
r17 = Fwd(big)
SetAll(fl)
r18 = CountTrue(fl)
k = 2
bb(k).3 = 1
r19 = bb(2)
r20 = bb(k).3
High(bb(k).0)
Toggle(bb(k).3)
r21 = bb(2)
SetB(r22)
r23 = LocalSum()
r23 = LocalSum()
k = 3
r24 = Tbl(k).3
r25 = LocalBig()
r26 = LT(0)
r27 = Last(ones) + 4
ex = 0
fl(2) = False
k = 2
If fl(k) Then
    ex = 1
EndIf
r28 = ex
r29 = ones(0)
r30 = iw(2)
k = 3
j = 1
r31 = Tbl(k) + Tbl(j) + 10
r32 = WT(k - 2) + WT(j + 1)
r33 = Tbl(Tbl(1) / 10 + 1)
If Tbl(k) = 40 Then
    r34 = 1
EndIf
r35 = i8(k) + Tbl(j) + 9
r36 = Twice(WT(j)) - WT(j) + 13
pts(2) = iw(1) + WT(0)
k = 2
r37 = Tbl(m(k) + 1) + Tbl(m(0)) + 40
k = 1
fs(k).F = 1
fs(k).G = 1
r38 = fs(1).V
r39 = fs(k).G
fs(k).G = 0
r40 = fs(k).G
r41 = fs(k).F
