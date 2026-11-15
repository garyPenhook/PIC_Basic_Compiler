' expect: T_A1=1 T_A2=0 T_A3=1 T_A4=0 T_A5=2 T_A6=7 T_A7=1
' expect-O0: T_A1=1 T_A2=0 T_A3=1 T_A4=0 T_A5=2 T_A7=1
' expect-18F16Q41: T_A6=0
' expect-18F25K22: T_A6=0
' expect-18F26K22: T_A6=0
' `==` is another spelling of `=` and `!=` of `<>`, in expressions, Case and #if.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a1 As Byte
Dim a2 As Byte
Dim a3 As Byte
Dim a4 As Byte
Dim a5 As Byte
Dim a6 As Byte
Dim a7 As Byte
Dim x As Byte
Dim s As String(8)

x = 5
' Inc then Dec: the value is unchanged, but the compiler no longer knows it, so the code below is generated as written (opt::global_value_sets)
Inc(x)
Dec(x)
s = "abc"
If x == 5 Then
    a1 = 1
End If
If x != 5 Then
    a2 = 1
End If
If s == "abc" And s != "abd" Then
    a3 = 1
End If
a4 = 0
If x == 6 Or s != "abc" Then
    a4 = 1
End If
Select x
    Case == 4
        a5 = 1
    Case != 4
        a5 = 2
End Select
' Set on every part, so it has storage where the #if is false (the 18F16Q41 run).
a6 = 0
#if _device == 18F27Q10 and _clock != 32
a6 = 7
#endif
a7 = 1
