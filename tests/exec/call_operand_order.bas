' Cases the in-place forms of x = x op f() must leave alone: a callee that writes the variable through FSR0
' (INDF0), calls whose order a commutative flip would change, a later step that reads the variable through
' a ByRef parameter, and Result coalescing next to an early Exit and a read of Result.
' expect: T_R0=1001 T_R1=999 T_R2=21 T_R3=7 T_R4=0 T_R5=12 T_R6=3
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim G As LongWord
Dim C As LongWord
Dim W As Word
Dim R0, R1, R2, R3, R4, R5, R6 As LongWord

' Writes the low byte of G through FSR0: G = G + Sneak() must add to the value G had before the call.
Function Sneak() As LongWord
    FSR0 = @G
    INDF0 = 7
    Result = 1
End Function

Function Nxt() As LongWord
    C = C + 1
    Result = C
End Function

Sub AddRef(ByRef q As Word)
    W = (W + 1) + q
End Sub

' Ends with Result = t, but may leave early with Result still 0.
Function Early(ByVal k As Byte) As LongWord
    Dim t As LongWord
    t = 7
    If k = 0 Then
        Exit
    End If
    Result = t
End Function

' Reads Result before the final copy.
Function ReadsRes(ByVal k As Byte) As LongWord
    Dim t As LongWord
    Result = k
    t = Result + 5
    Result = t
End Function

' A local set on one path only: its entry clear must stay.
Function OnePath(ByVal k As Byte) As Byte
    Dim t As Byte
    If k > 2 Then
        t = k
    End If
    Result = t
End Function

G = 1000
G = G + Sneak()
R0 = G

G = 1000
C = 0
G = Nxt() + (G - Nxt())
R1 = G

W = 10
AddRef(W)
R2 = W

R3 = Early(1)
R4 = Early(0)
R5 = ReadsRes(7)
R6 = OnePath(3) + OnePath(1)
