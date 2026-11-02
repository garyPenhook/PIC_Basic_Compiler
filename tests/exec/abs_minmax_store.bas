' Abs and Min/Max assigned straight to a variable: in place (x = Abs(x), a = Max(a, b), b = Min(a, b)), to another
' variable, and with a constant operand; Integer, LongInt, Word and ShortInt. Run-time arguments (two or more different
' values per routine) so the optimiser cannot fold them.
' expect: T_R0=32767 T_R1=256 T_R2=1 T_R3=0 T_R4=5 T_R5=300 T_R6=256 T_R7=1 T_R8=7
' expect: T_R9=100000 T_R10=65536 T_R11=1 T_R12=70000 T_R13=100 T_R14=7 T_R15=5 T_R16=5 T_R17=-200
' expect: T_R18=256 T_R19=0 T_R20=-3 T_R21=-3 T_R22=-300 T_R23=255 T_R24=5 T_R25=5 T_R26=-3
' expect: T_R27=-3 T_R28=5 T_R29=5 T_R30=-200 T_R31=-3 T_R32=-300 T_R33=-3 T_R34=4 T_R35=2
' expect: T_R36=5 T_R37=300 T_R38=60000 T_R39=7 T_R40=7 T_R41=5 T_R42=70000 T_R43=100 T_R44=100
' expect: T_R45=3 T_R46=-5 T_R47=-5 T_R48=-3 T_R49=-3
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim R0 As Integer
Dim R1 As Integer
Dim R2 As Integer
Dim R3 As Integer
Dim R4 As Integer
Dim R5 As Integer
Dim R6 As Integer
Dim R7 As Integer
Dim R8 As Integer
Dim R9 As LongInt
Dim R10 As LongInt
Dim R11 As LongInt
Dim R12 As LongInt
Dim R13 As ShortInt
Dim R14 As ShortInt
Dim R15 As Integer
Dim R16 As Integer
Dim R17 As Integer
Dim R18 As Integer
Dim R19 As Integer
Dim R20 As Integer
Dim R21 As Integer
Dim R22 As Integer
Dim R23 As Integer
Dim R24 As Integer
Dim R25 As Integer
Dim R26 As Integer
Dim R27 As Integer
Dim R28 As Integer
Dim R29 As Integer
Dim R30 As Integer
Dim R31 As Integer
Dim R32 As Integer
Dim R33 As Integer
Dim R34 As Integer
Dim R35 As Integer
Dim R36 As Integer
Dim R37 As Word
Dim R38 As Word
Dim R39 As Word
Dim R40 As Word
Dim R41 As LongInt
Dim R42 As LongInt
Dim R43 As ShortInt
Dim R44 As ShortInt
Dim R45 As ShortInt
Dim R46 As ShortInt
Dim R47 As ShortInt
Dim R48 As ShortInt
Dim R49 As ShortInt

Function AbsI(ByVal x As Integer) As Integer
    x = Abs(x)
    Result = x
End Function
Function AbsTo(ByVal x As Integer) As Integer
    Dim d As Integer
    d = Abs(x)
    Result = d
End Function
Function AbsL(ByVal x As LongInt) As LongInt
    x = Abs(x)
    Result = x
End Function
Function AbsLTo(ByVal x As LongInt) As LongInt
    Dim d As LongInt
    d = Abs(x)
    Result = d
End Function
Function AbsS(ByVal x As ShortInt) As ShortInt
    x = Abs(x)
    Result = x
End Function
Function MaxIn(ByVal a As Integer, ByVal b As Integer) As Integer
    a = Max(a, b)
    Result = a
End Function
Function MinIn(ByVal a As Integer, ByVal b As Integer) As Integer
    a = Min(a, b)
    Result = a
End Function
Function MaxSecond(ByVal a As Integer, ByVal b As Integer) As Integer
    b = Max(a, b)
    Result = b
End Function
Function MinSecond(ByVal a As Integer, ByVal b As Integer) As Integer
    b = Min(a, b)
    Result = b
End Function
Function MaxTo(ByVal a As Integer, ByVal b As Integer) As Integer
    Dim d As Integer
    d = Max(a, b)
    Result = d
End Function
Function MinTo(ByVal a As Integer, ByVal b As Integer) As Integer
    Dim d As Integer
    d = Min(a, b)
    Result = d
End Function
Function MaxK(ByVal a As Integer) As Integer
    a = Max(a, -3)
    Result = a
End Function
Function MinK(ByVal a As Integer) As Integer
    a = Min(5, a)
    Result = a
End Function
Function MaxW(ByVal a As Word, ByVal b As Word) As Word
    a = Max(a, b)
    Result = a
End Function
Function MinWTo(ByVal a As Word, ByVal b As Word) As Word
    Dim d As Word
    d = Min(a, b)
    Result = d
End Function
Function MaxL(ByVal a As LongInt, ByVal b As LongInt) As LongInt
    a = Max(a, b)
    Result = a
End Function
Function MaxS(ByVal a As ShortInt, ByVal b As ShortInt) As ShortInt
    a = Max(a, b)
    Result = a
End Function
Function MinSTo(ByVal a As ShortInt, ByVal b As ShortInt) As ShortInt
    Dim d As ShortInt
    d = Min(a, b)
    Result = d
End Function
Function MinS(ByVal a As ShortInt, ByVal b As ShortInt) As ShortInt
    a = Min(a, b)
    Result = a
End Function

R0 = AbsI(-32767)
R1 = AbsI(-256)
R2 = AbsI(1)
R3 = AbsI(0)
R4 = AbsI(-5)
R5 = AbsI(300)
R6 = AbsTo(-256)
R7 = AbsTo(-1)
R8 = AbsTo(7)
R9 = AbsL(-100000)
R10 = AbsL(-65536)
R11 = AbsL(1)
R12 = AbsLTo(-70000)
R13 = AbsS(-100)
R14 = AbsS(7)
R15 = MaxIn(5, -3)
R16 = MaxIn(-3, 5)
R17 = MaxIn(-300, -200)
R18 = MaxIn(256, 255)
R19 = MaxIn(-1, 0)
R20 = MinIn(5, -3)
R21 = MinIn(-3, 5)
R22 = MinIn(-200, -300)
R23 = MinIn(255, 256)
R24 = MaxSecond(5, -3)
R25 = MaxSecond(-3, 5)
R26 = MinSecond(5, -3)
R27 = MinSecond(-3, 5)
R28 = MaxTo(5, -3)
R29 = MaxTo(-3, 5)
R30 = MaxTo(-200, -300)
R31 = MinTo(5, -3)
R32 = MinTo(-300, -200)
R33 = MaxK(-10)
R34 = MaxK(4)
R35 = MinK(2)
R36 = MinK(9)
R37 = MaxW(300, 7)
R38 = MaxW(7, 60000)
R39 = MinWTo(60000, 7)
R40 = MinWTo(7, 60000)
R41 = MaxL(-70000, 5)
R42 = MaxL(70000, 5)
R43 = MaxS(100, -5)
R44 = MaxS(-5, 100)
R45 = MaxS(-128, 3)
R46 = MinSTo(100, -5)
R47 = MinSTo(-5, 100)
R48 = MinS(3, -3)
R49 = MinS(-3, 3)
End
