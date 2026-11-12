' expect: T_R1=-400 T_R2=-969997 T_R3=300 T_R4=71 T_R5=1 T_R6=-300 T_R7=-4 T_R8=70 T_R9=1002 T_R10=-71100 T_R11=14560 T_R12=17504 T_R13=-600 T_R14=1600 T_R15=6 T_R16=-279 T_R17=-900000 T_R18=105792 T_R19=244 T_R20=400 T_R21=-3100 T_R22=-3100 T_R23=-3100 T_R24=-200 T_R25=3 T_R26=14560 T_R27=3
' expect-O0: T_R1=-400 T_R2=-969997 T_R3=300 T_R4=71 T_R5=1 T_R6=-300 T_R7=-4 T_R8=70 T_R9=1002 T_R10=-71100 T_R11=14560 T_R12=17504 T_R13=-600 T_R14=1600 T_R15=6 T_R16=-279 T_R17=-900000 T_R18=105792 T_R19=244 T_R20=400 T_R21=-3100 T_R22=-3100 T_R23=-3100 T_R24=-200 T_R25=3 T_R26=14560 T_R27=3
' Streaming array loops: Byte, Word and Long elements walked by FSR0/FSR1 with POSTINC / POSTDEC, arr(i + k), and the
' shapes that must keep the indexed code (an element named twice, a branch, a third array).
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim w(8) As Integer
Dim w2(8) As Integer
Dim w3(8) As Integer
Dim uw(4) As Word
Dim l(4) As LongInt
Dim l2(4) As LongInt
Dim b(8) As Byte
Dim c(8) As Byte
Dim d(8) As Byte
Dim i As Byte
Dim s As LongInt
Dim r1 As LongInt
Dim r2 As LongInt
Dim r3 As Integer
Dim r4 As Integer
Dim r5 As Integer
Dim r6 As LongInt
Dim r7 As Integer
Dim r8 As Integer
Dim r9 As Integer
Dim r10 As LongInt
Dim r11 As Integer
Dim r12 As Integer
Dim r13 As LongInt
Dim r14 As LongInt
Dim r15 As Byte
Dim r16 As Integer
Dim r17 As LongInt
Dim r18 As LongInt
Dim r19 As Integer
Dim r20 As Integer
Dim r21 As LongInt
Dim r22 As LongInt
Dim r23 As Integer
Dim r24 As Integer
Dim r25 As Byte
Dim r26 As Integer
Dim r27 As Integer

Sub Init()
    w(0) = 100
    w(1) = -200
    w(2) = 300
    w(3) = -400
    w(4) = 500
    w(5) = -600
    w(6) = 700
    w(7) = -800
    l(0) = 100000
    l(1) = -70000
    l(2) = 3
    l(3) = -1000000
    uw(0) = 65535
    uw(1) = 256
    uw(2) = 1
    uw(3) = 40000
    b(0) = 10
    b(1) = 20
    b(2) = 30
    b(3) = 40
    b(4) = 50
    b(5) = 60
    b(6) = 70
    b(7) = 250
    For i = 0 To 7
        w2(i) = i + 1
    Next
End Sub

Init()

' R1: Integer elements summed into a Long
s = 0
For i = 0 To 7
    s = s + w(i)
Next
r1 = s

' R2: Long elements
s = 0
For i = 0 To 3
    s = s + l(i)
Next
r2 = s

' R3: two Byte arrays in one loop
For i = 0 To 7
    c(i) = b(i)
Next
r3 = c(0)
r3 = r3 + c(3)
r3 = r3 + c(7)

' R4: shift up by one element, counting down (the Fir history shift)
For i = 7 To 1 Step -1
    w2(i) = w2(i - 1)
Next
r4 = w2(7) * 10 + w2(1)
r5 = w2(0)

' R6: Integer element read at i + 2
s = 0
For i = 0 To 5
    s = s + w(i + 2)
Next
r6 = s

' R7: a constant written to Integer and to Long elements
For i = 0 To 7
    w3(i) = -2
Next
r7 = w3(0) + w3(7)
For i = 0 To 3
    l2(i) = 70000
Next
r8 = Integer(l2(3) / 1000)

' R9: an expression written
For i = 0 To 7
    w3(i) = w(i) * 2 + 1
Next
r9 = w3(1) + w3(6)

' R10: counting down over the Integer array
s = 0
For i = 7 To 0 Step -1
    s = s * 2 + w(i)
Next
r10 = s

' R11: a Byte taken from an Integer element (a narrow read)
For i = 0 To 7
    d(i) = Byte(w(i))
Next
r11 = d(1)
r11 = r11 * 256 + d(7)

' R12: an Integer taken from a Long element
For i = 0 To 3
    w3(i) = Integer(l(i))
Next
r12 = w3(0) + w3(3)

' R13: an element named twice keeps the indexed code
For i = 0 To 7
    w3(i) = w(i) + w(i)
Next
r13 = w3(2) + w3(5)

' R14: a branch keeps the indexed code
s = 0
For i = 0 To 7
    If w(i) > 0 Then
        s = s + w(i)
    End If
Next
r14 = s

' R15: the loop variable read in the body, and after the loop
s = 0
For i = 1 To 6
    s = s + w(i - 1) + i
Next
r15 = i
r16 = s

' R17: Long elements copied counting down
For i = 3 To 0 Step -1
    l2(i) = l(i)
Next
r17 = l2(0) + l2(3)

' R18: Word elements, the high bit set
s = 0
For i = 0 To 3
    s = s + uw(i)
Next
r18 = s

' R19: three arrays in one loop keep the indexed code
For i = 0 To 7
    d(i) = b(i) + c(i)
Next
r19 = d(7)

' R20: a start above zero, an element behind the variable
s = 0
For i = 3 To 5
    s = s + w(i - 1)
Next
r20 = s

' R21: two Integer arrays multiplied into a Long (the FIR dot product), counting up and down
s = 0
For i = 0 To 7
    s = s + w(i) * w2(i)
Next
r21 = s
s = 0
For i = 7 To 0 Step -1
    s = s + w(i) * w2(i)
Next
r22 = s

' R23: the same into an Integer
r23 = 0
For i = 0 To 7
    r23 = r23 + w(i) * w2(i)
Next

' R24: the variable is read after the loop, so it keeps counting normally
r24 = 0
For i = 0 To 3
    r24 = r24 + w(i)
Next
r25 = i

' R26: a narrow read counting down
For i = 7 To 0 Step -1
    d(i) = Byte(w(i))
Next
r26 = d(1)
r26 = r26 * 256 + d(7)

' R27: a Long element read as an Integer counting down
For i = 3 To 0 Step -1
    w3(i) = Integer(l(i))
Next
r27 = w3(2)
End
