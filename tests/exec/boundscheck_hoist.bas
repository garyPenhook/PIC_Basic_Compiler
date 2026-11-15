' expect: T_A1=5 T_A2=1 T_A3=1 T_A4=3 T_A5=1 T_A6=2 T_A7=3 T_B2=1 T_B3=2 T_B4=7
' expect-O0: T_A1=5 T_A2=1 T_A3=1 T_A4=3 T_A5=1 T_A6=2 T_A7=3 T_B2=1 T_B3=2 T_B4=7
' `#option BoundsCheck` with an index that calls a function or reads a device register: on the left of an
' assignment, in While, ElseIf and Until conditions, and a constant index into a ByRef array parameter, which is clamped to the caller's array at run time.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#option BoundsCheck = true
Dim a1 As Byte
Dim a2 As Byte
Dim a3 As Byte
Dim a4 As Byte
Dim a5 As Byte
Dim a6 As Byte
Dim a7 As Byte
Dim b1 As Byte
Dim b2 As Byte
Dim b3 As Byte
Dim b4 As Byte
Dim arr(5) As Byte
Dim small(3) As Byte
Dim calls As Byte
Dim n As Byte
Dim k As Byte
Dim log As Byte
Dim x As Byte
Function Txt() As String(4)
    Result = "42"
End Function
Function Pick() As Byte
    calls = calls + 1
    Result = 9
End Function
Function F() As Byte
    log = log * 10 + 1
    Result = 1
End Function
Function G() As Byte
    log = log * 10 + 2
    Result = 0
End Function
Sub Put7(ByRef a() As Byte)
    a(20) = 7
End Sub
arr(Pick()) = 5
a1 = arr(4)
a2 = calls
n = 0
While arr(Pick()) = 5 And n < 1
    n = n + 1
Wend
a3 = n
a4 = calls
If calls = 0 Then
    a5 = 9
ElseIf arr(LATA) = 0 Then
    a5 = 1
End If
k = 42
' Inc then Dec: the value is unchanged, but the compiler no longer knows it, so the code below is generated as written (opt::global_value_sets)
Inc(k)
Dec(k)
If k = 1 Then
    a6 = 1
ElseIf Txt() = "42" Then
    a6 = 2
Else
    a6 = 3
End If
If k = 1 Then
    a7 = 1
ElseIf Txt() = "41" Then
    a7 = 2
ElseIf arr(LATA) = 0 Then
    a7 = 3
Else
    a7 = 4
End If
calls = 0
n = 0
Do
    n = n + 1
Loop Until arr(Pick()) = 5 Or n = 2
b2 = calls
small(2) = 0
Put7(small)
b3 = n + 1
b4 = small(2)
End
