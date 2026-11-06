' expect: GS_R1=10 GS_R2=730 GS_R3=5 GS_R4=3 GS_R5=30 GS_R6=6 GS_R7=2 GS_R8=64 GS_R9=18 GS_R10=1 GS_R11=11
Program Gs
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim big(300) As Byte
Dim x As Byte
Dim acc As Word
Dim far As Word
Dim cnt As Byte
Dim r1 As Byte
Dim r2 As Word
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Word
Dim r6 As Byte
Dim r7 As Byte
Dim r8 As Word
Dim r9 As Word
Dim r10 As Byte
Dim r11 As Byte

Function Twice(v As Byte) As Byte
    Result = v + v
End Function

Sub Work()
    Dim a As Byte
    Dim t As Word
    a = 3
    t = 0
    GoSub Bump
    GoSub Bump
    GoSub Bump
    r5 = t
    r6 = a
    Exit
Bump:
    ' a subroutine that changes locals of the routine and calls a function
    a = a + 1
    t = t + Twice(a)
    Return
End Sub

Sub Pick(n As Byte)
    r7 = 0
    On n GoSub One, Two
    Exit
One:
    r7 = r7 + 1
    Return
Two:
    r7 = r7 + 2
    Return
End Sub

' constants known before a GoSub are not known after it
x = 5
GoSub Dbl
r1 = x
' the subroutine runs in another bank, then main reads a variable of a third
far = 700
big(299) = 9
acc = 0
GoSub Bank2
r2 = acc
r3 = big(299) - 2
' nested subroutines and a loop
cnt = 0
GoSub Outer
r4 = cnt
' early Return, taken or not
x = 0
GoSub Early
r8 = far
x = 1
GoSub Early
r9 = far
Work()
Pick(1)
r10 = 1
r11 = Twice(5) + 1
GoTo Done

Dbl:
x = x + x
Return

Bank2:
acc = acc + far
acc = acc + 20
acc = acc + big(299) + 1
big(299) = big(299) - 2
Return

Outer:
GoSub Inner
GoSub Inner
GoSub Inner
Return
Inner:
cnt = cnt + 1
Return

Early:
far = 64
If x = 0 Then
    Return
EndIf
far = far - 46
Return

Done:
