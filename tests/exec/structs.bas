' expect: REC_R1=1001 REC_R2=16 REC_R3=513 REC_R4=5 REC_R5=98 REC_R6=3 REC_R7=2 REC_R8=700 REC_R9=77 REC_R10=5
' expect: REC_R11=1001 REC_R12=513 REC_R13=99 REC_R14=1000 REC_R15=5 REC_R16=400 REC_R17=2 REC_R22=1001 REC_R23=4 REC_R24=121
' expect: REC_R25=10 REC_R26=1005 REC_R27=401 REC_R28=120 REC_R18=0 REC_R19=0 REC_R20=0 REC_R21=0 REC_R29=15 REC_R30=4 REC_R31=18 REC_R32=52 REC_R33=4660
Program Rec
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Structure TIn
    A As Byte
    B As Word
End Structure
Structure TPoint
    X As Word
    Y As Word
    Tag As String(4)
    Hist(3) As Byte
    Inner As TIn
End Structure
Structure TFlags
    Val As Byte
    En As Val.0
    Co As Val.1
End Structure
Structure TU
    V As Word
    Lo As V.Byte0
    Hi As V.Byte1
End Structure
Dim u As TU
Dim p, q As TPoint
Dim pts(3) As TPoint
Dim f, g As TFlags
Dim i As Byte
Dim r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 As Word
Dim r11, r12, r13, r14, r15, r16, r17, r18, r19, r20 As Word
Dim r21, r22, r23, r24, r25, r26, r27, r28, r29, r30 As Word
Dim r31, r32, r33 As Word
Sub Bump(ByRef t As TPoint)
    t.X = t.X + 1
    t.Inner.B = 4
    t.Tag = "xy"
    t.Hist(2) = t.Hist(2) + 1
End Sub
Function SumX(ByRef t As TPoint) As Word
    Result = t.X + t.Inner.B
End Function
Function Local() As Word
    Dim l As TIn
    l.A = 3
    l.B = 12
    Result = l.B + l.A
End Function

p.X = 1000
p.Y = p.X + 1
r1 = p.Y
p.Hist(1) = 7
i = 2
p.Hist(i) = 9
r2 = p.Hist(1) + p.Hist(2)
p.Inner.B = 513
p.Inner.A = 5
r3 = p.Inner.B
r4 = p.Inner.A
p.Tag = "abc"
r5 = Byte(p.Tag(1))
f.Val = 0
f.En = 1
f.Co = 1
r6 = f.Val
f.Val = 0
f.Co = 1
r7 = f.Val
pts(1).X = 300
pts(i).X = 400
pts(i).Inner.B = 77
pts(i).Hist(i) = 5
r8 = pts(1).X + pts(2).X
r9 = pts(2).Inner.B
r10 = pts(2).Hist(2)
q = p
r11 = q.Y
r12 = q.Inner.B
r13 = Byte(q.Tag(2))
pts(0) = p
r14 = pts(0).X
i = 1
pts(i) = pts(2)
r15 = pts(1).Hist(2)
r16 = pts(1).X
g = f
r17 = g.Val
Bump(p)
r22 = p.X
r23 = p.Inner.B
r24 = Byte(p.Tag(1))
r25 = p.Hist(2)
r26 = SumX(p)
Bump(pts(i))
r27 = pts(1).X
r28 = Byte(pts(1).Tag(0))
Clear(q)
r18 = q.X
r19 = q.Inner.B
Clear(pts)
r20 = pts(2).X
Clear(f)
r21 = f.Val
r29 = p.Hist(2) + 5
r30 = Local() - 11
u.Lo = 52
u.Hi = 18
r31 = u.Hi
r32 = u.Lo
r33 = u.V
