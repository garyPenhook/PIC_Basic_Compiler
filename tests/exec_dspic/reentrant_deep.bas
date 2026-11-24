' expect: RD_ACK=9 RD_MOVES=1023 RD_FS=55 RD_LW=479001600 RD_ARR=36 RD_SEEN=20
' Recursion on the dsPIC33: Ackermann (two parameters, nested recursive calls), towers of Hanoi (ten discs: 1023 moves,
' depth ten), a Float and a LongWord result and a recursive routine that walks a ByRef array. The
Program Rd
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW

Dim ack As Word
Dim moves As Word
Dim fs As Integer
Dim lw As LongWord
Dim arr As Integer
Dim seen As Byte
Dim data(8) As Integer
Dim i As Byte

Reentrant Function Ackermann(ByVal m As Word, ByVal n As Word) As Word
    If m = 0 Then
        Result = n + 1
    ElseIf n = 0 Then
        Result = Ackermann(m - 1, 1)
    Else
        Result = Ackermann(m - 1, Ackermann(m, n - 1))
    End If
End Function

Reentrant Sub Hanoi(ByVal n As Byte, ByVal a As Byte, ByVal b As Byte, ByVal c As Byte)
    If n > 0 Then
        Hanoi(n - 1, a, c, b)
        Inc(moves)
        Hanoi(n - 1, c, b, a)
    End If
End Sub

Reentrant Function FSum(ByVal n As Byte) As Float
    Dim t As Float
    If n = 0 Then
        Result = 0.0
    Else
        t = FSum(n - 1)
        Result = t + n
    End If
End Function

Reentrant Function Factorial(ByVal n As Byte) As LongWord
    Dim r As LongWord
    If n <= 1 Then
        Result = 1
    Else
        r = Factorial(n - 1)
        Result = r * n
    End If
End Function

Reentrant Function SumFrom(ByRef a() As Integer, ByVal k As Byte) As Integer
    Dim here As Integer
    here = a(k)
    If k = 0 Then
        Result = here
    Else
        Result = here + SumFrom(a, k - 1)
    End If
End Function

Reentrant Function Depth(ByVal n As Byte) As Byte
    Dim mine As Byte
    mine = n
    If n = 0 Then
        Result = 0
    Else
        Result = Depth(n - 1) + 1
    End If
    If mine <> n Then
        Result = 255
    End If
End Function

Interrupt T1()
    IFS0.T1IF = 0
    Inc(seen)
    arr = arr
End Interrupt

ack = Ackermann(2, 3)
Hanoi(10, 1, 2, 3)
fs = Integer(FSum(10)) 
lw = Factorial(12)
For i = 0 To 7
    data(i) = i + 1
Next
arr = SumFrom(data, 7)
seen = Depth(20)
Terminate
