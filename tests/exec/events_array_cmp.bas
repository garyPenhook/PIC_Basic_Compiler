' Event arrays and event comparison: a table of handlers called by index, a variable compared with
' a handler and with another variable, and a module-qualified Public variable.
' expect: T_N=111 T_C1=1 T_C2=0 T_C3=1 T_C4=1
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Type TCb = Event()
Dim Tbl(3) As TCb
Dim x As TCb
Dim y As TCb
Dim i As Byte
Volatile Dim n As Byte
Volatile Dim c1 As Byte
Volatile Dim c2 As Byte
Volatile Dim c3 As Byte
Volatile Dim c4 As Byte
Event A()
    n = n + 1
End Event
Event B()
    n = n + 10
End Event
Event C()
    n = n + 100
End Event
Tbl(0) = A
Tbl(1) = B
Tbl(2) = C
For i = 0 To 2
    Tbl(i)()
Next
x = A
y = A
If x = A Then
    c1 = 1
EndIf
If x = B Then
    c2 = 1
EndIf
If x = y Then
    c3 = 1
EndIf
y = B
If x <> y Then
    c4 = 1
EndIf
