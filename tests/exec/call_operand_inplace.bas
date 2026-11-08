' x = x op f(): the left operand is read after the call (not saved first) only when the call cannot change it,
' and x = (x op a) op b is updated in place only when no later step reads x or calls something that sees it.
' Covers callees that write the variable directly, through ByRef, or read it; an inlined result sharing an address
' with a callee's frame; zero-extended Byte results; and shift steps.
' expect: T_R0=1005 T_R1=11 T_R2=74 T_R3=58 T_R4=8 T_R5=1100 T_R6=2010 T_R7=3 T_R8=995 T_R9=305419901 T_R10=1234567898 T_R11=48 T_R12=21 T_R13=60
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim G As LongWord
Dim H As Word
Dim R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13 As LongWord

NoInline Function Five() As LongWord
    Result = 5
End Function

' Writes G: `G = G + SetG()` must add to the value G had before the call.
NoInline Function SetG() As LongWord
    G = 100
    Result = 1
End Function

' Reads G: in `G = G + Five() + Twice()` it must see G before the statement changed it.
NoInline Function Twice() As LongWord
    Result = G * 2
End Function

' Writes G after the first step has changed it.
NoInline Function Clobber() As LongWord
    G = 1000
    Result = 3
End Function

NoInline Function ByteRes(ByVal k As Byte) As Byte
    Result = k + 3
End Function

NoInline Function Poke(ByRef q As LongWord) As LongWord
    q = 7
    Result = 100
End Function

' Has locals of its own, so its frame can share addresses with the result of an inlined routine.
NoInline Function Busy(ByVal n As Word) As LongWord
    Dim a, b As LongWord
    a = n
    b = a * 3
    Result = b + 1
End Function

' Called once: inlined into the main program; its locals and result keep their own (overlaid) storage.
Function Once(ByVal n As Word) As LongWord
    Dim t As LongWord
    t = n
    t = t * 2
    Result = t
End Function

G = 1000
G = G + Five()
R0 = G

G = 10
G = G + SetG()
R1 = G

G = 23
G = G + Five() + Twice()
R2 = G

G = 50
G = G + Five() + Clobber()
R3 = G

G = 3
G = G + ByteRes(2)
R4 = G

G = 1000
G = G + Poke(G)
R5 = G

R6 = Once(1000) + Busy(3)

G = $FFFFFF0B
G = G And ByteRes(0)
R7 = G

G = 1000
G = G - ByteRes(2)
R8 = G

G = $12345678
G = G Xor Five() Xor $00000000 Or Five()
R9 = G

G = 1234567890
G = (G >> 1) + (G >> 1) + Five() + ByteRes(0)
R10 = G

H = 100
H = (H >> 1) - 2
R11 = H

H = 40
H = (H << 1) + Five() - 64
R12 = H

R13 = Busy(10) + Busy(5) + Five() + 8
