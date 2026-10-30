' expect: SIN_R1=1 SIN_R2=2 SIN_R3=3 SIN_R4=300 SIN_R5=7 SIN_R6=1 SIN_R7=104 SIN_R8=9 SIN_R9=5 SIN_R10=6 SIN_R11=1 SIN_R12=0 SIN_R13=101 SIN_R14=1 SIN_R15=1 SIN_R16=1 SIN_R17=1 SIN_R18=120 SIN_R19=12 SIN_R20=1
Program Sin
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Structure Pt
    x As Byte
    y As Word
End Structure
Structure Box
    id As Byte
    tab(3) As Byte
    at As Pt
    flag As Bit
    name As String(4)
    ok As Boolean
End Structure
Structure Status
    Val As Byte
    Enabled As Val.0
    Spare As Val.1
    n As Byte
End Structure
Dim b As Box = (1, 1, 2, 3, 7, 300, 1, "hi", True)
Dim pts(2) As Pt = (9, 100, 5, 200)
Dim names(3) As String(6) = ("one", "two", "")
Dim st As Status = (5, 6)
Dim lines(2) As Box
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Word
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
Dim r17 As Byte
Dim r18 As Byte
Dim r19 As Byte
Dim r20 As Byte
Sub Local()
    Dim q As Pt = (12, 7)
    Dim w(2) As String(3) = ("x", "yz")
    r18 = Byte(w(0)(0))
    r19 = q.x
End Sub
r1 = b.tab(0)
r2 = b.tab(1)
r3 = b.tab(2)
r4 = b.at.y
r5 = b.at.x
r6 = b.flag
r7 = Byte(b.name(0))
r8 = pts(0).x
r9 = pts(1).x
r10 = st.n
r11 = st.Enabled
r12 = st.Spare
r13 = Byte(names(0)(2))
If names(1) = "two" And names(2) = "" Then
    r14 = 1
EndIf
If b.ok Then
    r15 = 1
EndIf
If pts(1).y = 200 Then
    r16 = 1
EndIf
If st.Val = 5 Then
    r17 = 1
EndIf
Local()
r20 = 1
