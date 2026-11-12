' A leaf routine that ends `Result = p`, `p` a ByVal parameter, returns its value in the parameter itself
' (`opt::coalesce_results`). Byte (argument in W), Word and LongWord; a call as the argument of the same routine,
' two calls in one expression, a parameter the routine changes first, and routines that are not leaves or that
' read `Result` (which keep the copy).
' expect: T_R0=12 T_R1=48 T_R2=34 T_R3=21 T_R4=6 T_R5=300000 T_R6=77 T_R7=9 T_R8=40 T_R9=1010 T_G=84
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim R0, R1, R2, R3, R4, R5, R6, R7, R8, R9 As LongWord
Dim a, b As Byte
Dim w As Word
Dim g As Byte

Function Dbl(ByVal x As Byte) As Byte
    x = x + x
    Result = x
End Function

Function Gcd(ByVal m As Word, ByVal n As Word) As Word
    Dim t As Word
    While n <> 0
        t = m Mod n
        m = n
        n = t
    Wend
    Result = m
End Function

Function Tri(ByVal v As LongWord) As LongWord
    v = v * 3
    Result = v
End Function

' Unchanged parameter handed straight back.
Function Same(ByVal x As Byte) As Byte
    Result = x
End Function

' Not a leaf: it calls Dbl.
Function Quad(ByVal x As Byte) As Byte
    x = Dbl(Dbl(x))
    Result = x
End Function

' Reads Result before the copy.
Function Mix(ByVal x As Word) As Word
    Result = 10
    x = x + Result
    Result = x
End Function

' The parameter is a loop variable and the result: it keeps the last value the loop gave it.
Function LastOf(ByVal n As Byte) As Byte
    Dim s As Byte
    For n = 3 To 9
        s = s + 1
    Next
    Result = n
End Function

' The same with a body that reads the loop variable, so the loop is not turned into a count of passes: the
' variable is the result, so the loop may not step it past the limit (`opt::free_loop_ends`).
Function LastRead(ByVal n As Byte) As Byte
    For n = 3 To 9
        g = g + n
    Next
    Result = n
End Function

a = 6
b = 3
R0 = Dbl(a)
R1 = Dbl(Dbl(Dbl(a)))
R2 = Dbl(a) + Dbl(b) + Dbl(8)
R3 = Gcd(1071, 462)
R4 = Gcd(Gcd(48, 18), 30)
R5 = Tri(100000)
R6 = Same(77)
R7 = Same(Same(b)) + Dbl(b)
R8 = Quad(10)
w = 1000
R9 = Mix(w)
R0 = R0 + LastOf(1) - 9
R6 = R6 + LastOf(2) - 9
R1 = R1 + LastRead(1) - 9
R2 = R2 + LastRead(2) - 9
