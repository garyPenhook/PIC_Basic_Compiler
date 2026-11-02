' expect: BFT_R1=5 BFT_R2=1 BFT_R3=9 BFT_R4=17 BFT_R5=6 BFT_R6=6 BFT_R7=1 BFT_R8=9 BFT_R9=0 BFT_R10=1 BFT_R11=31 BFT_R12=6 BFT_R13=2 BFT_R14=1 BFT_R15=0 BFT_R16=8 BFT_R17=223 BFT_R18=3 BFT_R19=15 BFT_R20=4 BFT_R21=0 BFT_R22=21 BFT_R23=5 BFT_R24=1 BFT_R25=1 BFT_R26=0 BFT_R27=77 BFT_R28=3 BFT_R29=3 BFT_R30=7 BFT_R31=21 BFT_R32=1 BFT_R33=9 BFT_R34=7 BFT_R35=200 BFT_R36=12 BFT_R37=113
Program Bft
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
' Bits(n) structure fields: packed from bit 0, never straddling a byte.
Structure TCtl
    Mode As Bits(3)
    Run As Bits(1)
    Gain As Bits(4)
    Level As Bits(5)
    Hi As Bits(3)
    Spare As Byte
    Whole As Bits(8)
    Raw0 As Mode.Byte0
    Raw1 As Level.Byte0
End Structure
Dim c As TCtl
Dim a(2) As TCtl
Dim ix As Byte
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
Dim r17 As Byte
Dim r18 As Byte
Dim r19 As Byte
Dim r20 As Byte
Dim r21 As Byte
Dim r22 As Byte
Dim r23 As Byte
Dim r24 As Byte
Dim r25 As Byte
Dim r26 As Byte
Dim r27 As Byte
Dim r28 As Byte
Dim r29 As Byte
Dim r30 As Byte
Dim r31 As Byte
Dim r32 As Byte
Dim r33 As Byte
Dim r34 As Byte
Dim r35 As Byte
Dim r36 As Byte
Dim r37 As Byte
' a function that changes one field of the structure while its result goes into another
Function Touch() As Byte
    c.Level = 12
    Result = 9
End Function
Function Local() As Byte
    Dim l As TCtl
    l.Gain = 2
    l.Mode = 7
    Inc(l.Gain, 15)
    Result = l.Gain + l.Mode * 16
End Function
Sub SetIt(ByRef t As TCtl, ByVal n As Byte)
    t.Level = n
    t.Hi = n
End Sub
Function GetGain(ByRef t As TCtl) As Byte
    Result = t.Gain
End Function
c.Mode = 5
c.Run = 1
c.Gain = 9
c.Level = 17
c.Hi = 6
c.Spare = 77
r1 = c.Mode
r2 = c.Run
r3 = c.Gain
r4 = c.Level
r5 = c.Hi
Inc(c.Mode)
r6 = c.Mode
r7 = c.Run
r8 = c.Gain
' a carry out of the field is dropped, not added to the neighbour
Inc(c.Mode, 2)
r9 = c.Mode
r10 = c.Run
Dec(c.Level, 18)
r11 = c.Level
r12 = c.Hi
k = 11
c.Gain = k + 7
r13 = c.Gain
r14 = c.Run
Clear(c.Gain)
r15 = c.Gain
r16 = c.Raw0
r17 = c.Raw1
ix = 1
a(ix).Mode = 3
a(ix).Gain = 15
a(0).Gain = 4
r18 = a(1).Mode
r19 = a(ix).Gain
r20 = a(0).Gain
r21 = a(0).Mode
SetIt(c, 21)
r22 = c.Level
r23 = c.Hi
Select c.Level
    Case 21
        r24 = 1
    Else
        r24 = 2
EndSelect
If c.Run = 1 Then
    r25 = 1
EndIf
Toggle(c.Run)
r26 = c.Run
r27 = c.Spare
c.Gain = 3
r28 = GetGain(c)
r29 = c.Gain
' a bit of a field counts from the field's own bit 0
c.Hi.1 = 1
r30 = c.Hi
r31 = c.Level
r32 = c.Hi.2
' the call changes Level, and the store of Gain must not undo that
c.Gain = Touch()
r33 = c.Gain
r34 = c.Hi
c.Whole = 200
r35 = c.Whole
r36 = c.Level
r37 = Local()
End
