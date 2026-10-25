' expect: T_A=1 T_B=12 T_C=21 T_D=3 T_E=22 T_F=7
' Event variables: reassignment, an unassigned variable (does nothing), two variables of one type,
' a handler with locals, a handler that calls a routine, and comparing a variable with a handler.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Type TCallback = Event()
Dim Cb As TCallback
Dim Cb2 As TCallback
Volatile Dim a As Byte
Volatile Dim b As Byte
Volatile Dim c As Byte
Volatile Dim d As Byte
Volatile Dim e As Byte
Volatile Dim f As Byte
Volatile Dim total As Byte

Sub Add(ByVal x As Byte)
    total = total + x
End Sub
Event AddOne()
    Dim k As Byte
    k = k + 1
    Add(k)
End Event
Event AddTen()
    Add(10)
End Event
Event Nothing2()
    d = d + 1
End Event

Cb()
a = total + 1
Cb = AddOne
Cb()
Cb = AddTen
Cb()
b = total + 1
Cb2 = Cb
Cb = AddOne
Cb2()
c = total
Cb()
Cb = Nothing2
Cb()
Cb()
Cb()
e = total
f = 7
' total = 1 + 10 + 10 + 1 = 22
