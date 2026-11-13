' expect: SP_SP_R1=5 SP_SP_R2=0 SP_SP_R3=1 SP_SP_R4=1 SP_SP_R5=2 SP_SP_R6=3 SP_SP_A1=19 SP_SP_A2=17 SP_SP_A3=200 SP_SP_C=3 SP_SP_TOT=147 SP_SP_W1=1300 SP_SP_W2=700 SP_SP_Q1=7 SP_SP_Q2=9 SP_SP_OK=1
' Calls that pass different constants get a copy of the routine each (opt::specialize_best), and a routine that only
' returns a constant folds at its call. Everything below must give what the shared routine gave: validation results,
' side effects in the routine, a Byte and a Word parameter, a result used in a condition, a copy that calls another
' routine with a constant, a call whose argument is a variable, and a routine that writes its parameter.
Program Sp
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim calls As Byte
Dim sp_r1 As Byte
Dim sp_r2 As Byte
Dim sp_r3 As Byte
Dim sp_r4 As Byte
Dim sp_r5 As Byte
Dim sp_r6 As Byte
Dim sp_a1 As Byte
Dim sp_a2 As Byte
Dim sp_a3 As Byte
Dim sp_c As Byte
Dim sp_tot As Word
Dim sp_w1 As Word
Dim sp_w2 As Word
Dim sp_q1 As Byte
Dim sp_q2 As Byte
Dim sp_ok As Byte
Dim v As Byte
Dim i As Byte
Dim lim As Byte = 7

Function PinOk(ByVal pin As Byte) As Boolean
    Result = False
    If pin <= 5 And pin <> 3 Then
        Result = True
    End If
    If pin >= 16 And pin <= 21 Then
        Result = True
    End If
End Function

Function Bump(ByVal n As Byte) As Byte
    calls = calls + 1
    Result = n
End Function

Function Scale(ByVal k As Byte, ByVal x As Word) As Word
    If k = 1 Then
        Result = x
    ElseIf k = 2 Then
        Result = x + x
    Else
        Result = x + x + x
    End If
End Function

Function Pick(ByVal ch As Byte, ByVal pin As Byte) As Byte
    Result = 0
    If Not PinOk(pin) Then
        Exit
    End If
    If ch = 1 Then
        Result = pin + 1
    ElseIf ch = 2 Then
        Result = pin + 2
    Else
        Result = pin
    End If
End Function

Function Count(ByVal n As Byte) As Byte
    Dim t As Byte
    t = 0
    While n > 0
        t = t + 2
        n = n - 1
    Wend
    Result = t
End Function

' A routine that writes its parameter is not given copies.
Function Twice(ByVal n As Byte) As Byte
    n = n + n
    Result = n
End Function

sp_r1 = Bump(5)
sp_r2 = Bump(0)
' constant results of validation
If PinOk(4) Then
    sp_r3 = 1
End If
If Not PinOk(3) Then
    sp_r4 = 1
End If
If PinOk(18) And Not PinOk(30) Then
    sp_r5 = 2
End If
sp_r6 = calls + 1
sp_a1 = Pick(1, 18)
sp_a2 = Pick(2, 15)
sp_a2 = sp_a2 + 17
sp_a3 = Pick(3, 200) + 200
v = 4
sp_c = Count(1) + 1
sp_tot = Count(v) + Count(7) + Count(lim)
sp_tot = sp_tot + 111
sp_w1 = Scale(2, 650)
sp_w2 = Scale(1, 700)
sp_q1 = Twice(3) + 1
sp_q2 = Twice(4) + 1
sp_ok = 1
