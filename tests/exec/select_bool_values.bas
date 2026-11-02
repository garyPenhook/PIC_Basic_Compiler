' Select on a plain variable compares it in place (no hidden copy); a Word range with a computed left side folds its
' upper bound into the compare; a flag test as a value (x = 3, x > 4) is movlw 0 / btfsc STATUS / movlw 1; And, Or and Not
' of Boolean variables as a value are bitwise. Run-time arguments so the optimiser cannot fold them.
' expect: T_R0=10 T_R1=20 T_R2=20 T_R3=0 T_R4=30 T_R5=30 T_R6=40 T_R7=0 T_R8=0
' expect: T_R9=1 T_R10=2 T_R11=2 T_R12=3 T_R13=3 T_R14=3 T_R15=3 T_R16=2 T_R17=3
' expect: T_R18=99 T_R19=7 T_R20=1 T_R21=2 T_R22=3
' expect: T_R23=1 T_R24=0 T_R25=0 T_R26=1 T_R27=1 T_R28=0 T_R29=0 T_R30=1 T_R31=1 T_R32=0 T_R33=1 T_R34=0
' expect: T_R35=1 T_R36=0 T_R37=0 T_R38=0 T_R39=1 T_R40=1 T_R41=1 T_R42=0 T_R43=1 T_R44=0
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
Dim R23 As Boolean
Dim R24 As Boolean
Dim R25 As Boolean
Dim R26 As Boolean
Dim R27 As Boolean
Dim R28 As Boolean
Dim R29 As Boolean
Dim R30 As Boolean
Dim R31 As Boolean
Dim R32 As Boolean
Dim R33 As Boolean
Dim R34 As Boolean
Dim R35 As Boolean
Dim R36 As Boolean
Dim R37 As Boolean
Dim R38 As Boolean
Dim R39 As Boolean
Dim R40 As Boolean
Dim R41 As Boolean
Dim R42 As Boolean
Dim R43 As Boolean
Dim R44 As Boolean
Dim G As Byte
Dim GW As Word

Function SelA(ByVal x As Byte) As Byte
    Dim r As Byte
    r = 0
    Select x
        Case 1
            r = 10
        Case 2, 3
            r = 20
        Case 5 To 9
            r = 30
        Case > 100
            r = 40
        Case Else
            r = 0
    EndSelect
    Result = r
End Function

Function SelW(ByVal w As Word) As Byte
    Dim r As Byte
    Select w
        Case 1000
            r = 1
        Case 2000 To 3000
            r = 2
        Case Else
            r = 3
    EndSelect
    Result = r
End Function

' The selector written by a case body.
Function SelSelf(ByVal x As Byte) As Byte
    Select x
        Case 1
            x = 2
        Case 2
            x = 99
        Case Else
            x = 7
    EndSelect
    Result = x
End Function

' A global selector, and a call in a case body.
Sub Bump()
    G = G + 1
End Sub
Function SelGlobal() As Byte
    Dim r As Byte
    r = 0
    Select G
        Case 1
            Bump()
            r = 1
        Case 2
            r = 2
        Case Else
            r = 3
    EndSelect
    Result = r
End Function

Function IsThree(ByVal x As Byte) As Boolean
    Dim f As Boolean
    f = (x = 3)
    Result = f
End Function
Function IsOver4(ByVal x As Byte) As Boolean
    Dim f As Boolean
    f = x > 4
    Result = f
End Function
Function IsNeg(ByVal x As ShortInt) As Boolean
    Dim f As Boolean
    f = x < 0
    Result = f
End Function
Function AndB(ByVal a As Boolean, ByVal b As Boolean) As Boolean
    Dim r As Boolean
    r = a And b
    Result = r
End Function
Function OrB(ByVal a As Boolean, ByVal b As Boolean) As Boolean
    Dim r As Boolean
    r = a Or b
    Result = r
End Function
Function NotB(ByVal a As Boolean) As Boolean
    Dim r As Boolean
    r = Not a
    Result = r
End Function

R0 = SelA(1)
R1 = SelA(2)
R2 = SelA(3)
R3 = SelA(4)
R4 = SelA(5)
R5 = SelA(9)
R6 = SelA(101)
R7 = SelA(10)
R8 = SelA(100)
R9 = SelW(1000)
R10 = SelW(2000)
R11 = SelW(3000)
R12 = SelW(3001)
R13 = SelW(1999)
R14 = SelW(0)
R15 = SelW(65535)
R16 = SelW(2500)
R17 = SelW(1001)
R18 = SelSelf(2)
R19 = SelSelf(5)
G = 1
R20 = SelGlobal()
R21 = SelGlobal()
G = 9
R22 = SelGlobal()
R23 = IsThree(3)
R24 = IsThree(4)
R25 = IsOver4(4)
R26 = IsOver4(5)
R27 = IsOver4(255)
R28 = IsNeg(0)
R29 = IsNeg(5)
R30 = IsNeg(-1)
R31 = IsNeg(-128)
R32 = IsNeg(127)
R33 = AndB(True, True)
R34 = AndB(True, False)
R35 = OrB(False, True)
R36 = OrB(False, False)
R37 = AndB(False, True)
R38 = NotB(True)
R39 = NotB(False)
R40 = OrB(True, False)
R41 = OrB(True, True)
R42 = AndB(False, False)
R43 = NotB(R38)
R44 = NotB(R43)
End
