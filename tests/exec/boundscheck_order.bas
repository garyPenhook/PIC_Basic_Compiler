' expect: T_B1=12 T_B2=4 T_B3=123
' expect-O0: T_B1=12 T_B2=4 T_B3=123
' `#option BoundsCheck` keeps the order of evaluation: a call inside a checked index runs where it is written, after
' the operands to its left (`log` records the calls). PIC18 only: the PIC16 back end evaluates a right operand that
' calls a routine first, with or without the option.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#option BoundsCheck = true
Dim b1 As Byte
Dim b2 As Byte
Dim b3 As Byte
Dim arr(5) As Byte
Dim log As Byte
Function F() As Byte
    log = log * 10 + 1
    Result = 1
End Function
Function G() As Byte
    log = log * 10 + 2
    Result = 9
End Function
Function H() As Byte
    log = log * 10 + 3
    Result = 2
End Function
arr(4) = 3
b2 = F() + arr(G())
b1 = log
log = 0
b2 = F() + arr(G())
b3 = 0
log = 0
arr(F() + arr(G()) + H()) = 1
b3 = log
End
